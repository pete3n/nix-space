# Host firewall: basic filter policy over the NixOS nftables-mode firewall.
#
# SCOPE. This module configures the filtering every host should have — a
# default-deny input chain, the ports a host opens, what container bridges
# may reach, and a validated place for extra filter rules. Anything beyond
# basic filtering is out of scope on purpose and uses NixOS directly:
#
#   NAT, port forwarding, masquerade   networking.nat
#   Extra tables, custom hooks and     networking.nftables.tables.<name>
#   priorities, mangle, marks, sets,
#   drops that must precede accepts
#
# Both are declarative, both are checked by the same build-time `nft check`,
# and wrapping them here would be a second spelling with no added meaning.
#
# WHY NFTABLES MODE. On NixOS, `iptables` has been iptables-nft since 21.11,
# and kernels from 6.17 do not build the legacy ip_tables backend at all, so
# every iptables invocation on these hosts already produces nf_tables rules.
# Choosing the NixOS firewall's nftables mode means one native `inet nixos-fw`
# table that covers IPv4 and IPv6 together (the previous hand-rolled rules
# were IPv4-only and left IPv6 input open), ordered before the network comes
# up, with the `openFirewall` options of every service working again.
#
# Docker (system mode) and libvirt keep writing their own iptables-nft tables
# beside ours, as they do on every distribution that made this switch. The
# rule that governs how the tables interact: EVERY BASE CHAIN AT A HOOK GIVES
# ITS OWN VERDICT. An `accept` in libvirt's table does not save a packet that
# `nixos-fw` drops. That is why this module, not the host, allows the bridge
# traffic below.
#
# READING THE RESULT. `iptables -L` shows only the iptables-nft tables
# (Docker's, libvirt's) and nothing of nixos-fw; an admin who runs it sees an
# empty firewall while traffic is blocked. `nft list ruleset` shows everything.
{
  config,
  lib,
  ...
}:
let
  cfg = config.nixSpace.networking.firewall;

  libvirtOn = config.virtualisation.libvirtd.enable;
  dockerOn = config.virtualisation.docker.enable; # system mode only; rootless never touches the host firewall

  # nft accepts wildcard interface names ("virbr*"), which a NixOS
  # `interfaces.<name>` entry cannot express, so bridge rules are emitted as
  # rule lines rather than through that option.
  quote = s: ''"${s}"'';
  ifSet = names: "{ ${lib.concatMapStringsSep ", " quote names} }";
  portSet = ports: "{ ${lib.concatMapStringsSep ", " toString ports} }";

  activeBridges =
    lib.optionals libvirtOn cfg.bridges.libvirt
    ++ lib.optionals dockerOn cfg.bridges.docker;

  # What a libvirt NAT network needs from the host: dnsmasq on the bridge
  # answers the guests' DNS (53 udp/tcp) and DHCP (67 udp).
  libvirtInputRules = lib.optionalString (libvirtOn && cfg.bridges.libvirt != [ ]) ''
    iifname ${ifSet cfg.bridges.libvirt} udp dport { 53, 67 } accept comment "libvirt guest DNS/DHCP"
    iifname ${ifSet cfg.bridges.libvirt} tcp dport 53 accept comment "libvirt guest DNS over TCP"
  '';

  # Host services containers and guests may reach, on every active bridge.
  containerInputRules =
    let
      hs = cfg.hostServicesFromContainers;
    in
    lib.optionalString (activeBridges != [ ]) (
      lib.optionalString (hs.tcpPorts != [ ]) ''
        iifname ${ifSet activeBridges} tcp dport ${portSet hs.tcpPorts} accept comment "host services from containers"
      ''
      + lib.optionalString (hs.udpPorts != [ ]) ''
        iifname ${ifSet activeBridges} udp dport ${portSet hs.udpPorts} accept comment "host services from containers"
      ''
    );

  # With filterForward on, NAT'd bridge traffic must be let through the
  # forward chain too. Return traffic is covered by the chain's own
  # established/related rule.
  bridgeForwardRules = lib.optionalString (cfg.filterForward && activeBridges != [ ]) ''
    iifname ${ifSet activeBridges} accept comment "container/guest egress"
  '';
