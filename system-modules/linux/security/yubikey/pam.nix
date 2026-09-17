# Per-service authentication policy module.
#
# This file decides WHICH factors a PAM service accepts. It never decides HOW.
# Rule ordering, module paths, and arguments come from nixpkgs' rule stack,
# whose default auth order is already
#
#   ssh-agent -> u2f -> fingerprint -> password (pam_unix) -> deny
#
# with each factor `sufficient`, so the first that succeeds ends the stack.
# That is the order the old yk-fprint.nix re-implemented by hand with
# `text = mkForce`, discarding faillock, pam_env, and the password fallback
# along the way. Anything in this file that needs `text` or a hand-rolled
# order is a smell.
#
# Verify the generated stack rather than trusting this comment:
#
#   nix eval --raw .#nixosConfigurations.<host>.config.security.pam.services.sudo.text
#
# Each line ends in `# <rule> (order N)`. If the rssh rule ever lands after
# `unix`, pin it relative to u2f:
#
#   security.pam.services.sudo.rules.auth.<rssh rule name>.order =
#     config.security.pam.services.sudo.rules.auth.u2f.order - 10;
#
# The rules API is experimental and hidden, and nixpkgs warns that built-in
# order values can change between releases, so never use a constant.
#
# Services NOT listed keep nixpkgs defaults. One of those defaults bites:
# services.fprintd.enable turns fingerprint on for EVERY service. A laptop
# that wants fprint on sudo but not login must list login explicitly. Listing
# a service is how a decision becomes visible.
#
# The old yk-sshd.nix skipped u2f on pseudo-terminals so an SSH session would
# not wait on a key plugged into the REMOTE. With sshAgent on sudo that skip
# is unnecessary: in an SSH session the forwarded agent answers first, and
# pam_u2f fails fast when no local device is present. The remaining edge —
# a key physically in the remote while you are logged in from elsewhere —
# is the case the order pin above handles.
#
#
# POLICY REFERENCE
#
# Stack order comes from nixpkgs and is fixed (verify with nix eval; the
# generated file carries `# name (order N)` on every line):
#
#   sshAgent (rssh) -> u2f -> fprint -> password (unix) -> deny
#
# PAM control keywords, as they apply here:
#   sufficient  success ENDS the stack with success at once (unless an
#               earlier `required` already failed); failure is ignored and
#               the next line runs. This is an OR.
#   required    failure is RECORDED but the stack keeps running, so the
#               user still sees later prompts and cannot tell which factor
#               failed; the final result is failure. Success just continues.
#               This is an AND with whatever succeeds later.
#   requisite   like required, but failure ends the stack immediately.
#               Not exposed by this module; add it to the u2f enum if the
#               required-form delay is unwanted.
#
# Everything this module emits is `sufficient` except u2f = "required".
# nixpkgs always ends the auth stack with `pam_deny required`, so:
#
#   A USABLE STACK NEEDS AT LEAST ONE `sufficient` FACTOR AFTER ANY
#   `required` ONE. `u2f = "required"` with fprint and password both off
#   reaches pam_deny with nothing able to return success: always denied.
#
# Options per service:
#   u2f       null | "sufficient" | "required"   (default "sufficient")
#   u2fPin    null | true | false   PIN on top of the touch; overrides the
#                                   credential's enrolment flag
#   fprint    bool                  pam_fprintd, sufficient
#   sshAgent  bool                  pam_rssh, sufficient; the only hardware
#                                   path inside an SSH session
#   password  bool                  pam_unix, sufficient (default true)
#
# Combinations (touch = YubiKey presence; finger = fingerprint):
#   { }                                       touch  OR password
#   { fprint = true; }                        touch  OR finger  OR password
#   { fprint = true; password = false; }      touch  OR finger      (never password)
#   { u2f = null; fprint = true; }            finger OR password   (no key)
#   { u2f = "required"; }                     touch AND password
#   { u2f = "required"; fprint = true; }      touch AND (finger OR password)   2FA
#   { u2f = "required"; fprint = true;
#     password = false; }                     touch AND finger
#   { u2f = "required"; u2fPin = true; ... }  (touch + PIN) AND ...  — PIN is
#                                             knowledge on the token itself
#
# sshAgent caveat: rssh sits BEFORE u2f and is sufficient, so a forwarded
# agent signature alone satisfies the stack even when u2f = "required".
#   { u2f = "required"; sshAgent = true; fprint = true; }
#     = agent signature  OR  (touch AND (finger OR password))
# That is intended for remote sudo (the touch happens on the client's key),
# but it means sshAgent turns a 2FA policy into "2FA locally, one hardware
# factor remotely". Decide that consciously per host.
{
  config,
  lib,
  ...
}:
let
  cfg = config.nixSpace.security.yubikey;
  pcfg = cfg.pam;

  services = lib.attrValues pcfg.services;
  anyU2f = lib.any (s: s.u2f != null) services;
  anyFprint = lib.any (s: s.fprint) services;

  serviceModule = {
    options = {
      u2f = lib.mkOption {
        type = lib.types.nullOr (
          lib.types.enum [
            "sufficient"
            "required"
          ]
        );
        default = "sufficient";
        description = ''
          pam_u2f control for this service, or null to leave it out.

          "sufficient": a touch authenticates; without a key the stack
          continues to the next factor.

          "required": the key is mandatory and the remaining factors still
          run afterwards. A lost key means no access to this service. Enrol
          a backup token before considering it.
        '';
      };

      u2fPin = lib.mkOption {
        type = lib.types.nullOr lib.types.bool;
        default = null;
        description = ''
          Override the credential's PIN requirement for this service.

          null uses whatever was baked in at enrolment (+presence is touch
          only; +pin demands a PIN). true or false pass pinverification=1 or
          0 to pam_u2f, so login can require a PIN while sudo takes a touch,
          with the same enrolment.
        '';
      };

      fprint = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = ''
          Accept a fingerprint via pam_fprintd. Needs services.fprintd.enable,
          which is hardware-conditional and belongs to a hardware tag, not to
          this policy.
        '';
      };

      sshAgent = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = ''
          Accept a signature from the calling user's ssh-agent via pam_rssh.

          Over SSH with agent forwarding this is a touch on the key plugged
          into the CLIENT. Locally it asks whatever SSH_AUTH_SOCK points at.
          Key sources are configured in nixSpace.security.yubikey.sshAgent.
        '';
      };

      password = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = ''
          Keep the pam_unix password fallback. Turning it off with no other
          factor is refused by an assertion: the stack would be pam_deny alone.
        '';
      };
    };
  };
