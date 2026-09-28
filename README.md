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
| [`deplexity`](https://github.com/clappingmonkey/Deplexity) | Export Perplexity AI conversations, spaces and profile to JSON/Markdown/PDF |
| [`deplexity-with-chromium`](https://github.com/clappingmonkey/Deplexity) | Same, bundling Chromium so `deplexity login` works out of the box (linux only) |
| [`tolaria`](https://github.com/antono/tolaria) | Tolaria desktop app bundled with its MCP server (linux only — WebKitGTK 4.1) |
| [`tolaria-mcp`](https://github.com/antono/tolaria) | Just the Tolaria MCP server: vault tools over stdio + a WebSocket bridge |
| [`tolaria-node-modules`](https://github.com/antono/tolaria) | Tolaria's pnpm dependency closure, exposed so the hash can be rebuilt on its own |
| [`tolaria-src`](https://github.com/antono/tolaria) | Tolaria's fetched source, exposed so it can be realised on its own |
| [`hacktv`](https://github.com/captainjack64/hacktv) | Analogue TV signal generator for SDR hardware |
| [`mcphub`](https://github.com/samanhappy/mcphub) | Self-hosted MCP gateway: fronts many MCP servers behind one endpoint, with a dashboard |
| [`argocd-mcp`](https://github.com/argoproj-labs/mcp-for-argocd) | MCP server for Argo CD |
| [`fibery-mcp-server`](https://github.com/Fibery-inc/fibery-mcp-server) | MCP server for Fibery |
| [`freecad-mcp`](https://github.com/neka-nat/freecad-mcp) | MCP server for FreeCAD (pairs with an addon installed into FreeCAD) |
| [`greenhouse-mcp`](https://github.com/UladzislauRedzko/greenhouse-mcp) | MCP server for the Greenhouse Harvest API |
| [`kicad-mcp`](https://github.com/mixelpixx/KiCAD-MCP-Server) | MCP server for KiCAD (wraps a KiCAD install: its `pcbnew` bindings, CLI and libraries) |
| [`konnect`](https://github.com/mixelpixx/Konnect) | MCP server for KiCAD 10, the Rust rewrite of the above — one binary, over KiCAD's IPC API |
| [`mcp-musescore`](https://github.com/ghchen99/mcp-musescore) | MCP server for MuseScore (pairs with a QML plugin) |
| [`signoz-mcp-server`](https://github.com/SigNoz/signoz-mcp-server) | MCP server for SigNoz |

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

The two KiCAD servers are the ones that are not self-contained: both wrap a
`pkgs.kicad` of their own, because `kicad-cli` and the `KICAD<major>_*_DIR`
library paths are otherwise set only by the `kicad` wrapper, which nothing here
runs under. `kicad-mcp` needs more of it — `pcbnew` is a compiled module that
ships inside `kicad` rather than in nixpkgs' python set, so the interpreter is
wrapped too. Each has a README beside its package, and `.override { kicad =
...; }` moves everything together.

They are alternatives, not duplicates: `konnect` is the author's Rust rewrite —
AGPL-3.0, KiCAD 10 only, one binary over the IPC API — while `kicad-mcp` stays
MIT and works against 8 and 9. Enabling both is fine.

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

[`mcphub`](https://github.com/samanhappy/mcphub) is not another server. It is a
gateway: it starts the servers listed in its settings file and re-exports all of
them over one HTTP origin — with a dashboard, bearer keys and a CLI on top — so
a client that cannot spawn stdio children gets a single stable address instead
of N processes of its own.

`homeManagerModules.mcphub` runs it as a user service (systemd on linux,
launchd on darwin):

```nix
{
  imports = [ inputs.sneg.homeManagerModules.mcphub ];

  # Declared once. Direct clients read this; so does the hub.
  programs.mcp.servers.nixos = { ... };

  services.mcphub = {
    enable = true;

    # Servers only the hub should see, in mcphub's own schema. Merged after
    # programs.mcp, so a name repeated here wins.
    servers.deploy-notes = {
      type = "streamable-http";
      url = "https://notes.example.com/mcp";
      # Expanded by mcphub from its own environment, so the token itself never
      # reaches the store.
      headers.Authorization = "Bearer \${NOTES_TOKEN}";
    };

    environmentFile = "/run/secrets/mcphub.env";
  };
}
```

The thing to understand about mcphub is that it *owns its settings file*. There
is exactly one — `mcp_settings.json` — and mcphub does not merely read it: the
admin password hash lands there on first boot, every bearer key and OAuth
client the dashboard mints is appended to it, and every server toggled in the
UI is written back. A store symlink fails on the first write; a file
regenerated on every `home-manager switch` throws away the credentials that
make the dashboard reachable.

So the module treats it as state and merges into it at every start, under one
rule: **every top-level key the module declares replaces that key in the live
file, and every key it does not declare is left alone.** `servers` and
`useHomeManagerServers` declare `mcpServers`; `settings` declares whatever it
names. `users`, `bearerKeys`, `groups`, `oauthClients`, `oauthTokens`, `prompts`
and `resources` therefore survive untouched — and `mcpServers`, once declared,
is declared *entirely*, so a server added through the dashboard is dropped at
the next restart. Declare nothing and the dashboard owns the list.

The merge is shallow on purpose. A recursive one would leave half-overwritten
`systemConfig` subtrees matching neither what Nix said nor what the dashboard
said, so `settings.systemConfig` must be restated whole. It is a jq program in
its own store file, which is what lets `checks.<system>.mcphub-module` run it
against fabricated inputs rather than grepping the shell command that invokes
it.

`useHomeManagerServers` (on by default) folds `~/.config/mcp/mcp.json` in as the
first source of servers, read when the service starts rather than when the
configuration is built. The two schemas line up better than the names suggest:
`type`, `command`, `args`, `env`, `url`, `headers` and — unlike the hub this
replaced — `enabled` all mean the same thing on both sides, so a server switched
off in `programs.mcp` is switched off in the hub too.

The one thing that does not survive the trip is `env.<VAR>.file`, which
home-manager renders as the literal string `{file:/path}` for its per-client
modules to rewrite. mcphub has no such placeholder and hands the token text to
the server as its secret. That warns. The fix is to restate the server under
`services.mcphub.servers` with `env.<VAR> = "${VAR}"`: mcphub expands `${VAR}`
and `$VAR` from its *own* environment across a server's `env`, `args`, `headers`
and `url`, so supplying the variable through `environmentFile` keeps the secret
out of the store — the same rule the server modules follow, and the reason
`environment` is the wrong place for one.

mcphub is configured by environment variable rather than by argument: the module
exports `PORT`, `BASE_PATH` and `MCPHUB_SETTING_PATH` itself and leaves the rest
— `ADMIN_PASSWORD`, `DISABLE_WEB`, `READONLY`, the timeouts — to `environment`
and `environmentFile`. Note that it binds every interface, with no upstream
option to narrow that, and that `settings.systemConfig.routing.skipAuth` turns
every caller on that port into an admin who can register a stdio server. The
module warns about the second; the first is on you.

New generations reach a running hub by restarting it. The start script carries
the whole configuration in its own store path, so the unit's `ExecStart` and the
agent's `ProgramArguments` differ whenever anything does — that is enough for
sd-switch on linux and for home-manager's plist comparison on darwin, with no
generation marker needed. `Unit.X-Restart-Triggers` covers the one input that is
not baked in: the servers home-manager writes to a stable `~/.config` path.
mcphub re-reads its settings when the mtime moves, but the merge that moves it
runs at start, so the restart is the reload.

This module is independent of `homeManagerModules.default` — the bridge writes
`programs.mcp.servers`, the hub merges the file that option generates — so
importing both is fine and is the normal case: the bridge feeds sneg's servers
into `programs.mcp`, and the hub picks them up from there.

```
modules/mcphub.nix        the service module
pkgs/mcphub/package.nix
tests/mcphub-module.nix   checks.<system>.mcphub-module — the rendered unit,
                          the start script, and the merge rule actually run
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
