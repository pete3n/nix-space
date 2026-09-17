# Nix snowflake widget for waybar: OS, kernel, and nix version in a tooltip,
# with hyprsysteminfo on right-click.
#
# Same shape as calendar.nix and pomodoro.nix — the widget, its script, and
# its dependencies together, contributed to nixSpace.waybar.modules when
# enabled. The bundle places it; this file defines it.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.nixSpace.hyprdesktop.snowflake;

  # writeShellApplication rather than writeShellScriptBin: shellcheck at
  # build time, and errexit/nounset/pipefail set by the wrapper rather than
  # by hand. runtimeInputs replaces the per-command store paths the old
  # version spelled out.
  #
  # `nix` is deliberately NOT in runtimeInputs. Pinning it would report the
  # version nixpkgs ships rather than the daemon actually running, which is
  # the number that matters. It resolves from the session PATH, and the
  # fallback covers a session where it is absent.
  nixInfo = pkgs.writeShellApplication {
    name = "nix-info";
    runtimeInputs = with pkgs; [
      coreutils
      gnugrep
      jq
    ];
    text = # sh
      ''
        _kernel="$(uname -r)"
        _nix="$(nix --version 2>/dev/null || printf 'nix: unknown')"
        _os_title=""

        if [ -r /etc/os-release ]; then
          _os="$(grep '^NAME=' /etc/os-release | cut -f2 -d= | tr -d '"')"
          _os_ver="$(grep '^VERSION=' /etc/os-release | cut -f2 -d= | tr -d '"')"
          _os_title="''${_os}: ''${_os_ver}"
        fi

        # \r rather than \n: waybar renders tooltips as Pango markup, where a
        # literal newline in JSON is collapsed but a carriage return breaks
        # the line.
        jq -c -n \
          --arg os "''${_os_title}" \
          --arg kernel "Kernel: ''${_kernel}" \
          --arg nix "''${_nix}" \
          '{ "text": "", "tooltip": "\($os)\r\($kernel)\r\($nix)" }'
      '';
  };
in
{
  options.nixSpace.hyprdesktop.snowflake = {
    enable = lib.mkEnableOption "the nix snowflake waybar widget";
  };

  config = lib.mkIf cfg.enable {
    nixSpace.waybar.modules."custom/snowflake" = {
      style = ''
        #custom-snowflake {
          padding: 0 12px 0 10px;
          font-size: 16px;
        }
      '';

      format = "❄️";
      return-type = "json";
      tooltip = true;
      exec = lib.getExe nixInfo;

      # Hourly. The values change only on a rebuild, and a shorter interval
      # spawns nix --version repeatedly for nothing.
      interval = 3600;

      on-click = "${lib.getExe pkgs.libnotify} 'Nix Info' \"$(${lib.getExe nixInfo} | ${lib.getExe pkgs.jq} -r '.tooltip')\"";
      on-click-right = lib.getExe' pkgs.hyprsysteminfo "hyprsysteminfo";
    };

    home.packages = [
      nixInfo
      pkgs.hyprsysteminfo
    ];
  };
}
