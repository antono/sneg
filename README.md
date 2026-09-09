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
| `hacktv` | Analogue TV signal generator for SDR hardware |
| `mcp-hub` | Supervises a set of MCP servers and re-exports them over one HTTP port |
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

## The hub

[`mcp-hub`](https://github.com/ravitemer/mcp-hub) is not another server. It is a
supervisor: it starts the servers it is given and re-exports all of them over
one HTTP port, so clients that cannot spawn stdio children — mcphub.nvim above
all — get a single stable address instead of N processes of their own.

`homeManagerModules.mcphub` runs it as a user service (systemd on linux,
launchd on darwin):

```nix
{
  imports = [ inputs.sneg.homeManagerModules.mcphub ];

  # Declared once. Direct clients read this; so does the hub.
  programs.mcp.servers.nixos = { ... };

  services.mcphub = {
    enable = true;

    # Servers only the hub should see, in mcp-hub's own schema. Merged after
    # programs.mcp, so a name repeated here wins.
    servers.deploy-notes = {
      url = "https://notes.example.com/mcp";
      headers.Authorization = "Bearer \${cmd: cat /run/secrets/notes-token}";
    };
  };
}
```

The seam is the config file. `--config` takes JSON whose top-level `mcpServers`
key is exactly what home-manager's `programs.mcp` already writes to
`~/.config/mcp/mcp.json`, so `useHomeManagerServers` (on by default) hands that
file to the hub as it stands rather than restating every server. `--config` is
repeatable and later files win per server — the whole entry, not field by field
— which is what orders the sources: home-manager's file, then
`services.mcphub.servers`, then `extraConfigFiles`.

Two things in that file mean something different to mcp-hub than to a direct
client, and the module refuses to let either pass unnoticed:

- `enabled = false` is home-manager's way of switching a server off. mcp-hub
  reads `disabled` and starts everything else, so such a server would be
  *running* under the hub. That is an assertion, not a warning.
- `env.<VAR>.file` is rendered by home-manager as the literal string
  `{file:/path}`, which only its per-client modules rewrite. mcp-hub resolves
  `${VAR}`, `${env:VAR}`, `${cmd: ...}`, `${userHome}` and `${workspaceFolder}`
  and passes anything else through untouched, so the server gets the token text
  as its secret. That one warns.

Either is fixed by restating the server whole under `services.mcphub.servers`,
using `${cmd: cat /run/secrets/...}` for the secret.

`extraConfigFiles` is for paths that only exist at runtime — a sops-decrypted
file, a per-project config. mcp-hub skips a missing one silently. Secrets in
the hub's own environment go through `environmentFile`, never `environment`:
the latter ends up in a world-readable store file, the same rule the server
modules follow.

`mcp-hub` has no default port and comes up broken rather than failing loudly
when `--config` is empty, so the module supplies mcphub.nvim's `37373` and
asserts that at least one config source will actually exist — `programs.mcp`
writes nothing until it has servers, and a `--config` pointing at a file
nobody writes gets skipped without a word.

`--watch` is on by default, but it only covers a file rewritten in place, which
in practice means `extraConfigFiles`: the generated files are store symlinks,
and mcp-hub's watcher follows the link to an immutable store inode that is
never written. New generations reach the hub by restarting it — through
`Unit.X-Restart-Triggers` on linux, and through a generation marker in the
agent's environment (which makes the plist differ, so home-manager reloads it)
on darwin.

This module is independent of `homeManagerModules.default` — the bridge writes
`programs.mcp.servers`, the hub is pointed at the file that option generates —
so importing both is fine and is the normal case: the bridge feeds sneg's
servers into `programs.mcp`, and the hub picks them up from there.

```
modules/mcphub.nix     the service module
pkgs/mcp-hub/package.nix
tests/mcphub.nix       checks.<system>.mcphub — the rendered unit and JSON
```

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
