# Firefox HM configuration module.
{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.nixSpace.programs.firefox;

  # Flag to allow the hyprland window settings for PiP.
  hyprlandEnabled = config.nixSpace.hyprland.enable or false;
in
{
  options.nixSpace.programs.firefox = {
    enable = lib.mkEnableOption "the Firefox browser configuration";

    package = lib.mkOption {
      type = lib.types.nullOr lib.types.package;
      default = pkgs.firefox;
      defaultText = lib.literalExpression "pkgs.firefox";
      description = ''
        Firefox package to install. Set to `null` to have home-manager manage
        the profile without installing a browser. This is required on darwin, 
        where nixpkgs' `firefox` is Linux-only and the app comes from a cask.
      '';
    };

    profileName = lib.mkOption {
      type = lib.types.str;
      default = config.home.username;
      defaultText = lib.literalExpression "config.home.username";
      description = ''
        Name of the managed Firefox profile. Renaming this orphans the old
        profile directory rather than migrating it.
      '';
    };

    extensions = lib.mkOption {
      type = lib.types.listOf lib.types.package;
      default = [ ];
      example = lib.literalExpression ''
        with inputs.firefox-addons.packages.''${pkgs.stdenv.hostPlatform.system}; [
        ublock-origin
        multi-account-containers
        ]
      '';
      description = ''
        Extension packages, supplied by the calling configuration where the
        flake `inputs` are in lexical scope. This module does not reference
        `inputs`, so it carries no dependency on the caller's input names.
      '';
    };

    pkcs11Modules = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = { };
      example = lib.literalExpression ''
        { OpenSC = "''${pkgs.opensc}/lib/opensc-pkcs11.so"; }
      '';
      description = ''
        PKCS#11 security devices to register, as name -> library path. Written
        through the enterprise `SecurityDevices` policy, which is the only
        declarative route: the alternative is clicking through
        Settings -> Security Devices -> Load, which is not reproducible.

        Needed for YubiKey PIV client certificates. Note this is unrelated to
        WebAuthn/passkeys, which go over CTAP2 and need no PKCS#11 module.
      '';
    };

    defaultBrowser = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Register Firefox as the handler for http/https and HTML documents.
        Linux only: this writes `mimeapps.list`, which macOS does have.
      '';
    };

    hyprland.pictureInPicture = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Contribute a Hyprland window rule floating and pinning Firefox's
        Picture-in-Picture popout. Has no effect unless the Hyprland bundle is
        also enabled.
      '';
    };

    settings = lib.mkOption {
      type = lib.types.attrsOf lib.types.anything;
      default = { };
      description = ''
        Additional Firefox preferences, merged over the module's defaults so a
        host can override any single pref without restating the rest.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    programs.firefox = {
      enable = true;
      inherit (cfg) package;

      configPath = "${config.xdg.configHome}/mozilla/firefox";

      policies = lib.mkIf (cfg.pkcs11Modules != { }) {
        SecurityDevices = cfg.pkcs11Modules;
      };

      profiles.${cfg.profileName} = {
        extensions.packages = cfg.extensions;

        settings = {
          "browser.disableResetPrompt" = true;
          "browser.download.panel.shown" = true;
          "browser.download.useDownloadDir" = false;
          "browser.newtabpage.activity-stream.showSponsoredTopSites" = false;
          "browser.shell.checkDefaultBrowser" = false;
          "browser.shell.defaultBrowserCheckCount" = 1;
          "browser.startup.homepage" = "https://start.duckduckgo.com";
          "browser.uiCustomization.state" =
            ''{"placements":{"widget-overflow-fixed-list":[],"nav-bar":["back-button","forward-button","stop-reload-button","home-button","urlbar-container","downloads-button","library-button","ublock0_raymondhill_net-browser-action","_testpilot-containers-browser-action"],"toolbar-menubar":["menubar-items"],"TabsToolbar":["tabbrowser-tabs","new-tab-button","alltabs-button"],"PersonalToolbar":["import-button","personal-bookmarks"]},"seen":["save-to-pocket-button","developer-button","ublock0_raymondhill_net-browser-action","_testpilot-containers-browser-action"],"dirtyAreaCache":["nav-bar","PersonalToolbar","toolbar-menubar","TabsToolbar","widget-overflow-fixed-list"],"currentVersion":18,"newElementCount":4}'';
          "dom.security.https_only_mode" = true;
          "identity.fxaccounts.enabled" = false;
          "privacy.trackingprotection.enabled" = true;
          "signon.rememberSignons" = false;
          # ctap2 is required for modern passkeys. Setting it false disables
          # them outright, and requests will fail immediately with a message
          # suggesting the user cancelled.
          #
          # Declared as true rather than omitted: home-manager writes user.js,
          # and Firefox copies those into prefs.js at first read. Removing a
          # line from user.js stops re-asserting the value but leaves whatever
          # is already in prefs.js, so an omitted pref is NOT an unset pref.
          "security.webauthn.ctap2" = true;
        }
        // cfg.settings;
      };
    };

    xdg.mimeApps.defaultApplications =
      lib.mkIf (cfg.defaultBrowser && pkgs.stdenv.hostPlatform.isLinux)
        {
          "text/html" = [ "firefox.desktop" ];
          "text/xml" = [ "firefox.desktop" ];
          "x-scheme-handler/http" = [ "firefox.desktop" ];
          "x-scheme-handler/https" = [ "firefox.desktop" ];
        };

    # Hyprland window rule for PiP popouts.
    nixSpace.hyprland.windowRules = lib.mkIf (cfg.hyprland.pictureInPicture && hyprlandEnabled) [
      {
        name = "firefox-pip";
        match.title = "^(Picture-in-Picture)$";
        float = true;
        pin = true;
        size = "30% 30%";
        move = "65% 5%";
      }
    ];

  };
}
