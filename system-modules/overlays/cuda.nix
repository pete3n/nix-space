# CUDA-enabled package overrides.
#
# Applied when the `cuda` tag is set. This is the middle position between two
# bad options:
#
#   nixpkgs.config.cudaSupport = true
#     Every package with an optional CUDA path leaves the binary cache,
#     because upstream Hydra builds the cudaSupport = false variants. Hours of
#     rebuilds for packages nobody asked to accelerate.
#
#   Per-module .override
#     Affects one reference. If home-manager also installs the package, you
#     get both variants in the closure and PATH order decides which runs —
#     silently, and differently per session.
#
# An overlay applies to EVERY reference — system and home — from one
# definition, and only to packages named here.
#
# WHY THIS IS AN OVERLAY AND NOT A MODULE: overlays are consumed when `pkgs`
# is constructed, before the module system exists. A module cannot set
# nixpkgs.overlays once the flake supplies nixpkgs.pkgs, and could not read
# config anyway at that point. Anything affecting HOW a package is built
# belongs here; anything affecting what is installed or configured belongs in
# a module.
#
# NOT NEEDED HERE: packages with a separate CUDA attribute rather than an
# override — ollama-cuda, for instance. Those are built and cached upstream.
# Reference them directly in the consuming module.
#
# ADDING A PACKAGE
#
# The override argument name differs per package: cudaSupport, enableCuda,
# withCuda. A wrong name throws ("function has no argument named ..."), so
# typos fail loudly rather than silently doing nothing. Check the package's
# expression rather than guessing.
#
# MEASURE BEFORE COMMITTING. An entry's cost is not visible from its length:
# .override rebuilds the named package but NOT its dependencies, so if a
# package needs a CUDA-enabled dependency you must add that too — and then
# everything else depending on it rebuilds as well. Check with:
#
#   nix build --dry-run .#nixosConfigurations.<host>.config.system.build.toplevel
#
# before and after adding an entry, and compare the "will be built" list.
final: prev: {
  # 3D rendering — Cycles GPU rendering is the point of the override.
  blender = prev.blender.override { cudaSupport = true; };

  # TODO: verify the argument name against the current ffmpeg expression
  # before enabling. NVENC/NVDEC and CUDA filters are separate flags in some
  # versions.
  # ffmpeg = prev.ffmpeg.override { withCuda = true; };

  # TODO: opencv4 uses `enableCuda`. Note this one is expensive and
  # transitive — anything linking OpenCV rebuilds with it.
  # opencv4 = prev.opencv4.override { enableCuda = true; };
}
