# Incremental migration

Order: **system (Phase A) → flake (Phase B) → tags (Phase C)**. Each step is
one change with a predicted diff. Nothing from `user-flake/` or `wiring/` is
applied wholesale; those are the end state the steps converge on.

## Method

```
snapshot.sh   once, before anything     -> snapshot-<date>/, result-0
edit          one step
build-diff.sh <flake> N                 -> result-N, diff vs result-(N-1)
compare       the diff to the step's prediction; stop if it differs
nixos-rebuild test --flake <flake>      -> activates without a boot entry
verify        the step's check
nixos-rebuild switch                    -> only now
```

Two rules that make this safe:

- **Refactors must produce an empty diff.** `nvd diff` shows nothing and
  `diff -r result-N-1/etc result-N/etc` is silent. Any output means the
  refactor changed behavior; find out why before switching.
- **Before any PAM change, open a root shell and leave it open**
  (`sudo -i` in a second terminal). If the new stack is wrong, that shell
  fixes it without a reboot. `nixos-rebuild test` first; the previous
  generation's boot entry is the fallback after `switch`.

nix-space is imported from the working tree by absolute path today, so an
edit there is live on the next rebuild with no lock update. Convenient for
this phase; it is the version skew Phase B closes.

The framework-dt track runs the same A1–A5 in parallel: it needs the
*server* half of pam_rssh (A5) before silver16 can drop USB/IP (A6).

---

## Phase A — system, under the old flake and makeNix library

Every edit below is to the CURRENT `configuration.nix` (makeNixLib /
makeNixAttrs args unchanged) or to nix-space.

### A0 — Snapshot

```sh
./snapshot.sh .#nixosConfigurations.<host>
```

Read `options.txt`. Three answers steer what follows:

| Fact | If yes | If no |
|---|---|---|
| `security.pam.u2f.enable = true` | something global enables u2f; A2 must remove that definition in the same step | A2 is purely additive |
| `u2f-line.txt` non-empty | note its `origin=`; A2 reuses it verbatim | credentials were enrolled with whatever `-o` you gave `pamu2fcfg`; A2 probes |
| `per-service u2f.control` / `rssh` exist | proceed | see the contingency under A1 |

### A1 — Land the module, import it, enable nothing

**Change.** Copy the directory `system-modules/linux/security/yubikey/`
(five files: `default.nix`, `base.nix`, `u2f.nix`, `pam.nix`,
`ssh-agent.nix`) into nix-space at that path. In `configuration.nix`
imports:

```nix
"${nixSpace}/system-modules/linux/security/yubikey"
```

**Predicted diff.** Empty. Importing declares options; `enable` is false.

**Why this step exists.** It tests the module's assumptions about your
nixpkgs pin with nothing at stake. The module system checks that every
defined option *exists* even under `mkIf false`, so if the pin lacks
`security.pam.rssh` the build fails here with "does not exist" — the
cheapest possible place to learn it.

**Contingency.** If A1 fails on `security.pam.rssh`: comment `./ssh-agent.nix`
out of the module's `default.nix` and defer A5 until the pin has it. If A0
said `per-service u2f.control` is NO: in `pam.nix` replace `u2f.enable` /
`u2f.control` with `u2fAuth = svc.u2f != null;` and drop per-service control
(all services then use the global `security.pam.u2f.control`).

**Verify.** `nix eval <flake>.config.nixSpace.security.yubikey.enable` → `false`.

### A2 — pam_u2f on sudo through the new module, same behavior as today

**Change.** In `configuration.nix`:

```nix
nixSpace.security.yubikey = {
  enable = true;
  u2f = {
    enable = true;
    origin = "pam://<ORIGIN>";   # from u2f-line.txt, else the -o you enrolled with
    # users = {};                # deliberately empty: per-user file stays for now
  };
  pam.services.sudo = { };       # u2f sufficient, password kept, no fprint yet
};
```

If A0 showed a global `security.pam.u2f.enable = true`, remove that
definition now (it is what made u2f apply to every service).

**Predicted diff.** Packages: +pam_u2f, +libfido2, +pamtester. `/etc`: only
`pam.d/sudo`, one `pam_u2f.so` line with `origin=`, `appid=`, `cue`, control
`sufficient`, positioned before `pam_unix`. If u2f was global before,
`pam.d/login` and others *lose* their u2f line — expected and intended.