in
{
  options.nixSpace.security.yubikey.pam.services = lib.mkOption {
    type = lib.types.attrsOf (lib.types.submodule serviceModule);
    default = { };
    example = lib.literalExpression ''
      {
        sudo = { sshAgent = true; fprint = true; };
        login = { fprint = false; u2fPin = true; };
        hyprlock = { fprint = true; };
        polkit-1 = { };
      }
    '';
    description = ''
      PAM services under YubiKey policy. Each renders to
      security.pam.services.<name>.{u2f, fprintAuth, rssh, unixAuth}; nothing
      here writes `text`. Unlisted services keep nixpkgs defaults.
    '';
  };

  config = lib.mkIf (cfg.enable && pcfg.services != { }) {
    assertions =
      lib.concatLists (
        lib.mapAttrsToList (name: svc: [
          {
            assertion = svc.password || svc.u2f != null || svc.fprint || svc.sshAgent;
            message = ''
              nixSpace.security.yubikey.pam.services.${name} disables the password
              and enables no other factor. The generated stack would be pam_deny
              only, and ${name} would be unusable.
            '';
          }
          {
            assertion = svc.u2f != "required" || svc.fprint || svc.password;
            message = ''
              nixSpace.security.yubikey.pam.services.${name} sets u2f = "required"
              with no sufficient factor after it. nixpkgs ends the stack with
              pam_deny, so nothing can return success: ${name} would always deny.
              Enable fprint or password alongside it.
            '';
          }
        ]) pcfg.services
      )
      ++ [
        {
          assertion = !anyU2f || cfg.u2f.enable;
          message = ''
            A nixSpace.security.yubikey.pam service enables u2f, but
            nixSpace.security.yubikey.u2f is not enabled, so pam_u2f would
            run with no origin and no credentials.
          '';
        }
        {
          assertion = !anyFprint || config.services.fprintd.enable;
          message = ''
            A nixSpace.security.yubikey.pam service enables fprint, but
            services.fprintd is not enabled. Enable it from the hardware
            tag for this host; the policy does not own the daemon.
          '';
        }
      ];

    security.pam.services = lib.mapAttrs (_: svc: {
      u2f.enable = svc.u2f != null;
      u2f.control = lib.mkIf (svc.u2f != null) svc.u2f;
      fprintAuth = svc.fprint;
      rssh = svc.sshAgent;
      unixAuth = svc.password;

      # A per-service argument on nixpkgs' own u2f rule. settings is an attrset
      # merged by name, so this adds one token without redefining the rule.
      rules.auth.u2f.settings.pinverification = lib.mkIf (svc.u2fPin != null) (
        if svc.u2fPin then 1 else 0
      );
    }) pcfg.services;

    # pam_rssh reads the calling user's SSH_AUTH_SOCK, which sudo strips
    # unless told otherwise. Set here rather than relying on nixpkgs to do
    # it for rssh; a duplicate env_keep line is harmless.
    security.sudo.extraConfig =
      lib.mkIf ((pcfg.services.sudo.sshAgent or false) && config.security.sudo.enable)
        ''
          Defaults env_keep+=SSH_AUTH_SOCK
        '';
  };
}
