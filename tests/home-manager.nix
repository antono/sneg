# Checks the home-manager bridge without making home-manager an input: the only
# thing it needs from home-manager is the `programs.mcp.servers` option, so this
# declares a stand-in and evaluates the module against it.
#
# Asserting on real store paths is the point — it proves the bridge resolved
# packages through sneg's overlay for its own servers and through
# mcp-servers-nix' for upstream's.
{ snegLib, pkgs }:
let
  inherit (pkgs) lib;

  eval = lib.evalModules {
    specialArgs = { inherit pkgs lib; };
    modules = [
      {
        options.programs.mcp.servers = lib.mkOption {
          type = lib.types.attrsOf lib.types.anything;
          default = { };
        };
      }
      (import ../modules/home-manager.nix { inherit snegLib; })
      {
        mcp-servers.programs = {
          nixos.enable = true; # mcp-servers-nix
          signoz.enable = true; # sneg
          argocd = {
            enable = true;
            baseUrl = "https://argocd.example.com";
          };
        };
      }
    ];
  };
in
pkgs.runCommand "sneg-mcp-home-manager"
  {
    json = builtins.toJSON eval.config.programs.mcp.servers;
    passAsFile = [ "json" ];
  }
  ''
    cp "$jsonPath" "$out"

    grep -q '/bin/mcp-nixos' "$out"
    grep -q '/bin/signoz-mcp-server' "$out"
    grep -q '/bin/argocd-mcp' "$out"
    grep -q 'ARGOCD_BASE_URL' "$out"

    # `type` is dropped so home-manager can infer the transport itself.
    if grep -q '"type"' "$out"; then
      echo "bridge leaked a 'type' key into programs.mcp.servers" >&2
      exit 1
    fi
  ''
