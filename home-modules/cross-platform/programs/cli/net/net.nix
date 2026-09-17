# Networking and remote access CLI tool module.
#
# TODO: extract a nixSpace.programs.vpn module. openvpn3 is not a drop-in
# replacement for openvpn: it is D-Bus based, with system services
# (openvpn3-service-*) plus per-user sessions, so it needs NixOS and
# home-manager sides configured together and gated by a shared tag.
# openvpn and wireguard options below should move to a separate VPN module.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.nixSpace.programs.net;

  # --add-flags rather than a shell alias: an alias exists only in an
  # interactive shell, so any script, cron job, or `sh -c` invocation would
  # silently fall back to the public relay. The wrapper travels with the
  # binary.
  wormholeWrapped = pkgs.symlinkJoin {
    name = "magic-wormhole-relay";
    paths = [ pkgs.magic-wormhole ];
    nativeBuildInputs = [ pkgs.makeWrapper ];
    postBuild = ''
      wrapProgram $out/bin/wormhole \
        --add-flags "--relay-url=${cfg.wormhole.relayUrl}"
    '';
  };

  openvpnPackage =
    if cfg.openvpn.pkcs11Support then pkgs.openvpn.override { pkcs11Support = true; } else pkgs.openvpn;

  isLinux = pkgs.stdenv.hostPlatform.isLinux;
in
{
  options.nixSpace.programs.net = {
    enable = lib.mkEnableOption "networking and remote access CLI tools";

    mosh = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Roaming SSH replacement that survives suspend and address changes.

        The client works from this package alone. Accepting INCOMING mosh
        sessions additionally needs UDP 60000-61000 open, which is a system
        concern: `programs.mosh.enable = true` in the NixOS configuration
        does it. Without that, outbound sessions work and inbound ones hang
        after the SSH handshake succeeds, which reads as a mosh bug rather
        than a firewall one.

        mosh-server also refuses to start without a UTF-8 locale, reporting
        that it needs one rather than failing obscurely.
      '';
    };

    wormhole = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Transfer files between machines using a short code phrase.";
      };

      rust = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = ''
          Also install the Rust implementation (magic-wormhole-rs), which is
          faster and has no Python runtime.

          It is a separate binary rather than a replacement, so both can be
          installed. If the two ever ship the same executable name, activation
          fails with a buildEnv collision — loudly, not silently.
        '';
      };

      relayUrl = lib.mkOption {
        type = lib.types.str;
        default = "wss://mailbox.mw.leastauthority.com/v1";
        description = ''
          Mailbox relay to use, applied by wrapping the binary.

          The default is Least Authority's relay rather than the project's
          public one. The relay sees connection metadata and the encrypted
          blobs, never the plaintext, so the code phrase never reaches it.
          This is a load and availability choice, not a confidentiality one.

          Applied via --add-flags, so it is passed on every invocation.
          Overriding it for a single run means checking that the CLI takes the
          last occurrence of a repeated flag; it is not guaranteed to.
        '';
      };
    };

    diagnostics = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Install dig, mtr, and iperf3.

        Not in the original package list — added because the failures this
        fleet actually hits are DNS resolution on the .p22 domain, path
        problems to the NFS host, and throughput questions on remote builds.
        dig distinguishes REFUSED from unreachable, mtr shows which hop is
        losing packets, and iperf3 separates a slow link from a slow service.

        mtr needs root for ICMP mode on darwin, and for raw sockets on Linux
        unless the binary carries CAP_NET_RAW.
      '';
    };

    bandwhich = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Per-process network utilisation monitor.

        Requires elevated privileges to read socket tables: expect to run it
        under sudo. The package alone grants nothing, and unprivileged it
        reports an empty table rather than a permissions error.
      '';
    };

    openvpn = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = ''
          OpenVPN 2.x client.

          Creating a tun/tap device and rewriting routes needs root, so this is
          invoked under sudo.
        '';
      };

      pkcs11Support = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = ''
          Build OpenVPN with pkcs11-helper, for certificates held on a
          smartcard or YubiKey PIV applet.

          This is an override, so the result is not the binary the cache has:
          enabling it means compiling OpenVPN locally.

          The build only makes the capability available. Using it needs
          --pkcs11-providers pointing at a provider library: pkgs.opensc's
          opensc-pkcs11.so, which is not pulled in here.
        '';
      };
    };

    wireguard = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        wireguard-tools: wg and wg-quick.

        Tools only. wg-quick reads /etc/wireguard/<iface>.conf, which is
        root-owned system state: this installs no tunnels and no keys. For
        declarative tunnels, the config belongs in networking.wireguard.* with
        the private key delivered through agenix/sops rather than written into 
        a world-readable store path.

        On darwin there is no kernel implementation; wg-quick drives
        wireguard-go in userspace, which has to be present separately.
      '';
    };

    wireless = lib.mkOption {
      type = lib.types.bool;
      default = pkgs.stdenv.hostPlatform.isLinux;
      defaultText = lib.literalExpression "pkgs.stdenv.hostPlatform.isLinux";
      description = ''
        Wireless tooling: iw and wpa_supplicant.

        Linux-only: both speak nl80211, which has no darwin equivalent.

        For manual connection management: `wpa_supplicant -i <iface> -c
        <conf> -B`, rather than a managed daemon. That means no unit and no
        D-Bus service, so nothing here conflicts with a system that has
        networking.wireless or NetworkManager switched off.

        wpa_passphrase ships in the same package, for generating a config
        stanza from an SSID and passphrase.

        `iw list` reports what the driver actually advertises.
      '';
    };

    extraPackages = lib.mkOption {
      type = lib.types.listOf lib.types.package;
      default = [ ];
      example = lib.literalExpression "[ pkgs.croc pkgs.gping ]";
      description = "Additional networking tools, without an option each.";
    };
  };

  config = lib.mkIf cfg.enable {
    home.packages =
      (
        with pkgs;
        [
          browsh
          lynx
          w3m
          ddgr
          socat
          speedtest-rs
          sshs
          whois
        ]
        ++ lib.optional isLinux pkgs.netcat-openbsd
      )
      ++ lib.optional cfg.mosh pkgs.mosh
      ++ lib.optional cfg.bandwhich pkgs.bandwhich
      ++ lib.optional cfg.wormhole.enable wormholeWrapped
      ++ lib.optional (cfg.wormhole.enable && cfg.wormhole.rust) pkgs.magic-wormhole-rs
      ++ lib.optionals cfg.diagnostics (
        with pkgs;
        [
          bind.dnsutils
          iperf3
          knot-dns # kdig for DNS-over-TLS and DNS-over-HTTPS
          mtr # improved traceroute
          tcpdump
        ]
        ++ lib.optional isLinux pkgs.ethtool
      )
      ++ lib.optionals cfg.wireless
      &&
        isLinux (
          with pkgs;
          [
            iw
            wpa_supplicant
          ]
        )
        ++ lib.optional cfg.openvpn.enable openvpnPackage
        ++ lib.optional cfg.wireguard pkgs.wireguard-tools
        ++ cfg.extraPackages;
  };
}
