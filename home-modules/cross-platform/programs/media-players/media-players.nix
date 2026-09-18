# Media playback, transcoding, and capture module.
#
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.nixSpace.programs.mediaPlayers;
  isLinux = pkgs.stdenv.hostPlatform.isLinux;
in
{
  options.nixSpace.programs.mediaPlayers = {
    enable = lib.mkEnableOption "media playback, transcoding, and capture tools";

    videoPlayer = lib.mkOption {
      type = lib.types.nullOr lib.types.package;
      default = if pkgs.stdenv.hostPlatform.isLinux then pkgs.vlc else null;
      defaultText = lib.literalExpression "pkgs.vlc on Linux, null otherwise";
      description = ''
        Video player, and the owner of that choice fleet-wide.

        Other modules read this rather than naming a player of their own.
        Yazi's video opener and the video MIME associations below both use
        it, so changing it here changes it everywhere rather than in three
        files that can drift apart.

        null installs no player and contributes no associations, for a host
        that transcodes video without playing it.
      '';
    };

    videoPlayerDesktopFile = lib.mkOption {
      type = lib.types.str;
      default = "vlc.desktop";
      description = ''
        The .desktop filename for videoPlayer, used for MIME associations.

        Not derivable from the package: a desktop file's basename follows no
        rule that can be computed from a derivation, and naming one that does
        not exist leaves the association inert with no error — the type just
        keeps whatever handler it had.

        Check with:
          ls "$(nix build --no-link --print-out-paths nixpkgs#vlc)/share/applications"
      '';
    };

    transcoding = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        ffmpeg and yt-dlp.

        ffmpeg is also a runtime dependency of several other things — yazi's
        video thumbnailer and ripgrep-all's subtitle adapter among them — so
        a host may already be pulling it in indirectly. Installing it here
        makes it available directly and costs nothing extra when it is
        already in the closure.
      '';
    };

    metadata = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        exiftool, for reading and writing embedded metadata.

        Reads more than photos despite the name: video, audio, and PDF
        metadata as well. Worth knowing it WRITES by default and renames the
        original to *_original rather than modifying in place, which
        surprises people expecting a read-only tool.
      '';
    };

    capture = lib.mkOption {
      type = lib.types.bool;
      default = isLinux;
      defaultText = lib.literalExpression "pkgs.stdenv.hostPlatform.isLinux";
      description = ''
        Screen and terminal recording: wf-recorder and asciinema.

        wf-recorder captures a Wayland output through wlr-screencopy, so it
        is Linux-only and additionally needs a compositor implementing that
        protocol — Hyprland does. It produces a file and nothing plays it;
        that is what videoPlayer is for.

        asciinema records the terminal as a .cast rather than as video, and
        is portable. It is bundled here rather than split into its own option
        because both answer "record what I am doing".
      '';
    };

    extraPackages = lib.mkOption {
      type = lib.types.listOf lib.types.package;
      default = [ ];
      example = lib.literalExpression "[ pkgs.local.ipod-shuffle-4g pkgs.mpv ]";
      description = ''
        Additional media tools, supplied by the calling configuration.

        This is the seam for overlay-provided packages such as
        pkgs.local.ipod-shuffle-4g, so this module stays importable without
        those overlays applied.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = !(cfg.capture && !isLinux);
        message = ''
          nixSpace.programs.mediaPlayers.capture is enabled on a non-Linux host.
          wf-recorder captures through wlr-screencopy, which has no darwin
          equivalent. Set capture = false; asciinema is portable but is not
          worth the option on its own.
        '';
      }
    ];

    home.packages =
      lib.optional (cfg.videoPlayer != null) cfg.videoPlayer
      ++ lib.optionals cfg.transcoding [
        pkgs.ffmpeg
        pkgs.yt-dlp
      ]
      ++ lib.optional cfg.metadata pkgs.exiftool
      ++ lib.optional (cfg.capture && isLinux) pkgs.wf-recorder
      ++ lib.optional cfg.capture pkgs.asciinema
      ++ cfg.extraPackages;

    # Contributed from here rather than assembled in the xdg module: the
    # module that owns the player owns the association, so the two cannot
    # name different programs.
    #
    # Types are listed individually. mimeapps.list takes exact MIME types
    # only — the video/* wildcard that works in yazi's openRules is not valid
    # here, and a wildcard entry is ignored rather than rejected.
    nixSpace.xdg.mimeApps.defaults = lib.mkIf (cfg.videoPlayer != null) {
      "video/mp4" = [ cfg.videoPlayerDesktopFile ];
      "video/mpeg" = [ cfg.videoPlayerDesktopFile ];
      "video/quicktime" = [ cfg.videoPlayerDesktopFile ];
      "video/webm" = [ cfg.videoPlayerDesktopFile ];
      "video/x-matroska" = [ cfg.videoPlayerDesktopFile ];
      "video/x-msvideo" = [ cfg.videoPlayerDesktopFile ];
    };
  };
}
