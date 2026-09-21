# konnect

[Konnect](https://github.com/mixelpixx/Konnect) — the same author's Rust
rewrite of [kicad-mcp](../kicad-mcp). One static binary speaking MCP over
stdio, driving KiCAD 10 through its official IPC API instead of the SWIG
`pcbnew` bindings, with schematic editing done directly on the `.kicad_sch`
S-expressions and no KiCAD process required.

It does not supersede `kicad-mcp` here. Pick on two axes:

| | `konnect` | `kicad-mcp` |
| --- | --- | --- |
| Licence | AGPL-3.0 | MIT |
| KiCAD | 10 only | 8, 9, 10 |
| PCB edits | IPC, undo-aware, live in the open window | SWIG, on-disk, headless |
| Runtime | one binary | Node + Python + `pcbnew` |

Enabling both is fine — separate servers, separate tool names.

## Enable it

```nix
{
  imports = [ inputs.sneg.homeManagerModules.default ];

  mcp-servers.programs.konnect.enable = true;
}
```

Or point any client at `${pkgs.konnect}/bin/konnect` — running it bare is the
MCP server; every other mode is a subcommand.

## Options

| Option | Environment variable |
| --- | --- |
| `logLevel` | `RUST_LOG` |
| `kicadApiSocket` | `KICAD_API_SOCKET` |
| `stateDir` | `KONNECT_STATE_DIR` |

Everything mcp-servers-nix gives every server — `env`, `envFile`,
`passwordCommand`, `package` — works here too.

Konnect's own settings live in `~/.config/konnect/config.toml`, and that is
where `transport` (`"stdio"`, `"http"` or `"both"`) and the toolset defaults
belong. It also searches for a `settings.json` beside its executable, which
under Nix is a read-only store path and so never matches.

## 22 tools, not 226

A fresh `tools/list` returns 22 — the router, project and config tools. That is
the design, not a broken build: the rest of upstream's 226 sit in 21 on-demand
toolsets to keep the context cost down. The model calls `list_toolboxes` and
then `load_toolset` to pull in what a task needs; `get_active_toolsets` shows
what is currently loaded.

## What the wrapper sets

Konnect's KiCAD coupling is narrower than kicad-mcp's — there are no Python
bindings to find — but two things still are not discoverable from outside
KiCAD's own wrapper:

| Variable | Points at |
| --- | --- |
| `KICAD_CLI`, `KICAD_CLI_PATH` | `kicad-cli`, which exports and DRC/ERC shell out to |
| `KICAD10_SYMBOL_DIR` | the stock symbol library |
| `KICAD10_FOOTPRINT_DIR` | the stock footprint library |
| `PATH` | `kicad`, appended |

Both CLI variables are set because different modules read different ones. All
are `--set-default`, so the module's `env` wins; `PATH` is a suffix, so a KiCAD
already on your PATH takes precedence.

`KONNECT_BUILD_COMMIT` is baked in at build time. Upstream's build script reads
the commit out of `.git`, which `fetchFromGitHub` does not produce, so without
it the always-visible `get_installation_info` tool reports a null commit and no
client can tell which build is answering. It is pinned beside `version` and
must be bumped with it.

## Live PCB editing

The IPC backend needs KiCAD 10 running with its API server enabled:
**Preferences → Plugins → Enable IPC API Server**. Schematic tools, exports and
design review work without it.

## The KiCAD plugin

`share/konnect/plugin` is the KiCAD-side half: a Python action plugin that adds
a Konnect button to the PCB editor and gates the optional native Specctra
bridge. It is installed as *source to copy*, not as something loadable in
place — it writes a `settings.json` beside itself, which a store path will not
allow:

```bash
mkdir -p ~/.local/share/kicad/10.0/3rdparty/plugins
cp -r --no-preserve=mode /nix/store/…-konnect-*/share/konnect/plugin \
  ~/.local/share/kicad/10.0/3rdparty/plugins/konnect
```

The one path that must not stay relative — the server binary the plugin
launches — is rewritten at build time to this package's `bin/konnect`, so the
copy still uses the store binary. Upstream's supported route is the Plugin and
Content Manager, which installs a prebuilt binary; that is what this replaces.

Everything the plugin offers is optional. The MCP server needs none of it.

## Client guidance

`konnect init` installs Konnect's bundled KiCAD skills, agents and hooks into
`~/.claude` (or `~/.agents/skills` with `--client codex`), and `konnect
uninstall` removes them. Starting the server never installs or restores them,
so this stays an explicit, reversible step you run yourself.

## Bump it

```bash
nix-update --flake konnect
nix build -L .#konnect
```

Three things move together and `nix-update` only moves one: `version`, the
`rev` that `KONNECT_BUILD_COMMIT` pins — dereference the annotated tag, not the
tag object — and `cargoHash`, from the mismatch the first build reports.

The build needs `protoc` and `cmake` (the `nng` crate compiles the NNG C
library). `checkPhase` runs upstream's own `-p konnect --lib --tests` gate, and
`installCheckPhase` asserts `konnect --version` matches `version` — which is
what catches a stale version against a bumped tag.
