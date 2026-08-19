# Injects every package from ./pkgs into nixpkgs.
#
#   nixpkgs.overlays = [ inputs.sneg.overlays.default ];
#
# `final` is the fixed point, so packages here can refer to each other.
# `inputs` carries this flake's own inputs (fenix, crane) through to the
# packages that need them.
inputs: final: prev:
import ./pkgs { inherit final prev inputs; }
