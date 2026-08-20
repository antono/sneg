# Reads GREENHOUSE_API_KEY from the environment — set it through `envFile` or
# `passwordCommand` rather than `env`, which is world-readable in /nix/store.
{ mkServerModule, ... }:
{
  imports = [
    (mkServerModule {
      name = "greenhouse";
      packageName = "greenhouse-mcp";
    })
  ];
}
