{
  config,
  lib,
  mkServerModule,
  ...
}:
let
  cfg = config.programs.fibery;
in
{
  imports = [
    (mkServerModule {
      name = "fibery";
      packageName = "fibery-mcp-server";
    })
  ];

  options.programs.fibery = {
    host = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = ''
        Fibery account host, exported as FIBERY_HOST.
      '';
      example = "your-account.fibery.io";
    };
  };

  # The server reads FIBERY_API_TOKEN too, but it is deliberately not an option:
  # both `env` and `args` land in the world-readable /nix/store. Supply it via
  # `envFile` or `passwordCommand`.
  config.settings.servers = lib.mkIf cfg.enable {
    fibery = {
      env = lib.optionalAttrs (cfg.host != null) { FIBERY_HOST = cfg.host; };
    };
  };
}
