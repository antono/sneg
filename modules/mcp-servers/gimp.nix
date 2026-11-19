# Half of this server is a GIMP plug-in that has to be loaded by GIMP and
# started from Tools > MCP. That is not expressible as an option here, so it
# lives in ../../pkgs/mcp-servers/gimp-mcp/README.md — what is left in this
# module is what the client side reads from its environment.
{
  config,
  lib,
  mkServerModule,
  ...
}:
let
  cfg = config.programs.gimp;
in
{
  imports = [
    (mkServerModule {
      name = "gimp";
      packageName = "gimp-mcp";
    })
  ];

  options.programs.gimp = {
    port = lib.mkOption {
      type = lib.types.nullOr lib.types.port;
      default = null;
      description = ''
        The port the plug-in listens on, as GIMP_MCP_PORT. It has to match the
        port set in GIMP under Tools > MCP > MCP Server Settings; the default
        there is 9877.
      '';
      example = 9877;
    };

    timeout = lib.mkOption {
      type = lib.types.nullOr lib.types.ints.positive;
      default = null;
      description = ''
        Seconds to wait for GIMP to finish one command, as GIMP_MCP_TIMEOUT.
        Upstream's default is 300; raise it for large or 16-bit images and slow
        filters. A command that times out may still be running in GIMP.
      '';
      example = 900;
    };
  };

  config.settings.servers = lib.mkIf cfg.enable {
    gimp.env =
      lib.optionalAttrs (cfg.port != null) { GIMP_MCP_PORT = toString cfg.port; }
      // lib.optionalAttrs (cfg.timeout != null) {
        GIMP_MCP_TIMEOUT = toString cfg.timeout;
      };
  };
}
