# sneg

antono's personal Nix package set — the custom packages used by my personal
NixOS/home-manager flake, in one repo instead of one fork per project.

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
| `argocd-mcp` | MCP server for Argo CD |
| `fibery-mcp-server` | MCP server for Fibery |
| `freecad-mcp` | MCP server for FreeCAD (pairs with an addon installed into FreeCAD) |
| `greenhouse-mcp` | MCP server for the Greenhouse Harvest API |
| `mcp-musescore` | MCP server for MuseScore (pairs with a QML plugin) |
| `signoz-mcp-server` | MCP server for SigNoz |

## MCP servers

The servers above are the ones [`mcp-servers-nix`](https://github.com/natsukium/mcp-servers-nix)
does not ship. There is no fork of it: sneg's servers plug into upstream's
module system, and `lib.mkConfig` is a drop-in for upstream's that knows about
both sides.

```nix
programs.mcp.configFile = inputs.sneg.lib.mkConfig pkgs {
  programs = {
    # from mcp-servers-nix
    chrome-devtools.enable = true;
    context7.enable = true;
    nixos.enable = true;
    playwright.enable = true;
    terraform.enable = true;

    # from sneg
    argocd = {
      enable = true;
      baseUrl = "https://argocd.example.com";
      passwordCommand.ARGOCD_API_TOKEN = [ "cat" "/run/secrets/argocd" ];
    };
    signoz.enable = true;
  };
};
```

Secrets go through `envFile` or `passwordCommand`, never `env` or `args` —
everything in `/nix/store` is world-readable. That is why sneg's modules expose
hosts and URLs as options but never tokens.

Prefer upstream's version of a server whenever it gains one: when
`chrome-devtools` landed there, sneg's copy was deleted rather than kept.

### How the composition works

Upstream's `lib.evalModule` takes the nixpkgs instance it resolves server
packages from, plus one module. Both are seams:

- extending nixpkgs with `overlays.mcp-servers` makes `programs.<name>.package`
  resolve sneg's servers by name, exactly as it resolves upstream's;
- the module can `imports` sneg's server modules, which are ordinary
  mcp-servers-nix modules built on upstream's `mkServerModule` specialArg.

`lib/default.nix` does both. If you would rather wire it yourself:

```nix
inputs.mcp-servers-nix.lib.mkConfig (pkgs.extend inputs.sneg.overlays.mcp-servers) {
  imports = inputs.sneg.lib.serverModules;
  programs.signoz.enable = true;
}
```

`checks.<system>.mcp-servers` renders every server from both sides into one
config file, so a bad package name or a clash with an upstream module fails
here rather than at the consumer.

## Layout for MCP servers

```
lib/default.nix                mkConfig / evalModule / serverModules
modules/mcp-servers/<name>.nix one file per server, auto-discovered
pkgs/mcp-servers/<name>/package.nix
tests/mcp-servers.nix          the composition check
```

Package attribute names must match the `packageName` its module passes to
`mkServerModule` — that is the only thing tying the two halves together.

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
