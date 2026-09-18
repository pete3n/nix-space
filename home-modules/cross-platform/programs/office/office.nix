# Document creation and document search.
#
# OnlyOffice does not follow symlinks when scanning font directories, and
# home-manager's font path is entirely symlinks into the Nix store, so it sees
# nothing and falls back to its bundled set.
#
# See: https://github.com/NixOS/nixpkgs/issues/373521
#
# The kludge is to copy real files into a directory OnlyOffice will read.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.nixSpace.programs.office;

  isLinux = pkgs.stdenv.hostPlatform.isLinux;

  hmFonts = "${config.home.profileDirectory}/share/fonts";
  ooFonts = "${config.xdg.dataHome}/fonts/onlyoffice";
in
{
  options.nixSpace.programs.office = {
    enable = lib.mkEnableOption "document editing and search tooling";

    onlyoffice = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = isLinux;
        defaultText = lib.literalExpression "pkgs.stdenv.hostPlatform.isLinux";
        description = ''
          OnlyOffice desktop editors.

          Defaults to the platform rather than to true: the package is
          Linux-only, so a plain `true` would break evaluation of the darwin
          configuration the moment this module is imported there.
        '';
      };
      desktopFile = lib.mkOption {
        type = lib.types.str;
        default = "onlyoffice-desktopeditors.desktop";
        description = ''
          The .desktop filename for OnlyOffice.

          One entry for the whole suite: OnlyOffice registers a single editor
          that dispatches on the file it is given, where LibreOffice registers
          one per application.
        '';
      };
      userName = lib.mkOption {
        type = lib.types.str;
        default = config.home.username;
        defaultText = lib.literalExpression "config.home.username";
        description = ''
          Author name recorded in documents and shown on comments.
          Defaults to the account name rather than being left unset.
        '';
      };
      uiTheme = lib.mkOption {
        type = lib.types.str;
        default = "theme-night";
        example = "theme-classic-light";
        description = ''
          Interface theme, by its internal ID.

          "theme-night" is Modern Dark. The IDs are not the names shown in the
          UI, and an unrecognised one is ignored silently.
        '';
      };
      fontFix = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = ''
          Copy real font files into a directory OnlyOffice can read.

          Without it OnlyOffice sees no system fonts at all. Home-manager's
          font directory is symlinks, which it does not follow. The copy runs
          on every activation and is incremental.
        '';
      };
    };

    libreoffice = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = ''
          Enables the libreoffice suite. Linux-only.
        '';
      };
      package = lib.mkOption {
        type = lib.types.package;
        default = pkgs.libreoffice-fresh;
        defaultText = lib.literalExpression "pkgs.libreoffice-fresh";
        example = lib.literalExpression "pkgs.libreoffice";
        description = ''
          Which LibreOffice branch to install. `fresh` tracks current
          features.
        '';
      };
      desktopFiles = lib.mkOption {
        type = lib.types.attrsOf lib.types.str;
        default = {
          writer = "writer.desktop";
          calc = "calc.desktop";
          impress = "impress.desktop";
          draw = "draw.desktop";
        };
        description = ''
          LibreOffice .desktop filenames, by application.

          Per application rather than per suite: LibreOffice ships base, calc,
          draw, impress, math, startcenter, writer, and xsltfilter as separate
          entries, so a text document and a spreadsheet want different files.

          Only the four that own a document type are listed. startcenter is a
          launcher rather than a handler, and math and base handle formats not
          associated here.
        '';
      };
    };

    docSearch = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = ''
          ripgrep-all (`rga`), which searches inside PDFs, office documents,
          ebooks, archives, and subtitles.

          This is a cross-platform package. Darwin. NOTE: rga is wrapped with 
          pandoc, poppler, and ffmpeg, making it a large closure.
        '';
      };
      extraPackages = lib.mkOption {
        type = lib.types.listOf lib.types.package;
        default = [ ];
        example = lib.literalExpression "[ pkgs.poppler_utils pkgs.pandoc ]";
        description = ''
          Additional document tooling, pdftotext, pandoc, and similar, for
          use directly rather than through rga's adapters.
        '';
      };
    };

    pdfViewer.enable = lib.mkOption {
      type = lib.types.bool;
      default = pkgs.stdenv.hostPlatform.isLinux;
      defaultText = lib.literalExpression "pkgs.stdenv.hostPlatform.isLinux";
      description = ''
        Install a PDF viewer.

        Linux only by default: macOS has Preview, which is both the system
        default and what other applications hand PDFs to. zathura also
        fails to build on aarch64-darwin — appstream, one of its
        dependencies, mislinks there.
      '';
      package = lib.mkOption {
        type = lib.types.package;
        default = pkgs.zathura;
        defaultText = lib.literalExpression "pkgs.zathura";
        example = lib.literalExpression "pkgs.zathura";
        description = ''
          Which PDF viewer package to install.
        '';
      };
      desktopFile = lib.mkOption {
        type = lib.types.str;
        default = "org.pwmt.zathura.desktop";
        description = ''
          The .desktop filename for pdfViewer.

          Not derivable from the package: zathura's is reverse-DNS
          (org.pwmt.zathura.desktop) where VLC's is a bare vlc.desktop, so
          the convention differs per project and has to be stated.

          Naming a file that is not installed leaves the association inert,
          the type keeps whatever handler it already had, with no error.

          zathura also ships per-format entries (-cb, -djvu, -ps) for the
          plugins bundled with it. Only PDF is associated here; the others
          would each need their own type and file.

          Check with:
            ls "$(nix build --no-link --print-out-paths nixpkgs#zathura^out)/share/applications"
        '';
      };
    };

    mdPreview = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = isLinux;
        description = ''
          Provide markdown preview with the litemdview package.
          Linux only.
        '';
      };
    };

    associateDocuments = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Claim the office document MIME types for whichever suite is enabled.

        Off leaves .docx and .odt to whatever the desktop database happens to
        pick, which is usually the last thing installed that declared support.

        See documentHandler below for how the two suites are split when both
        are enabled.
      '';
    };

    documentHandler = lib.mkOption {
      type = lib.types.enum [
        "split"
        "onlyoffice"
        "libreoffice"
      ];
      default = "split";
      description = ''
        Which suite handles which document formats, when both are enabled.

        "split" sends OOXML (.docx, .xlsx, .pptx) to OnlyOffice and ODF
        (.odt, .ods, .odp) to LibreOffice. OnlyOffice tracks Microsoft's
        formats more closely; LibreOffice is stronger on open and legacy
        formats, and is the only suite yazi's office preview supports.

        "onlyoffice" and "libreoffice" send everything to one of them.

        Whatever this is set to, a format only goes to a suite that is actually
        enabled: with one suite installed it takes everything, and this
        option has no effect.
      '';
    };

  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = !(cfg.onlyoffice.enable && !isLinux);
        message = ''
          nixSpace.programs.office.onlyoffice is enabled on a non-Linux host.
          onlyoffice-desktopeditors is Linux-only; there is no darwin build to
          fall back to.
        '';
      }
      {
        assertion = !(cfg.libreoffice.enable && !isLinux);
        message = ''
          nixSpace.programs.office.libreoffice is enabled on a non-Linux host.
          nixpkgs' libreoffice is Linux-only. On darwin, install it as a cask.
        '';
      }
    ];

    programs.onlyoffice = lib.mkIf cfg.onlyoffice.enable {
      enable = true;
      settings = {
        UITheme = cfg.onlyoffice.uiTheme;
        UserName = cfg.onlyoffice.userName;
      };
    };

    home.packages =
      lib.optional cfg.libreoffice.enable cfg.libreoffice.package
      ++ lib.optional cfg.docSearch.enable pkgs.ripgrep-all
      ++ cfg.docSearch.extraPackages
      ++ lib.optional cfg.mdPreview.enable pkgs.litemdview
      ++ lib.optional cfg.pdfViewer.enable cfg.pdfViewer.package;

    nixSpace.xdg.mimeApps.defaults =
      let
        oo = cfg.onlyoffice.enable;
        lo = cfg.libreoffice.enable;
        loFiles = cfg.libreoffice.desktopFiles;
        ooFile = [ cfg.onlyoffice.desktopFile ];

        # Preferred handler for a format family, falling back to the other
        # suite when the preferred one is not installed, and to nothing when
        # neither is. `null` entries are filtered out below.
        pick =
          {
            preferLibre,
            libreFile,
          }:
          let
            wantLibre = cfg.documentHandler == "libreoffice" || (cfg.documentHandler == "split" && preferLibre);
          in
          if wantLibre && lo then
            [ libreFile ]
          else if oo then
            ooFile
          else if lo then
            [ libreFile ]
          else
            null;

        textDoc = pick {
          preferLibre = false;
          libreFile = loFiles.writer;
        };
        textOdf = pick {
          preferLibre = true;
          libreFile = loFiles.writer;
        };
        sheetDoc = pick {
          preferLibre = false;
          libreFile = loFiles.calc;
        };
        sheetOdf = pick {
          preferLibre = true;
          libreFile = loFiles.calc;
        };
        slideDoc = pick {
          preferLibre = false;
          libreFile = loFiles.impress;
        };
        slideOdf = pick {
          preferLibre = true;
          libreFile = loFiles.impress;
        };
        drawOdf = pick {
          preferLibre = true;
          libreFile = loFiles.draw;
        };
      in
      lib.mkIf (cfg.associateDocuments && (oo || lo)) (
        lib.filterAttrs (_: v: v != null) {
          # OOXML
          "application/vnd.openxmlformats-officedocument.wordprocessingml.document" = textDoc;
          "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet" = sheetDoc;
          "application/vnd.openxmlformats-officedocument.presentationml.presentation" = slideDoc;

          # ODF
          "application/vnd.oasis.opendocument.text" = textOdf;
          "application/vnd.oasis.opendocument.spreadsheet" = sheetOdf;
          "application/vnd.oasis.opendocument.presentation" = slideOdf;
          "application/vnd.oasis.opendocument.graphics" = drawOdf;
          # Legacy binary Microsoft formats.
          "application/msword" = textOdf;
          "application/vnd.ms-excel" = sheetOdf;
          "application/vnd.ms-powerpoint" = slideOdf;

          # PDF, from the pdfViewer option rather than either suite, both
          # can open a PDF but neither should be the default for reading one.
        }
        // lib.optionalAttrs (cfg.pdfViewer.enable && cfg.pdfViewer.package != null) {
          "application/pdf" = [ cfg.pdfViewer.desktopFile ];
        }
      );

    home.activation.onlyofficeUserFonts = lib.mkIf (cfg.onlyoffice.enable && cfg.onlyoffice.fontFix) (
      lib.hm.dag.entryAfter [ "writeBoundary" ] # sh
        ''
          set -eu

          if [ -d "${hmFonts}" ]; then
            $DRY_RUN_CMD ${pkgs.coreutils}/bin/mkdir -p "${ooFonts}"

            # --delete and an incremental sync, NOT rm -rf and a full copy.
            # This runs on every activation, and re-copying an entire font
            # collection each time is work proportional to the library
            # rather than to what changed.
            #
            # -L dereferences: copying the symlinks themselves is exactly
            # what OnlyOffice cannot read.
            $DRY_RUN_CMD ${pkgs.rsync}/bin/rsync -aL --delete \
              --include='*/' \
              --include='*.ttf' --include='*.otf' \
              --exclude='*' \
              --chmod=D755,F644 \
              "${hmFonts}/" "${ooFonts}/"

            # --chmod above rather than a chmod pass afterwards. Store
            # files are 444 and directories 555, and rsync -a preserves
            # that — which would leave a tree rsync itself cannot update on
            # the next run, since removing an entry needs write on its
            # parent directory.
            $DRY_RUN_CMD ${pkgs.fontconfig}/bin/fc-cache -f "${ooFonts}" >/dev/null 2>&1 || true
          fi
        ''
    );
  };
}
