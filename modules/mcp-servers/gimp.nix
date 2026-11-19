# Half of this server is a GIMP plug-in that GIMP has to load. `withGimp` puts a
# GIMP carrying it on PATH when this goes through the Home Manager bridge;
# otherwise ../../pkgs/mcp-servers/gimp-mcp/README.md has the ways to load it.
#
# `autostart` and `port` are baked into the package as the plug-in's defaults
# (and `port` as the server's), so the plug-in inside GIMP and the server the
# client launches cannot drift apart. They are defaults, not pins: a setting
# saved from GIMP's own MCP Server Settings dialog still wins.
{
  config,
  lib,
  mkServerModule,
  servers,
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
    autostart = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Start the plug-in's MCP server when GIMP launches, instead of from
        Tools > MCP > Start MCP Server every time. Without it, the first tool
        call after starting GIMP fails with a connection error.
      '';
    };

    port = lib.mkOption {
      type = lib.types.port;
      default = 9877;
      description = ''
        The port the plug-in listens on and the server connects to (as
        GIMP_MCP_PORT). Applied to both halves through the package.
      '';
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

    withGimp = lib.mkEnableOption ''
      GIMP with this server's plug-in, built from {option}`gimpPackage`.
      Only the Home Manager bridge installs it (into home.packages); through
      `lib.mkConfig` this has no effect'';

    gimpPackage = lib.mkPackageOption servers "gimp3-with-plugins" { };
  };

  config = lib.mkIf cfg.enable {
    programs.gimp.package = lib.mkDefault (servers.gimp-mcp.override { inherit (cfg) autostart port; });

    settings.servers.gimp.env = lib.optionalAttrs (cfg.timeout != null) {
      GIMP_MCP_TIMEOUT = toString cfg.timeout;
    };

    # Appended to a `plugins` list `gimpPackage` already carries. The wrapper's
    # own default, null, means "every plug-in in gimp3Plugins"; that is not
    # kept, so a bare gimp3-with-plugins becomes GIMP plus gimp-mcp alone.
    homePackages = lib.optional cfg.withGimp (
      cfg.gimpPackage.override (old: {
        plugins = (if old.plugins or null == null then [ ] else old.plugins) ++ [ cfg.package ];
      })
    );
  };
}