in
{
  options.nixSpace.networking.firewall = {
    enable = lib.mkEnableOption "the host firewall (NixOS firewall in nftables mode)";

    filterForward = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Filter forwarded traffic (policy drop on the forward hook).

        Off by default: a workstation forwards only for its own containers
        and guests, whose NAT tools expect the forward path open. A gateway
        turns this on and states what it forwards in extraRules.forward.
        When on, this module already allows egress from the active
        container and guest bridges.
      '';
    };

    allowPing = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Answer ICMP echo requests.";
    };

    logRefused = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Log refused connections to the journal (`journalctl -k | grep refused`).
        Useful while bringing a host up; noisy on an exposed one.
      '';
    };

    bridges = {
      libvirt = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ "virbr*" ];
        description = ''
          Interface patterns of libvirt NAT networks. Applied only when
          virtualisation.libvirtd is enabled. The default covers every
          libvirt-managed bridge; narrow it to "virbr0" for the default
          network only.
        '';
      };

      docker = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [
          "docker0"
          "br-*"
        ];
        description = ''
          Interface patterns of system-mode Docker bridges. Applied only when
          virtualisation.docker is enabled (rootless Docker does its
          networking in user space and needs nothing here). docker0 is the
          default bridge; user-defined and compose networks get br-<id>.
        '';
      };
    };

    hostServicesFromContainers = {
      tcpPorts = lib.mkOption {
        type = lib.types.listOf lib.types.port;
        default = [ ];
        example = [ 11434 ];
        description = ''
          TCP ports on the host that containers and guests may reach over
          the active bridges — an Ollama instance a container calls, for
          example. Scoped to the bridge interfaces; nothing is opened to
          the LAN.
        '';
      };

      udpPorts = lib.mkOption {
        type = lib.types.listOf lib.types.port;
        default = [ ];
        description = "As tcpPorts, for UDP.";
      };
    };

    extraRules = {
      input = lib.mkOption {
        type = lib.types.lines;
        default = "";
        example = ''
          iifname "eth0" tcp dport 8080 ct state new accept
        '';
        description = ''
          Extra nftables rules appended to the input allow chain, after the
          allowed-port rules and before the final drop. Checked by
          `nft check` at build time, so a malformed rule fails the build.

          Written in nft syntax. An iptables rule translates mechanically:

            iptables-translate -A INPUT -i eth0 -p tcp --dport 8080 -j ACCEPT
            => nft add rule ip filter INPUT iifname "eth0" tcp dport 8080 counter accept

          The part after INPUT is the line to put here. For a saved
          ruleset, `iptables-restore-translate -f rules.v4`.

          This chain can only ACCEPT (or log). A rule that must drop before
          the accepts belongs in its own table at a lower priority:
          networking.nftables.tables.<name>.
        '';
      };

      forward = lib.mkOption {
        type = lib.types.lines;
        default = "";
        example = ''
          iifname "wlan0" oifname "eth0" accept
        '';
        description = ''
          Extra nftables rules appended to the forward allow chain. Only
          meaningful with filterForward = true, which an assertion enforces
          so these lines cannot be silently dead.
        '';
      };
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.extraRules.forward == "" || cfg.filterForward;
        message = ''
          nixSpace.networking.firewall.extraRules.forward is set but
          filterForward is false. Without filterForward the forward chain
          is not created and these rules would never be evaluated.
          Set filterForward = true, or remove the rules.
        '';
      }
    ];

    networking.nftables.enable = true;

    networking.firewall = {
      enable = true;
      inherit (cfg) allowPing filterForward;
      logRefusedConnections = cfg.logRefused;

      extraInputRules = libvirtInputRules + containerInputRules + cfg.extraRules.input;
      extraForwardRules = bridgeForwardRules + cfg.extraRules.forward;
    };
  };
}
