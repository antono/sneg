{
  config,
  lib,
  mkServerModule,
  ...
}:
let
  cfg = config.programs.argocd;
in
{
  imports = [
    (mkServerModule {
      name = "argocd";
      packageName = "argocd-mcp";
    })
  ];

  options.programs.argocd = {
    baseUrl = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = ''
        Argo CD instance URL, exported as ARGOCD_BASE_URL.
      '';
      example = "https://argocd.example.com";
    };

    readOnly = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Disable the mutating tools (create, update, delete and sync
        applications) by exporting MCP_READ_ONLY.
      '';
    };

    tlsRejectUnauthorized = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Whether to verify the Argo CD server's TLS certificate. Set to false
        for self-signed certificates or a private CA.
      '';
    };
  };

  # ARGOCD_API_TOKEN is deliberately not an option: anything set through `env`
  # ends up in the world-readable /nix/store. Supply it via `envFile` or
  # `passwordCommand` instead.
  config.settings.servers = lib.mkIf cfg.enable {
    argocd = {
      args = [ "stdio" ];
      env =
        lib.optionalAttrs (cfg.baseUrl != null) { ARGOCD_BASE_URL = cfg.baseUrl; }
        // lib.optionalAttrs cfg.readOnly { MCP_READ_ONLY = "true"; }
        // lib.optionalAttrs (!cfg.tlsRejectUnauthorized) { NODE_TLS_REJECT_UNAUTHORIZED = "0"; };
    };
  };
}
