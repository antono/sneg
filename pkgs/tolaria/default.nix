# Tolaria — personal knowledge and life management app (Tauri 2 + React 19).
#
# The build files are ported from the `nixos` branch of github:antono/tolaria,
# which carries a flake under nix/. The pieces are kept as separate files, as
# that branch has them, so changes can be diffed against it. What changed here:
#
#   * `src` is fetched from GitHub instead of being a `lib.fileset` over the repo
#     checkout. The filesets existed to keep rebuilds from triggering on
#     unrelated files; a pinned fetch is already immutable, so they are gone.
#   * `version` comes from this file rather than being hardcoded per output.
#
# The source is the upstream release tag, not the fork: the fork only adds the
# nix/ files, which live here. Upstream tags stable releases by date
# (`v2026-10-13`) and leaves the in-tree version at 0.1.0, so the date is the
# version. Pre-releases are tagged `alpha-v...`; skip those.
{
  lib,
  pkgs,
  stdenv,
  fetchFromGitHub,
  symlinkJoin,
  fenix,
  crane,
}:

let
  version = "2026-10-13";

  src = fetchFromGitHub {
    owner = "refactoringhq";
    repo = "tolaria";
    tag = "v${version}";
    hash = "sha256-gB3PHW88GN9oGWt9v5LYN1Jbs1Bcy4SfkdivjaZj12k=";
  };

  rust = import ./rust-toolchain.nix {
    inherit
      pkgs
      lib
      fenix
      crane
      ;
    system = stdenv.hostPlatform.system;
  };

  # pnpm dependency closure — pure node files, works on every system.
  nodeModules = import ./node-modules.nix {
    inherit
      pkgs
      lib
      src
      version
      ;
  };

  # stdio MCP server + ws-bridge. Pure node, cross-platform.
  mcp = import ./mcp-server.nix {
    inherit
      pkgs
      lib
      src
      version
      nodeModules
      ;
  };

  # The bare desktop app (crane build). Linux only — WebKitGTK 4.1 stack.
  app = import ./tauri-package.nix {
    inherit
      pkgs
      lib
      src
      version
      nodeModules
      ;
    craneLib = rust.craneLib;
  };

  # `tolaria` ships the desktop app + the MCP server in one installable so
  # launchers and MCP clients (Claude Desktop, Codex, ...) all see the same
  # versioned pair. `tolaria-mcp` stays exposed for users who want only the
  # server (e.g. on a remote node host).
  bundle = symlinkJoin {
    name = "tolaria-${version}";
    paths = [
      app
      mcp
    ];
    meta = app.meta // {
      description = app.meta.description + " (bundled with tolaria-mcp server)";
    };
  };
in
{
  # `src` is exported so it can be realised on its own. Evaluating the app is
  # import-from-derivation — crane reads Cargo.lock/Cargo.toml out of the
  # fetched tree — so the source must already exist in the store before any of
  # this will instantiate at all. See the CI workflow.
  inherit
    src
    nodeModules
    mcp
    bundle
    ;
}
