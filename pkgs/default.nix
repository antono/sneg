# The package list. Both `overlays.default` and `packages.<system>` are
# derived from this, so adding a package means one directory under ./pkgs
# and one line here.
#
# `final` is the overlay fixed point — use it for callPackage and for
# referring to other packages. `prev` is the package set as it was before
# this overlay; anything that decides *which attributes exist* must read
# from `prev`, or nixpkgs' stdenv bootstrap recurses infinitely.
{
  final,
  prev,
  inputs,
}:
let
  inherit (prev) lib;

  # tolaria ships several outputs from one source tree, so its directory
  # returns a set rather than a single derivation.
  tolaria = final.callPackage ./tolaria { inherit (inputs) fenix crane; };
in
{
  deplexity = final.callPackage ./deplexity/package.nix { };

  tolaria-mcp = tolaria.mcp;
  tolaria-node-modules = tolaria.nodeModules;
}
// lib.optionalAttrs prev.stdenv.hostPlatform.isLinux {
  # chromium is linux-only in nixpkgs, so this variant is too.
  deplexity-with-chromium = final.callPackage ./deplexity/package.nix {
    browser = final.chromium;
  };

  # The desktop app needs the WebKitGTK 4.1 stack.
  tolaria = tolaria.bundle;
}
