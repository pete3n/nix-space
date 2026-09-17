# Validate a user@host attribute file:
# - Errors accumulate and throw once.
# - Unknown fields are an error.
# - Required fields resolve to `null` in targetAttrs rather than throwing on access,
#   so that computing the error list cannot blow itself up. Downstream checks
#   that touch them are guarded on `missing == [ ]`.
# - Tag misuse is an error.
{ lib, self }:
let
  requiredAttrs = [
    "system"
    "user"
    "host"
  ];

  # Optional keys and their default values. Embedded fields are null on standard
  # hosts; `embeddedTarget` selects the platform and board-specific fields sit
  # alongside it.
  optionalAttrs = {
    tags = [ ];
    specialisations = [ ];
    isHomeAlone = false;
    useHomebrew = false;
    useCache = false;
    sshPubKeys = [ ];
    chassis = null;
    buildSystem = null;
    deployMode = "local";
  };

  knownAttrs = requiredAttrs ++ builtins.attrNames optionalAttrs;

  showVal = val: if val == null then "<unset>" else toString val;

  load =
    { attrs, src }:
    let
      targetAttrs =
        builtins.mapAttrs (key: (default: attrs.${key} or default)) optionalAttrs
        // lib.genAttrs requiredAttrs (key: attrs.${key} or null);

      # Build system defaults to the target system.
      # buildSystem != system is a cross build.
      resolvedAttrs = targetAttrs // {
        # Implied tags added here, before any check reads them. A host tags
        # what it has; expansion adds what that implies; requirements name
        # what they need.
        tags = self.tags.expandTags targetAttrs.tags;

        buildSystem =
          if targetAttrs.buildSystem != null then targetAttrs.buildSystem else targetAttrs.system;
        deployMode =
          if attrs ? deployMode then
            targetAttrs.deployMode
          else if isPi then
            "sd-image"
          else
            "local";
      };

      missingAttrs = builtins.filter (key: !(attrs ? ${key})) requiredAttrs;
      unknownAttrs = builtins.filter (key: !builtins.elem key knownAttrs) (builtins.attrNames attrs);
      badTags = self.tags.invalidTags resolvedAttrs.tags;

      hasChassis = resolvedAttrs.chassis != null;
      validChassis = hasChassis && builtins.elem resolvedAttrs.chassis self.hardware.valid;

      isEmbedded = validChassis && self.hardware.isEmbedded resolvedAttrs.chassis;
      isPi = validChassis && self.hardware.family resolvedAttrs.chassis == "raspberry-pi";

      errors =
        lib.optional (
          missingAttrs != [ ]
        ) "missing required field(s): ${lib.concatStringsSep ", " missingAttrs}"

        ++
          lib.optional (unknownAttrs != [ ])
            "unknown field(s): ${lib.concatStringsSep ", " unknownAttrs} (typo, or a field no longer read by validate-attrs.nix)"

        ++ lib.optional (
          badTags != [ ]
        ) "invalid tag(s): ${lib.concatStringsSep ", " badTags} (add to tag-registry.nix to use)"

        # chassis errors
        ++
          lib.optional (hasChassis && !validChassis)
            "unknown chassis '${showVal resolvedAttrs.chassis}'. Must be one of: ${lib.concatStringsSep ", " self.hardware.valid}"

        ++
          lib.optional (!resolvedAttrs.isHomeAlone && !hasChassis)
            "chassis is required on managed hosts. Set isHomeAlone = true if the operating system is not managed by nix (Debian, Fedora, an unmanaged Mac)."

        ++
          lib.optional (resolvedAttrs.isHomeAlone && hasChassis)
            "chassis '${showVal resolvedAttrs.chassis}' is set but isHomeAlone = true. Hardware modules are NixOS/nix-darwin only and cannot be applied to an unmanaged OS."

        # home-alone errors
        ++ lib.optional (
          resolvedAttrs.isHomeAlone && resolvedAttrs.specialisations != [ ]
        ) "specialisations are a NixOS feature and cannot be applied when isHomeAlone = true"

        ++
          lib.optional
            (resolvedAttrs.isHomeAlone && builtins.elem resolvedAttrs.deployMode self.deploy.systemModes)
            "deployMode '${showVal resolvedAttrs.deployMode}' produces a whole system image and cannot be used when isHomeAlone = true"

        # platform errors
        ++
          lib.optional (isEmbedded && missingAttrs == [ ] && !self.platform.isLinux resolvedAttrs.system)
            "embedded chassis '${showVal resolvedAttrs.chassis}' requires a Linux system target (got '${showVal resolvedAttrs.system}')"

        # deployMode errors
        ++
          lib.optional (!builtins.elem resolvedAttrs.deployMode self.deploy.validModes)
            "invalid deployMode '${showVal resolvedAttrs.deployMode}'. Must be one of: ${lib.concatStringsSep ", " self.deploy.validModes}"

        ++ lib.optional (
          !isEmbedded && builtins.elem resolvedAttrs.deployMode self.deploy.embeddedOnlyModes
        ) "deployMode '${showVal resolvedAttrs.deployMode}' requires an embedded chassis"

        ++ lib.optionals isPi (
          self.pi.deployErrors {
            inherit (resolvedAttrs) chassis deployMode;
          }
        )

        # Tag misuse errors
        ++ lib.optionals (missingAttrs == [ ]) (
          self.tags.misuse {
            inherit (resolvedAttrs) tags system isHomeAlone;
            inherit isPi;
          }
        );
    in
    lib.throwIf (
      errors != [ ]
    ) "fromAttrs: ${src}:\n  - ${lib.concatStringsSep "\n  - " errors}" resolvedAttrs;
in
{
  # Build a context from an in-memory attrset.
  fromAttrs =
    attrs:
    load {
      inherit attrs;
      src = "<inline>";
    };

  # Build a context from a file containing an attribute set.
  fromFile =
    path:
    let
      loadedAttrs = import path;
    in
    lib.throwIf (!lib.isAttrs loadedAttrs)
      "attrs.fromFile: ${toString path} must evaluate to a bare attrset, not a ${builtins.typeOf loadedAttrs}."
      (load {
        attrs = loadedAttrs;
        src = toString path;
      });
}
