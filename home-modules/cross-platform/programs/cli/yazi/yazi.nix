# yazi terminal file manager module.
#
# yazi shells out to a different tool for each file type, and a missing one
# dependency produces an empty preview pane rather than an error.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.nixSpace.programs.yazi;

  # The office plugin's rules, are used for both preloaders and previewers.
  # A yazi plugin is a directory containing main.lua, so this is the whole
  # packaging.
  officePlugin = pkgs.runCommand "office.yazi" { } ''
    mkdir -p $out
    cp ${./office-main.lua} $out/main.lua
  '';

  # Matched on extension, NOT MIME type. yazi resolves these files correctly
  # — `file -bL --mime-type` on a .odp returns
  # application/vnd.oasis.opendocument.presentation, but a `mime` rule
  # naming that exact type never reaches the plugin, while the equivalent
  # `url` rule does.
  officeRules = [

    {
      url = "*.odp";
      run = "office";
    }
    {
      url = "*.odt";
      run = "office";
    }
    {
      url = "*.ods";
      run = "office";
    }
    {
      url = "*.doc";
      run = "office";
    }
    {
      url = "*.docx";
      run = "office";
    }
    {
      url = "*.ppt";
      run = "office";
    }
    {
      url = "*.pptx";
      run = "office";
    }
    {
      url = "*.xls";
      run = "office";
    }
    {
      url = "*.xlsx";
      run = "office";
    }
  ];

  officeCfg = config.nixSpace.programs.office or { };
  pdfViewer = if (officeCfg.pdfViewer.enable or false) then officeCfg.pdfViewer.package else null;
  videoPlayer = config.nixSpace.programs.media.videoPlayer or null;

  # Store paths, not bare names: yazi launched from a compositor keybind
  # inherits the session environment, not a shell's PATH.
  documentOpeners =
    lib.optionalAttrs (pdfViewer != null) {
      pdf = [
        {
          run = ''${lib.getExe pdfViewer} "$@"'';
          orphan = true;
          desc = "PDF viewer";
        }
      ];
    }
    // lib.optionalAttrs (videoPlayer != null) {
      video = [
        {
          run = ''${lib.getExe videoPlayer} "$@"'';
          orphan = true;
          desc = "Video player";
        }
      ];
    };

  documentRules =
    lib.optional (pdfViewer != null) {
      mime = "application/pdf";
      use = "pdf";
    }
    ++ lib.optional (videoPlayer != null) {
      mime = "video/*";
      use = "video";
    };

  # piper is the official plugin that turns any shell command into a
  # previewer. Both HTML and markdown route through it, so it is installed
  # if either is on rather than by each independently — two definitions of
  # the same plugins.piper key would be a duplicate, not a merge.
  usesPiper = cfg.previewers.html || cfg.previewers.markdown;

  # glow's command appears in two rules (MIME and extension), so it is bound
  # once here. See the comment on the extension rule below for why both.
  glowCommand = ''piper -- ${lib.getExe pkgs.glow} -s dark -w "$w" "$1"'';

  piperPreviewers =
    lib.optionals cfg.previewers.html [
      {
        mime = "text/html";
        run = ''piper -- ${lib.getExe pkgs.w3m} -dump -T text/html -cols "$w" "$1"'';
      }
    ]
    ++ lib.optionals cfg.previewers.markdown [
      {
        mime = "text/markdown";
        run = glowCommand;
      }
      # `file` reports markdown as text/plain — there is no magic-bytes
      # signature to distinguish it — so the MIME rule alone misses most .md
      # files. Matching on the name catches them regardless of what the sniff
      # returned. `url`, not `name`: yazi renamed that field, and the old
      # spelling fails to parse with "at least one of `url` or `mime` must be
      # specified".
      {
        url = "*.md";
        run = glowCommand;
      }
    ];