**Verify.**

```sh
pamtester sudo "$USER" authenticate     # touch -> "successfully authenticated"
# unplug the key
pamtester sudo "$USER" authenticate     # falls to password; must still succeed
```

If the origin is unknown, try candidates with pamtester; a wrong origin
fails cleanly to the password prompt, so this probe cannot lock you out.

### A3 — Central mapping and realm origin

Only if the origin changes (e.g. `pam://silver16` → `pam://p22`) is
re-enrolment needed; the credential embeds the origin.

**Change.** Enrol both tokens once at the realm origin, then:

```nix
u2f = {
  enable = true;
  origin = "pam://p22";
  users.pete = [ "<line from pamu2fcfg -n -o pam://p22 -i pam://p22, key 1>"
                 "<same, key 2>" ];
};
```

**Predicted diff.** `/etc/u2f_mappings` appears (mode 0444, one `pete:` line);
`pam.d/sudo` gains `authfile=/etc/u2f_mappings`. Nothing else.

**Verify.** `pamtester` as in A2, both tokens. Then in home-manager, delete
the `nixSpace.security.yubikey.u2f` block from `home.nix` and apply the
patched HM `yubikey.nix` (`home/security/yubikey.nix` — it removes the `u2f`
option and adds `agent`, still disabled). HM diff: `~/.config/Yubico/u2f_keys`
disappears; nothing else. Re-run pamtester: the central file is now the only
source.

### A4 — Policy on the other services

**Change.** Extend `pam.services`; delete the old `security.pam.services`
block (its `login.fprintAuth` was never applied — the `// lib.mkIf`
discarded it).

```nix
pam.services = {
  sudo     = { fprint = <true if fprintd runs>; };
  login    = { u2f = null; fprint = <same>; };
  polkit-1 = { };
  hyprlock = { };     # if hyprland
};
```

**Predicted diff.** `pam.d/login`, `polkit-1`, `hyprlock` only. `hyprlock`
may be a *new* file if nothing created it before — check
`pam.d-listing.txt` from the snapshot.

**Verify.** With the root shell open: lock and unlock (touch, then
fingerprint, then password); trigger a polkit prompt (`systemctl restart
sshd` from a user shell); log in on TTY2.

### A5 — pam_rssh on sudo, fleet agent at home

System half:

```nix
users.users.pete.openssh.authorizedKeys.keys = [ "sk-ssh-ed25519@openssh.com AAAA..." ];
nixSpace.security.yubikey.pam.services.sudo.sshAgent = true;
```

**Predicted diff.** `/etc/ssh/authorized_keys.d/pete` appears; `pam.d/sudo`
gains a `libpam_rssh.so` line (note its position relative to `pam_u2f` in
the `# name (order N)` comments); `sudoers` gains `env_keep+=SSH_AUTH_SOCK`.
Packages: +pam_rssh.

Home half: `nixSpace.security.yubikey.agent.enable = true`, and in the p22
ssh blocks replace `IdentityAgent = "none"` with the socket plus
`ForwardAgent = true; AddKeysToAgent = "yes";` (see
`home/security/ssh-fleet.example.nix`). HM diff: `fleet-ssh-agent.service`
in `~/.config/systemd/user/`, and `~/.ssh/config`.

**Verify, locally first** (no second machine involved):

```sh
systemctl --user status fleet-ssh-agent
ssh-add -K                                              # or: ssh framework-dt true (AddKeysToAgent loads it)
SSH_AUTH_SOCK="$XDG_RUNTIME_DIR/fleet-agent.sock" ssh-add -l   # exactly the p22 key
SSH_AUTH_SOCK="$XDG_RUNTIME_DIR/fleet-agent.sock" pamtester sudo "$USER" authenticate   # touch
SSH_AUTH_SOCK=/nonexistent pamtester sudo "$USER" authenticate  # falls through to u2f/password
```

Then from framework-dt, once it has done A5 too: `ssh silver16 sudo -v` —
one touch on the key plugged into dt.

### A6 — Remove the old USB/IP modules

Precondition: framework-dt has A5, so it no longer needs the shared key.

