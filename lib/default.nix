# Composition with mcp-servers-nix.
#
# Upstream's `lib.evalModule` takes the nixpkgs instance to resolve server
# packages from, and one module. Both are seams: extending nixpkgs with
# `overlays.mcp-servers` makes sneg's servers resolvable by name, and the module
# can `imports` sneg's server modules. So the servers here compose with
# upstream's without forking it.
{
  mcp-servers-nix,
  overlay,
}:
let
  serverModules = import ../modules/mcp-servers;

  evalModule =
    pkgs: config:
    mcp-servers-nix.lib.evalModule (pkgs.extend overlay) {
      imports = serverModules ++ [ config ];
    };
in
{
  inherit serverModules evalModule;

  # Drop-in for `mcp-servers-nix.lib.mkConfig`: same signature, but every
  # `programs.<name>` from sneg is available on top of upstream's.
  mkConfig = pkgs: config: (evalModule pkgs config).config.configFile;
}
