# Home Manager bridge: `mcp-servers.programs.<name>` in, home-manager's own
# `programs.mcp.servers` out, so claude-code, opencode, codex and friends pick
# the servers up through their `enableMcpIntegration` options.
#
# A drop-in superset of `mcp-servers-nix.homeManagerModules.default`: same
# option path, but the module set includes sneg's servers. Import one or the
# other, never both — they declare the same options.
{ snegLib }:
{
  config,
  pkgs,
  lib,
  ...
}:
let
  cfg = config.mcp-servers;

  # "claude" is the flavor whose shape matches programs.mcp.servers.
  evaluated = snegLib.evalModule pkgs {
    inherit (cfg) programs settings;
    flavor = "claude";
  };

  servers = evaluated.config.settings.servers or { };

  # home-manager infers the transport from the presence of `command` (stdio) or
  # `url` (remote), so `type` is dropped rather than passed through.
  transformServer =
    _name: server:
    lib.filterAttrs (_: v: v != null && v != [ ] && v != { }) (
      lib.removeAttrs (
        lib.optionalAttrs (server ? command) { inherit (server) command; }
        // lib.optionalAttrs (server ? args) { args = map toString server.args; }
        // lib.optionalAttrs (server ? env) { env = lib.mapAttrs (_: toString) server.env; }
        // lib.optionalAttrs (server ? url) { inherit (server) url; }
        // lib.optionalAttrs (server ? headers) { inherit (server) headers; }
      ) [ "type" ]
    );
in
{
  options.mcp-servers = {
    programs = lib.mkOption {
      type = lib.types.attrsOf lib.types.anything;
      default = { };
      description = ''
        MCP server configurations, as accepted by `sneg.lib.mkConfig`: every
        `programs.<name>` mcp-servers-nix declares, plus the ones sneg adds.
      '';
      example = lib.literalExpression ''
        {
          nixos.enable = true;
          signoz = {
            enable = true;
            envFile = "/run/secrets/signoz.env";
          };
        }
      '';
    };

    settings = lib.mkOption {
      type = lib.types.submodule {
        freeformType = (pkgs.formats.json { }).type;
      };
      default = { };
      description = ''
        Freeform settings merged into the generated configuration.
      '';
    };
  };

  config = lib.mkIf (servers != { }) {
    programs.mcp.servers = lib.mapAttrs transformServer servers;
  };
}
