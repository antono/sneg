# MCP servers that mcp-servers-nix does not (yet) ship. Everything here is
# named the way its `modules/mcp-servers/*.nix` counterpart expects, because
# upstream's `mkServerModule` resolves `programs.<name>.package` by looking
# `packageName` up in the nixpkgs instance handed to `lib.mkConfig`.
#
# One line per server, mirroring ../default.nix.
#
# `prev`, not `final`, decides which attributes exist — see ../default.nix.
{ final, prev }:
{
  argocd-mcp = final.callPackage ./argocd-mcp/package.nix { };
  blender-mcp = final.callPackage ./blender-mcp/package.nix { };
  freecad-mcp = final.callPackage ./freecad-mcp/package.nix { };
  greenhouse-mcp = final.callPackage ./greenhouse-mcp/package.nix { };
  mcp-musescore = final.callPackage ./mcp-musescore/package.nix { };
  signoz-mcp-server = final.callPackage ./signoz-mcp-server/package.nix { };
  telegram-mcp = final.callPackage ./telegram-mcp/package.nix { };
}
# Only where nixpkgs' KiCAD evaluates. Its base.nix sets
# `broken = stdenv.hostPlatform.isDarwin`, and a flake output that throws on
# evaluation breaks every tool that walks all systems (flakehub-push,
# `nix flake check --all-systems`). Mirrored as a platform test rather than
# `prev.kicad.meta.available`: forcing a package to decide which attributes
# exist recurses through the fixed point.
// prev.lib.optionalAttrs (!prev.stdenv.hostPlatform.isDarwin) {
  kicad-mcp = final.callPackage ./kicad-mcp/package.nix { };
  konnect = final.callPackage ./konnect/package.nix { };
}
