# Configured entirely through SIGNOZ_URL and SIGNOZ_API_KEY. Put the key in an
# `envFile` or `passwordCommand`; `env` is world-readable in /nix/store.
{ mkServerModule, ... }:
{
  imports = [
    (mkServerModule {
      name = "signoz";
      packageName = "signoz-mcp-server";
    })
  ];
}
