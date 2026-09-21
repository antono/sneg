# The package wraps the server so it already knows where KiCAD, its Python
# bindings and its libraries are — see ../../pkgs/mcp-servers/kicad-mcp. What
# is left here is the behaviour that is a matter of taste rather than of paths.
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
  cfg = config.programs.kicad;
in
{
  imports = [
    (mkServerModule {
      name = "kicad";
      packageName = "kicad-mcp";
    })
  ];

  options.programs.kicad = {
    backend = lib.mkOption {
      type = lib.types.nullOr (
        lib.types.enum [
          "auto"
          "ipc"
          "swig"
        ]
      );
      default = null;
      description = ''
        Which KiCAD API to drive, as KICAD_BACKEND. `ipc` talks to a running
        KiCAD over its IPC API, so edits show up in the open window; `swig`
        uses the in-process `pcbnew` bindings and works headless. The default
        (`auto`) tries IPC and falls back to SWIG.
      '';
      example = "swig";
    };

    autoLaunch = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Whether the server may start KiCAD itself when the IPC backend finds
        nothing to connect to, via KICAD_AUTO_LAUNCH. Off upstream, and off
        here: it spawns a GUI application as a side effect of a tool call.
      '';
    };

    interactiveSchematic = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Whether to edit schematics through a running Eeschema rather than by
        rewriting the `.kicad_sch` file on disk, via
        KICAD_INTERACTIVE_SCHEMATIC.
      '';
    };

    logLevel = lib.mkOption {
      type = lib.types.nullOr (
        lib.types.enum [
          "error"
          "warn"
          "info"
          "debug"
        ]
      );
      default = null;
      description = ''
        Verbosity of the log written to `~/.kicad-mcp/logs`, as
        KICAD_MCP_LOG_LEVEL. Upstream defaults to `info`.
      '';
      example = "debug";
    };
  };

  # No secrets here — this server talks to a local KiCAD install, not to an
  # API. The JLCPCB credentials its part-lookup tool can use are the one
  # exception, and belong in `envFile` or `passwordCommand` like every other.
  config.settings.servers = lib.mkIf cfg.enable {
    kicad.env =
      lib.optionalAttrs (cfg.backend != null) { KICAD_BACKEND = cfg.backend; }
      // lib.optionalAttrs cfg.autoLaunch { KICAD_AUTO_LAUNCH = "true"; }
      // lib.optionalAttrs cfg.interactiveSchematic { KICAD_INTERACTIVE_SCHEMATIC = "true"; }
      // lib.optionalAttrs (cfg.logLevel != null) { KICAD_MCP_LOG_LEVEL = cfg.logLevel; };
  };
}
