# Injects every package from ./pkgs into nixpkgs.
#
#   nixpkgs.overlays = [ inputs.snowball.overlays.default ];
#
# `final` is the fixed point, so packages here can refer to each other.
final: prev: import ./pkgs { inherit final prev; }
