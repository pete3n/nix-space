# CUPS printing module.
#
# Opt-in. A print server is a running daemon and a set of drivers, which a
# server or a desk with no printer should not carry.
#
# Printers are per-site facts (which USB serial, which room), so none are
# listed here. A host names its own in `printers`.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.nixSpace.printing;
in
{
  options.nixSpace.printing = {
    enable = lib.mkEnableOption "CUPS printing";

    drivers = lib.mkOption {
      type = lib.types.listOf lib.types.package;
      default = [ pkgs.gutenprint ];
      defaultText = lib.literalExpression "[ pkgs.gutenprint ]";
      example = lib.literalExpression "[ pkgs.gutenprint pkgs.splix ]";
      description = ''
        CUPS driver packages. gutenprint covers most inkjet and laser models;
        add vendor drivers (splix for Samsung, etc.) as a printer needs them.
      '';
    };

    printers = lib.mkOption {
      # Same shape as hardware.printers.ensurePrinters, so an entry copies
      # across without translation.
      type = lib.types.listOf lib.types.attrs;
      default = [ ];
      example = lib.literalExpression ''
        [
          {
            name = "Brother_HL-L3280CDW";
            deviceUri = "usb://Brother/HL-L3280CDW%20series?serial=XXXXXXXX";
            model = "gutenprint.5.3://brother-hl-3400cn";
            description = "Brother HL-L3280CDW USB";
            location = "Office";
            ppdOptions = {
              PageSize = "Letter";
              Duplex = "DuplexNoTumble";
            };
          }
        ]
      '';
      description = ''
        Printers to declare in CUPS, in the form taken by
        `hardware.printers.ensurePrinters`. Empty by default: printers
        belong to a site, not to the module.
      '';
    };

    defaultPrinter = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "Name of the printer CUPS uses when none is chosen.";
    };
  };

  config = lib.mkIf cfg.enable {
    hardware.printers = {
      ensurePrinters = cfg.printers;
      ensureDefaultPrinter = cfg.defaultPrinter;
    };

    services.printing = {
      enable = true;
      inherit (cfg) drivers;
    };

    environment.systemPackages = with pkgs; [
      cups
      system-config-printer
    ];
  };
}
