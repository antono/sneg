# The Rust successor to `kicad`/kicad-mcp, and a second opinion rather than a
# replacement: it needs KiCAD 10 and is AGPL-3.0, where the other still works
# against 8 and 9 under MIT. Enabling both is fine — they are separate servers
# with separate tool names.
#
# Konnect's own settings live in `~/.config/konnect/config.toml`, which is
# where `transport` (stdio, http or both) and the toolset defaults belong. It
# also looks for a `settings.json` beside its executable, which under Nix is a
# read-only store path and never matches — so the config file is the seam, and
# only the environment overrides are options here.
{
  config,
  lib,
  mkServerModule,
  ...
}:
let
  cfg = config.programs.konnect;
in
{
  imports = [
    (mkServerModule {
      name = "konnect";
      packageName = "konnect";
    })
  ];

  options.programs.konnect = {
    logLevel = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = ''
        A `tracing` filter, exported as RUST_LOG, overriding the `log_level`
        in konnect's config file. Logs go to stderr, which most MCP clients
        capture.
      '';
      example = "konnect=debug,konnect_core=debug";
    };

    kicadApiSocket = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = ''
        Endpoint of KiCAD 10's IPC API server, as KICAD_API_SOCKET. Only
        needed when KiCAD is not listening where konnect expects; the socket
        has to be enabled in KiCAD under Preferences -> Plugins.
      '';
      example = "ipc:///tmp/kicad/api.sock";
    };

    stateDir = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = ''
        Absolute path for konnect's transaction journal and caches, as
        KONNECT_STATE_DIR. Defaults to the platform local-data directory.
      '';
      example = "/var/lib/konnect";
    };
  };

  config.settings.servers = lib.mkIf cfg.enable {
    konnect.env =
      lib.optionalAttrs (cfg.logLevel != null) { RUST_LOG = cfg.logLevel; }
      // lib.optionalAttrs (cfg.kicadApiSocket != null) { KICAD_API_SOCKET = cfg.kicadApiSocket; }
      // lib.optionalAttrs (cfg.stateDir != null) { KONNECT_STATE_DIR = cfg.stateDir; };
  };
}
