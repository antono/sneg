# MCP servers that mcp-servers-nix does not (yet) ship. Everything here is
# named the way its `modules/mcp-servers/*.nix` counterpart expects, because
# upstream's `mkServerModule` resolves `programs.<name>.package` by looking
# `packageName` up in the nixpkgs instance handed to `lib.mkConfig`.
#
# One line per server, mirroring ../default.nix.
{ final, ... }:
{
  argocd-mcp = final.callPackage ./argocd-mcp/package.nix { };
  fibery-mcp-server = final.callPackage ./fibery-mcp-server/package.nix { };
  freecad-mcp = final.callPackage ./freecad-mcp/package.nix { };
  greenhouse-mcp = final.callPackage ./greenhouse-mcp/package.nix { };
  mcp-musescore = final.callPackage ./mcp-musescore/package.nix { };
  signoz-mcp-server = final.callPackage ./signoz-mcp-server/package.nix { };
}
