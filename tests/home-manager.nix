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
        options.home.packages = lib.mkOption {
          type = lib.types.listOf lib.types.package;
          default = [ ];
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
          gimp = {
            enable = true;
            autostart = true;
            port = 9988;
            withGimp = true;
          };
        };
      }
    ];
  };

  # GIMP that `gimp.withGimp` asks for, checked by name and by the plug-in it
  # was built with — both without string context, so this check does not build
  # (or require a platform with) GIMP.
  homePackages = eval.config.home.packages;
  gimp = lib.findFirst (p: lib.hasPrefix "gimp-with-plugins" p.name) null homePackages;

  # gimp-mcp itself is cheap to build, so its baked-in defaults are checked on
  # the real file.
  gimpMcp = dirOf (dirOf eval.config.programs.mcp.servers.gimp.command);
in
assert lib.assertMsg (gimp != null) "gimp.withGimp did not add GIMP to home.packages";
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
    grep -q '/bin/gimp-mcp-server' "$out"
    grep -qF 'DEFAULT_SETTINGS = {"autostart": True, "port": 9988}' \
      ${gimpMcp}/lib/gimp/3.0/plug-ins/gimp-mcp-plugin/gimp-mcp-plugin.py
    grep -qF 'GIMP_MCP_PORT' ${gimpMcp}/bin/gimp-mcp-server
    grep -qF '9988' ${gimpMcp}/bin/gimp-mcp-server

    # `type` is dropped so home-manager can infer the transport itself.
    if grep -q '"type"' "$out"; then
      echo "bridge leaked a 'type' key into programs.mcp.servers" >&2
      exit 1
    fi
  ''
