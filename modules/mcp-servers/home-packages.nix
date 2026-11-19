# Not a server: the one option servers use to hand the Home Manager bridge
# (../home-manager.nix) packages to install alongside them — e.g. a GIMP that
# carries gimp-mcp's plug-in. Declared once here so several servers can add to
# it. Through `lib.mkConfig` nothing reads it.
{ lib, ... }:
{
  options.homePackages = lib.mkOption {
    type = lib.types.listOf lib.types.package;
    default = [ ];
    internal = true;
    description = "Packages the Home Manager bridge adds to home.packages.";
  };
}
