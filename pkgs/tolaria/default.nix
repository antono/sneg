# Tolaria — personal knowledge and life management app (Tauri 2 + React 19).
#
# Ported from the `nixos` branch of github:antono/tolaria, which carries the
# project's own flake under nix/. The pieces are kept as separate files, as
# upstream has them, so changes can be diffed against it. What changed here:
#
#   * `src` is fetched by rev instead of being a `lib.fileset` over the repo
#     checkout. The filesets existed to keep rebuilds from triggering on
#     unrelated files; a pinned fetch is already immutable, so they are gone.
#   * `version` comes from this file rather than being hardcoded per output.
#
# The branch has no release tag, so the pin is a commit and the version uses
# the nixpkgs `-unstable-<date>` convention. Advance both together.
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
  version = "0.1.0-unstable-2026-08-03";

  src = fetchFromGitHub {
    owner = "antono";
    repo = "tolaria";
    rev = "ee192622e903b6a8bac18ff346bb6e4e4cd88a6d";
    hash = "sha256-yHU6sKz9PrRQbqVp2pzprCL4HM10Zo20szVvPMYg5bU=";
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
  inherit nodeModules mcp bundle;
}
