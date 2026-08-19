# sneg

ant0no's personal Nix package set — the custom packages used by
[`the-flake`](https://github.com/antono/the-flake), in one repo instead of one
fork per project.

## Use it

```nix
{
  inputs.sneg = {
    url = "github:antono/sneg";
    inputs.nixpkgs.follows = "nixpkgs";
  };
}
```

Then either take the overlay, which makes everything available as `pkgs.<name>`:

```nix
nixpkgs.overlays = [ inputs.sneg.overlays.default ];
```

or reach for a single package directly:

```nix
inputs.sneg.packages.${system}.deplexity
```

## Packages

| Attribute | What |
| --- | --- |
| `deplexity` | Export Perplexity AI conversations, spaces and profile to JSON/Markdown/PDF |
| `deplexity-with-chromium` | Same, bundling Chromium so `deplexity login` works out of the box (linux only) |
| `tolaria` | Tolaria desktop app bundled with its MCP server (linux only — WebKitGTK 4.1) |
| `tolaria-mcp` | Just the Tolaria MCP server: vault tools over stdio + a WebSocket bridge |
| `tolaria-node-modules` | Tolaria's pnpm dependency closure, exposed so the hash can be rebuilt on its own |
| `tolaria-src` | Tolaria's fetched source, exposed so it can be realised on its own |

### One caveat: tolaria evaluates via import-from-derivation

crane reads tolaria's `Cargo.lock` and `Cargo.toml` out of the fetched tree, so
merely *evaluating* `tolaria` requires its source to already be in the store.
Upstream's flake avoids this only because its `src` is a local path.

Consequences, all of them handled in `.github/workflows/ci.yml`:

- `nix flake check --no-build` cannot instantiate tolaria on a cold store.
  Run `nix build --no-link .#tolaria-src` first.
- `--all-systems` cannot work: evaluating `packages.aarch64-*` would need an
  aarch64 source derivation realised on an x86_64 machine.

## Layout

```
flake.nix              packages.<system>.*, overlays.default, checks, devShell
overlay.nix            final: _prev: import ./pkgs final
pkgs/default.nix       the package list — one line per package
pkgs/<name>/package.nix
```

`pkgs/default.nix` is the single source of truth: `overlays.default` and
`packages.<system>` are both derived from it.

A package that ships several outputs from one source tree (tolaria) gets a
directory with a `default.nix` returning a set, which `pkgs/default.nix` splices
into the package set under its final names.

Two rules the overlay has to obey:

- Anything deciding **which attributes exist** must read `prev`, not `final`.
  Reading `final.stdenv` there sends the nixpkgs stdenv bootstrap into infinite
  recursion.
- Extra flake inputs (`fenix`, `crane` — both only for tolaria) reach packages
  through the `inputs` argument threaded from `flake.nix` via `overlay.nix`.
  Prefer packages that need nothing beyond nixpkgs.

## Add a package

1. `pkgs/<name>/package.nix` — a plain `callPackage`-able derivation. Keep it
   nixpkgs-shaped (`fetchFromGitHub` pinned to a release tag, no local paths, no
   flake inputs) so it can be sent upstream as-is later.
2. One line in `pkgs/default.nix`.
3. `git add` it — flakes ignore untracked files — then `nix flake check -L`.

Starting from scratch? `nix run nixpkgs#nix-init -- pkgs/<name>/package.nix`
generates a first draft.

## Bump a package

```bash
nix-update --flake deplexity     # rewrites version, src hash and vendorHash
nix flake check -L
```

## Develop

```bash
nix develop          # nix-update, nix-init, nixfmt-tree
nix fmt
nix build .#deplexity && ./result/bin/deplexity --version
```
