# Half of this server is a Blender extension that has to be installed into
# Blender's own config directory, and Blender has to be running with online
# access on for it to answer. Neither is expressible as an option here, so both
# live in ../../pkgs/mcp-servers/blender-mcp/README.md — what is left in this
# module is the pair of addresses the client side needs.
#
# Every option below is written with `--set-default` semantics in mind: the
# wrapper only fills in what the environment does not already set, so anything
# put in `env` here wins over the package's own defaults.
{
  config,
  lib,
  mkServerModule,
  ...
}:
let
  cfg = config.programs.blender;
in
{
  imports = [
    (mkServerModule {
      name = "blender";
      packageName = "blender-mcp";
    })
  ];

  options.programs.blender = {
    host = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = ''
        Where the add-on's socket server is listening, as BLENDER_MCP_HOST. It
        has to match the host the add-on was started with in Blender's own
        preferences; the default there is `localhost`.
      '';
      example = "localhost";
    };

    port = lib.mkOption {
      type = lib.types.nullOr lib.types.port;
      default = null;
      description = ''
        The port the add-on's socket server listens on, as BLENDER_MCP_PORT.
        It has to match the port the add-on was started with in Blender's own
        preferences; the default there is 9876. The add-on binds to the
        loopback address and takes no authentication, so a host other than
        localhost means giving anyone who can reach that port the ability to run
        Python inside Blender.
      '';
      example = 9876;
    };
  };

  config.settings.servers = lib.mkIf cfg.enable {
    blender.env =
      lib.optionalAttrs (cfg.host != null) { BLENDER_MCP_HOST = cfg.host; }
      // lib.optionalAttrs (cfg.port != null) {
        BLENDER_MCP_PORT = toString cfg.port;
      };
  };
}