in
{
  options.nixSpace.programs.yazi = {
    enable = lib.mkEnableOption "yazi file manager";

    shellWrapperName = lib.mkOption {
      type = lib.types.str;
      default = "y";
      description = ''
        Name of the shell function that changes the parent shell's directory
        on exit.

        yazi cannot change its parent's directory itself, so home-manager
        defines a wrapper function that reads yazi's last path and cds to it.
        Running `yazi` directly still works, but it just leaves you where you
        started.
      '';
    };

    previewers = {
      builtin = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = ''
          Install the tools yazi's own previewers shell out to: pdftoppm,
          ffmpegthumbnailer, magick, and chafa.

          These must be on PATH — yazi's built-in Lua calls them by name and
          has no store path to use. A missing one gives an EMPTY preview pane
          rather than an error, so turning this off makes yazi look broken
          rather than minimal.

          Contrast the piper-based previewers below, which embed a store path
          in the rule and need nothing installed.
        '';
      };

      html = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = ''
          Render HTML through w3m rather than showing source.

          yazi has no previewer for text/html, so it falls through to the
          code previewer. Text-layout rendering only — headings, lists, and
          tables reflowed to the pane width. A real visual render would mean
          a headless browser per file, far too slow for a preview that fires
          on every cursor move.

          Self-contained: w3m is named by store path in the rule, so nothing
          needs to be on PATH.
        '';
      };

      markdown = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = ''
          Render markdown through glow rather than showing source.

          Via piper rather than the glow.yazi plugin: that plugin targets an
          older previewer API and fails on yazi 26.5 with "attempt to call a
          nil value in function glow.peek".

          Directly relevant with nb, whose notebooks are markdown.
        '';
      };

      office = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = ''
          Preview office documents, converting through LibreOffice.

          Needs LibreOffice from somewhere — either officeConverter here or
          nixSpace.programs.office.libreoffice.
        '';
      };

      imageOverlay = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = ''
          Install ueberzugpp for image previews.

          Only for terminals with no graphics protocol of their own, such as
          alacritty. yazi uses kitty or sixel directly where available and
          falls back to chafa's block characters otherwise. ueberzugpp draws
          a separate overlay window, which works but does not follow the
          terminal when it moves.
        '';
      };
    };

    openers = lib.mkOption {
      type = lib.types.attrsOf (lib.types.listOf (lib.types.attrsOf lib.types.anything));
      default = { };
      example = lib.literalExpression ''
        {
          pdf = [
            {
              run = "okular \"$@\"";
              orphan = true;
              desc = "Okular";
            }
          ];
        }
      '';

      description = ''
        Programs yazi opens files with, keyed by opener name.

        This is empty by default because an opener names a command, and nothing here
        installs it.
      '';
    };

    openRules = lib.mkOption {
      type = lib.types.listOf (lib.types.attrsOf lib.types.str);
      default = [ ];
      example = lib.literalExpression ''
        [
          { mime = "application/pdf"; use = "pdf"; }
          { mime = "video/*"; use = "vlc"; }
        ]
      '';
      description = ''
        Which opener handles which file type. Prepended to yazi's own rules,
        so these win.
      '';
    };

    plugins = {
      office = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = ''
          Preview office documents as a rendered page.

          Renders an actual page rather than extracting text: LibreOffice
          converts one page to PDF and pdftoppm rasterises it, so this needs
          plugins.officeConverter as well.
        '';
      };

      officeConverter = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = ''
          Install LibreOffice for the office plugin to render pages through.
          Linux-only. pkgs.libreoffice has no darwin build.

          Off by default, it is a large closure for a preview and may already
          be installed.

          Turn this on only where yazi is the sole reason LibreOffice is
          wanted. Where nixSpace.programs.office.libreoffice.enable is already
          true, leave this off; the plugin finds libreoffice on PATH either
          way.
        '';
      };

      officeConverterPackage = lib.mkOption {
        type = lib.types.package;
        default = config.nixSpace.programs.office.libreoffice.package or pkgs.libreoffice-stable;
        defaultText = lib.literalExpression "the office module's package, else pkgs.libreoffice-fresh";
        description = ''
          Which LibreOffice the plugin renders through, when officeConverter
          is on. Defaults to whatever the office module selected, so the two
          cannot diverge into separate closures.
        '';
      };

      archive = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Preview and extract archives with ouch.";
      };

      mount = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = ''
          Mount and unmount removable devices, bound to M.

          Off by default: mounting needs privileges the plugin does not
          provide. Without udisks2 or a polkit rule the device list appears
          and mounting fails, which reads as a broken plugin.
        '';
      };

      lazygit = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Open lazygit in the current directory, bound to g-i.";
      };
    };

    shellKeymaps = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Restore the shell keybindings: ! for a blocking shell, ; for a
        shell command prompt, : for a blocking one.

        yazi 26.5 dropped these from its default keymap. 
      '';
    };

    keymaps = lib.mkOption {
      type = lib.types.listOf (lib.types.attrsOf lib.types.anything);
      default = [ ];
      example = lib.literalExpression ''
        [
          {
            on = [ "g" "p" ];
            run = "cd ~/Projects";
            desc = "go ~/Projects";
          }
        ]
      '';
      description = ''
        Extra keymaps, prepended so they take precedence over yazi's own.

        The lazygit binding is added separately when that plugin is enabled.
        It belongs with the plugin rather than here.
      '';
    };

    flavor = lib.mkOption {
      type = lib.types.nullOr lib.types.package;
      default = pkgs.fetchFromGitHub {
        owner = "BennyOe";
        repo = "tokyo-night.yazi";
        rev = "5f5636427f9bb16cc3f7c5e5693c60914c73f036";
        hash = "sha256-4aNPlO5aXP8c7vks6bTlLCuyUQZ4Hx3GWtGlRmbhdto=";
      };
      defaultText = lib.literalMD "tokyo-night.yazi, pinned by revision.";
      description = ''
        Colour flavor, or null for yazi's default.

        Pinned by revision rather than tracking a branch: a flavor is a set of
        theme files yazi loads at startup, and an upstream change to their
        structure breaks startup rather than just looking different.
      '';
    };

    flavorName = lib.mkOption {
      type = lib.types.str;
      default = "tokyo-night";
      description = ''
        Name the flavor is registered under.

        Must match the directory name inside the flavor package, because yazi looks
        it up by name, and a mismatch means the flavor is installed and never
        applied.
      '';
    };

    assertions = [
      {
        assertion = !(cfg.plugins.officeConverter && !pkgs.stdenv.hostPlatform.isLinux);
        message = ''
          nixSpace.programs.yazi.plugins.officeConverter is enabled on a
          non-Linux host. pkgs.libreoffice is Linux-only. Disable this option 
          to use Yazi on Darwin.
        '';
      }
    ];

  };

  config = lib.mkIf cfg.enable {
    warnings =
      let
        libreofficeAvailable =
          cfg.plugins.officeConverter || (config.nixSpace.programs.office.libreoffice.enable or false);
      in
      lib.optional (cfg.plugins.office && !libreofficeAvailable) ''
        nixSpace.programs.yazi.plugins.office is enabled, but nothing on
        this host provides LibreOffice — neither plugins.officeConverter here
        nor nixSpace.programs.office.libreoffice.

        The plugin renders through LibreOffice, so previewing a document
        fails with "attempt to index a nil value": it does not check whether
        the command exists before using its output.

        Enable either one, or install LibreOffice some other way and ignore
        this.
      '';

    home.packages =
      lib.optionals cfg.previewers.builtin [
        pkgs.chafa # image fallback for terminals without a graphics protocol
        pkgs.ffmpegthumbnailer
        pkgs.imagemagick # image decoding for formats yazi cannot read natively
        pkgs.poppler-utils
      ]
      # The office plugin converts through LibreOffice to PDF and
      # rasterises with pdftoppm.
      ++ lib.optional cfg.plugins.officeConverter cfg.plugins.officeConverterPackage
      ++ lib.optional cfg.plugins.lazygit pkgs.lazygit
      ++ lib.optional cfg.previewers.imageOverlay pkgs.ueberzugpp;

    programs.yazi = {
      enable = true;
      inherit (cfg) shellWrapperName;

      # Shell integration comes from home-manager's own detection of which
      # shells are enabled, rather than an argument threaded in from the.
      enableBashIntegration = lib.mkDefault config.programs.bash.enable;
      enableZshIntegration = lib.mkDefault config.programs.zsh.enable;

      plugins =
        lib.optionalAttrs usesPiper { piper = pkgs.yaziPlugins.piper; }
        // lib.optionalAttrs cfg.previewers.office { office = officePlugin; }
        // lib.optionalAttrs cfg.plugins.lazygit { lazygit = pkgs.yaziPlugins.lazygit; }
        // lib.optionalAttrs cfg.plugins.archive { ouch = pkgs.yaziPlugins.ouch; }
        // lib.optionalAttrs cfg.plugins.mount { mount = pkgs.yaziPlugins.mount; };

      keymap.mgr.prepend_keymap =
        cfg.keymaps
        ++ lib.optionals cfg.shellKeymaps [
          {
            on = [ "!" ];
            run = ''shell "$SHELL" --block'';
            desc = "shell here";
          }
          {
            on = [ ";" ];
            run = "shell --interactive";
            desc = "run shell command";
          }
          {
            on = [ ":" ];
            run = "shell --block --interactive";
            desc = "run blocking shell command";
          }
        ]
        ++ lib.optionals cfg.plugins.mount [
          {
            on = "M";
            run = "plugin mount";
            desc = "Mount and unmount devices";
          }
        ]
        ++ lib.optional cfg.plugins.lazygit {
          on = [
            "g"
            "i"
          ];
          run = "plugin lazygit";
          desc = "run lazygit";
        };

      settings = {
        mgr.linemode = "size";

        opener = documentOpeners // cfg.openers;
        open.prepend_rules = cfg.openRules ++ documentRules;

        plugin = lib.mkIf cfg.plugins.office {
          prepend_previewers = piperPreviewers ++ lib.optionals cfg.previewers.office officeRules;
        };
      }
      // lib.optionalAttrs (cfg.flavor != null) {
        flavors.${cfg.flavorName} = cfg.flavor;

        theme.flavor = {
          use = cfg.flavorName;
          dark = cfg.flavorName;
        };
      };
    };
  };
}
