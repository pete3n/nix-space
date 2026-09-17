# Load user@host metadata files from a directory into { "user@host" = attrs; }.
#
# Returns validated attributes with defaults applied.
#
{ lib, self }:
{ dir }:
assert lib.assertMsg (builtins.pathExists dir) "getHomeAttrs: directory not found: ${toString dir}";
let
  entries = builtins.readDir dir;

  fileType =
    name:
    let
      val = entries.${name};
    in
    if builtins.isAttrs val then val.type else val;

  isNixFile =
    name:
    let
      type = fileType name;
    in
    (type == "regular" || type == "symlink") && lib.strings.hasSuffix ".nix" name;

  attrFiles = builtins.filter isNixFile (
    builtins.sort (filenameA: (filenameB: filenameA < filenameB)) (builtins.attrNames entries)
  );

  pairs = map (
    name:
    let
      attrs = self.attrs.fromFile (dir + "/${name}");
    in
    lib.nameValuePair "${attrs.user}@${attrs.host}" attrs
  ) attrFiles;

  keys = map (pair: pair.name) pairs;
  dupes = lib.unique (builtins.filter (key: lib.count (idx: idx == key) keys > 1) keys);
in
lib.throwIf (dupes != [ ])
  "getHomeAttrs: duplicate user@host keys in ${toString dir}: ${lib.concatStringsSep ", " dupes}"
  (builtins.listToAttrs pairs)
