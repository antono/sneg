# kicad-mcp

[KiCAD-MCP-Server](https://github.com/mixelpixx/KiCAD-MCP-Server) over stdio:
229 tools covering board layout, routing, DRC, schematic editing, exports and
part lookup. Unlike `freecad-mcp`, there is nothing to install into KiCAD by
hand — the package carries its own KiCAD and finds everything through it.

See also [`konnect`](../konnect), the same author's Rust rewrite of this
server. It is AGPL-3.0 and needs KiCAD 10; this one stays MIT and works against
8 and 9, and upstream maintains both. Enabling both is fine.

## Enable it

```nix
{
  imports = [ inputs.sneg.homeManagerModules.default ];

  mcp-servers.programs.kicad.enable = true;
}
```

That goes through home-manager's `programs.mcp.servers`, so any client with
`enableMcpIntegration` picks it up. Through `sneg.lib.mkConfig` instead:

```nix
programs.mcp.configFile = inputs.sneg.lib.mkConfig pkgs {
  programs.kicad.enable = true;
};
```

Or skip the module set entirely and point a client at
`${pkgs.kicad-mcp}/bin/kicad-mcp` — the wrapper needs no environment of its own.

## Options

| Option | Environment variable | Default |
| --- | --- | --- |
| `backend` | `KICAD_BACKEND` | `auto` |
| `autoLaunch` | `KICAD_AUTO_LAUNCH` | `false` |
| `interactiveSchematic` | `KICAD_INTERACTIVE_SCHEMATIC` | `false` |
| `logLevel` | `KICAD_MCP_LOG_LEVEL` | `info` |

Everything else mcp-servers-nix gives every server — `env`, `envFile`,
`passwordCommand`, `package` — works here too.

## The two backends

`swig` drives the in-process `pcbnew` bindings. It works with no KiCAD window
open, edits the `.kicad_pcb` file on disk, and is what you want for batch work.

`ipc` talks to a *running* KiCAD over its IPC API, so edits appear in the open
window as they happen. KiCAD does not listen by default: turn it on under
**Preferences → Plugins → Enable IPC API Server**, and leave KiCAD running.

`auto` — the default — tries IPC and falls back to SWIG, which means a tool call
silently changes meaning depending on whether KiCAD happens to be open. Pin it
when that matters:

```nix
mcp-servers.programs.kicad = {
  enable = true;
  backend = "swig";
};
```

`autoLaunch` lets the IPC backend start KiCAD itself when it finds nothing to
connect to. It is off here and upstream, because it spawns a GUI application as
a side effect of a tool call.

## What the wrapper sets

The server is two processes: a Node MCP server that spawns
`python/kicad_interface.py`, which does the real work through KiCAD's Python
API. That API is not in nixpkgs' python set — `pcbnew` is a compiled module
built as part of KiCAD and installed into `kicad.base`, importable only from the
interpreter KiCAD was built against. Nor is the rest of KiCAD discoverable:
symbols, footprints, 3D models and templates are found through
`KICAD<major>_*_DIR`, which on nixpkgs only the `kicad` wrapper sets — and
nothing here runs under that wrapper.

So `bin/kicad-mcp` supplies all of it:

| Variable | Points at |
| --- | --- |
| `KICAD_PYTHON` | a `python3.withPackages` env with upstream's Python requirements |
| `PYTHONPATH` | `${kicad.base}/lib/python3.x/site-packages`, where `pcbnew` lives |
| `KICAD_CLI` | `kicad-cli` from the wrapped `kicad` (exports shell out to it) |
| `KICAD<major>_SYMBOL_DIR` | the symbol library |
| `KICAD<major>_FOOTPRINT_DIR` | the footprint library |
| `KICAD<major>_3DMODEL_DIR` | the 3D model library |
| `KICAD<major>_TEMPLATE_DIR` | the project templates |
| `PATH` | `kicad`, appended, so `shutil.which("kicad-cli")` also resolves |

All of these are `--set-default`, so anything you put in the module's `env`
wins. `PATH` is a suffix, so a KiCAD already on your PATH takes precedence.

A build-time check imports `pcbnew`, `skip`, `sexpdata` and `kipy` through that
same interpreter and PYTHONPATH — so a KiCAD bump or a `python3` bump that moves
`site-packages` fails here rather than at the first tool call.

## A different KiCAD

The interpreter, the CLI and the library paths are all derived from one package
argument, so they move together:

```nix
pkgs.kicad-mcp.override { kicad = pkgs.kicad-small; }
```

Anything without Python scripting will fail the install check, which is the
point.

## JLCPCB credentials

`get_jlcpcb_part` can hit JLCPCB's API for live pricing and stock; without
credentials it falls back to a local snapshot, and search is always local.

Upstream reads them from a `.env` beside the package root. That never works
here — the package root is a read-only store path — so pass them through the
environment:

```nix
mcp-servers.programs.kicad = {
  enable = true;
  envFile = "/run/secrets/jlcpcb.env";   # JLCPCB_APP_ID, JLCPCB_API_KEY, JLCPCB_API_SECRET
};
```

Not `env`: everything in `/nix/store` is world-readable.

## Logs

`~/.kicad-mcp/logs/kicad-mcp-<date>.log`, rotated by the server. Raise the
detail with `logLevel = "debug"`; the Python child's own output is relayed onto
the server's stderr, which most clients capture.

## Bump it

```bash
nix-update --flake kicad-mcp
nix build -L .#kicad-mcp
```

`nix-update` rewrites the version and `src` hash but not `npmDepsHash` — set
that from the mismatch the first build reports. Upstream tags track
`package.json`, so the tag is the version.

Watch two things across a bump: whether `python/` grew an import that is not in
`pythonEnv` (upstream's `requirements.txt` is wider than its imports, so read
the imports, not the file), and whether the `KICAD<major>_*_DIR` lists in
`python/commands/dynamic_symbol_loader.py` and its neighbours learned a new
major version — they are hardcoded tuples, currently 10, 9 and 8.
