{ mkServerModule, ... }:
{
  imports = [
    (mkServerModule {
      name = "freecad";
      packageName = "freecad-mcp";
    })
  ];
}
