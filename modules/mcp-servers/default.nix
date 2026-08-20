# The list of server modules, discovered from this directory so that adding a
# server means dropping one file in here.
#
# These are mcp-servers-nix modules, not standalone ones: they expect the
# `mkServerModule` specialArg that upstream's `lib.evalModule` provides. Use
# them through `sneg.lib.mkConfig`, or pass them to upstream's `mkConfig`
# yourself alongside `sneg.overlays.mcp-servers`.
let
  isServerModule = name: name != "default.nix" && builtins.match ".*\\.nix" name != null;
in
map (name: ./. + "/${name}") (
  builtins.filter isServerModule (builtins.attrNames (builtins.readDir ./.))
)