**Change.** Remove `outputs.nixosModules.yubikeyUsbipServer` from imports and
the `yubikeyUsbipServer.enable` line. There is no replacement module; pam_rssh
(A5) is the replacement. The `yubi-usbip-*` tags and the `usbip-role`
exclusive group in `tag-registry.nix` go with them in Phase C.

**Predicted diff.** Packages: −yk-ssh, −usbip. `sudoers` loses the two
NOPASSWD rules. `tmpfiles.d` loses `/run/yk-usbip-server`.

**Verify.** `sudo -l` shows no NOPASSWD entries; `command -v yk-ssh` empty.
On framework-dt: remove the client module the same way.

### A7 — Refactors, each with an empty diff

One at a time, in this order, each proven by `build-diff.sh` printing no
package change and no `/etc` change:

1. `// lib.mkIf` → `lib.optionalAttrs` anywhere it remains
   (`services // lib.optionalAttrs` is already correct; the pam block was
   the only wrong one and A4 deleted it).
2. fw16 quirks (`fw16*`, `lidmond`, kernel pin, `kernelParams`, fw16
   packages) → nix-space `system-modules/hardware/framework16`. Import it
   from `configuration.nix` for now; the flake imports it in Phase B.
3. `fileSystems."/data"` → nix-space `hosts/silver16` beside the installer
   config. Then drop the local `./hardware-configuration.nix` import —
   **after** `diff` shows the nix-space copy identical.
4. `services.resolved` p22 block → `infrax/p22/p22-dns.nix`.
5. `age.secrets` + the agenix PATH export → `secrets.nix`; check
   `users/pete/secrets/yubi-age.nix` in nix-space doesn't already export it.
6. `enable = true` → `hasTag "<tag>" makeTags` where the tag is present in
   the attrs (`local-ai`, `crypto`, `laptop`, `virtualisation`). Same tag
   present = same value = empty diff. Tags that are absent today
   (`hyprdesktop`, `hw-fprint`) wait for Phase C.

---

## Phase B — flake

B1. New flake from `user-flake/flake.nix`, but with `attrs.fromFile` on the
single attrs file (the shape of your partially-migrated one, bugs fixed), and
a `flake.lock` whose inputs match the old lock. `build-diff.sh` across the
two flakes: the only acceptable diff is from inputs you knowingly changed.
`nix flake metadata` on both, compare the locked revs.

B2. Rename args: `makeNixLib`/`makeNixAttrs` → `nixSpaceLib`/`nixSpaceAttrs`,
`makeNixLib.hasTag` → `nixSpaceLib.tags.hasTag`, absolute nix-space path →
`inputs.nixSpace`. Empty diff.

B3. `fromFile` → `fromDir ./attrs`; add `hosts/<host>/{system,home}.nix` and
move A7's leftovers into them. Empty diff.

## Phase C — tags

C1. Registry and schema (`lib/tag-registry.nix`, `lib/validate-attrs.nix`
patches). Add `hyprdesktop`, `hw-fprint`, `ssh-user`, `yubi-ssh-agent` to the
attrs; move the two credential lines into `u2fCredentials`. `nix flake check`
validates the attrs file — that is the whole test.

C2. Wiring modules replace the explicit `nixSpace.security.yubikey = {…}`
block from A2–A5. Empty diff, because the wiring computes the same values
from the tags. If it isn't empty, the wiring disagrees with what you set by
hand — and the diff says exactly where.

C3. Same for `linux-user.nix` taking over `users.users.pete`, groups, and
`authorizedKeys` from `sshPubKeys`. Empty diff.

---

## Which files from the earlier revision apply where

| Step | File |
|---|---|
| A1 | `system-modules/linux/security/yubikey/` (five files) |
| A3 | `home/security/yubikey.nix`, `home/security/gpg.nix` |
| A5 | `home/security/ssh-fleet.example.nix` |
| A7.2 | `user-flake/hosts/silver16/system.nix` — as the *source* of what moves, not as a file to import |
| B1–B3 | `user-flake/flake.nix`, `configuration.nix`, `home.nix`, `secrets.nix`, `cache-config.nix` |
| C1 | `lib/tag-registry.nix`, `lib/validate-attrs.nix`, `user-flake/attrs/pete@silver16.nix` |
| C2 | `wiring/nixos-yubikey.nix`, `wiring/home-yubikey.nix` |

