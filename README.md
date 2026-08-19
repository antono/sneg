# snowball

ant0no's personal Nix package set — the custom packages used by
[`the-flake`](https://github.com/antono/the-flake), in one repo instead of one
fork per project.

## Use it

```nix
{
  inputs.snowball = {
    url = "github:antono/snowball";
    inputs.nixpkgs.follows = "nixpkgs";
  };
}
```

Then either take the overlay, which makes everything available as `pkgs.<name>`:

```nix
nixpkgs.overlays = [ inputs.snowball.overlays.default ];
```

or reach for a single package directly:

```nix
inputs.snowball.packages.${system}.deplexity
```

## Packages

| Attribute | What |
| --- | --- |
| `deplexity` | Export Perplexity AI conversations, spaces and profile to JSON/Markdown/PDF |
| `deplexity-with-chromium` | Same, bundling Chromium so `deplexity login` works out of the box (linux only) |

## Layout

```
flake.nix              packages.<system>.*, overlays.default, checks, devShell
overlay.nix            final: _prev: import ./pkgs final
pkgs/default.nix       the package list — one line per package
pkgs/<name>/package.nix
```

`pkgs/default.nix` is the single source of truth: `overlays.default` and
`packages.<system>` are both derived from it.

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
