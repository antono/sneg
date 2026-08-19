# The package list. Both `overlays.default` and `packages.<system>` are
# derived from this, so adding a package means one directory under ./pkgs
# and one line here.
#
# `final` is the overlay fixed point — use it for callPackage and for
# referring to other packages. `prev` is the package set as it was before
# this overlay; anything that decides *which attributes exist* must read
# from `prev`, or nixpkgs' stdenv bootstrap recurses infinitely.
{ final, prev }:
let
  inherit (prev) lib;
in
{
  deplexity = final.callPackage ./deplexity/package.nix { };
}
// lib.optionalAttrs prev.stdenv.hostPlatform.isLinux {
  # chromium is linux-only in nixpkgs, so this variant is too.
  deplexity-with-chromium = final.callPackage ./deplexity/package.nix {
    browser = final.chromium;
  };
}
