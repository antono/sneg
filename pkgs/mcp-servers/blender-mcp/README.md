# blender-mcp

[Blender Lab's MCP server](https://projects.blender.org/lab/blender_mcp) over
stdio: 20 tools that drive Blender — object and blend-file summaries, window
and viewport screenshots, `bpy` executed directly, and the bundled API and
manual doc search. Six of them also come as `*_for_cli` variants, which open a
`.blend` in a background Blender instead of talking to the running one, for 26
in all.

Unlike `kicad-mcp`, this one does not carry its own Blender: it drives whichever
Blender you point it at, and half of it lives *inside* Blender as an extension
that has to be installed and started. That half is not expressible as a module
option, so it is written out below. Skip it and every tool call comes back with
the same connection error.

## Enable it

```nix
{
  imports = [ inputs.sneg.homeManagerModules.default ];

  mcp-servers.programs.blender.enable = true;
}
```

That goes through home-manager's `programs.mcp.servers`, so any client with
`enableMcpIntegration` picks it up. Through `sneg.lib.mkConfig` instead:

```nix
programs.mcp.configFile = inputs.sneg.lib.mkConfig pkgs {
  programs.blender.enable = true;
};
```

Or skip the module set entirely and point a client at
`${pkgs.blender-mcp}/bin/blender-mcp`.

## Options

| Option | Environment variable | Default |
| --- | --- | --- |
| `host` | `BLENDER_MCP_HOST` | `localhost` |
| `port` | `BLENDER_MCP_PORT` | `9876` |

Both are the client half of one plain TCP connection, and both have to agree
with the add-on's own address in Blender's preferences — there is no discovery
and no fallback port. Leave them out and both sides use the upstream defaults,
which is the only configuration that is known to work.

Everything else mcp-servers-nix gives every server — `env`, `envFile`,
`passwordCommand`, `package` — works here too, and is worth reading: MCP clients
spawn a server with a *curated* environment, not the one you are sitting in, so
a variable set in your shell does not reach it. Whatever goes in the module's
`env` is what the server sees.

## Install the extension

The package ships it at `${pkgs.blender-mcp}/share/blender-mcp/addon/mcp`, named
after the `id` in its `blender_manifest.toml` — that is the one name that is not
free, because Blender identifies an extension as `bl_ext.<repo>.<id>` and
matches the directory against both. Upstream's checkout calls the directory
`blender_mcp_addon`; the package renames it on the way in.

Blender loads extensions from per-user repository directories, so the extension
goes next to your other per-user config, under a `<major.minor>` directory that
tracks the version:

```nix
{
  imports = [ inputs.sneg.homeManagerModules.default ];

  mcp-servers.programs.blender.enable = true;

  xdg.configFile."blender/${lib.versions.majorMinor pkgs.blender.version}/extensions/user_default/mcp".source =
    "${pkgs.blender-mcp}/share/blender-mcp/addon/mcp";
}
```

That is `~/.config/blender/5.2/extensions/user_default/mcp` on Linux, which is
where Blender looks; `xdg.configFile` is the option that lands there, where
`home.file` would put it in `~/blender` and Blender would never see it. A major
or minor bump moves the directory, which is why the version is computed rather
than typed. On macOS Blender reads
`~/Library/Application Support/Blender/<ver>/extensions/...` instead, so that
one line wants `home.file` with the macOS prefix.

`user_default` is Blender's built-in user repository. If a future version
renames it, the right path is whatever Blender prints:

```bash
blender --background --python-expr 'import bpy; print(bpy.utils.user_resource("EXTENSIONS", path="user_default", create=True))'
```

Then enable it once. From the GUI: **Preferences → Get Extensions → Installed →
MCP**. Headless, where the choice is written back to `userpref.blend` so it
survives into later GUI sessions:

```bash
blender --background --python-expr 'import bpy, addon_utils; addon_utils.enable("bl_ext.user_default.mcp", default_set=True, persistent=True); bpy.ops.wm.save_userpref()'
```

That has to match the directory name above — `bl_ext.user_default.mcp` is
`bl_ext.<repo>.<id>`, and an enable call for an extension Blender cannot find is
a no-op, not an error. Check what it thinks:

```bash
blender --background --python-expr 'import bpy; print([a.module for a in bpy.context.preferences.addons if "mcp" in a.module])'
```

## Online access

The extension opens a listening socket, and Blender will not do that without
online access — a deliberate policy that also gates extension downloads and
telemetry. It is off in a fresh profile, and the failure is only visible in
Blender's output:

```
Error: Online access must be enabled in the system preferences
  Use --online-mode to enable online access from the command line
```

From the GUI: **Preferences → System → Network → Online Access**. For a single
command-line session, `--online-mode`. To make it stick without opening the GUI,
same trick as the add-on:

```bash
blender --background --python-expr 'import bpy; bpy.context.preferences.system.use_online_access = True; bpy.ops.wm.save_userpref()'
```

The flag is a session override and wins over the preference, so `--online-mode`
is the more honest way to run a headless bridge: it fails loudly if the profile
ever stops having it. With the preference set, the plain
`blender --background --command blender_mcp` below works too.

## Start the bridge

In an interactive Blender, the extension starts itself about a second after
startup — **Auto Start** in its preferences, on by default. Leave it on. Without
it, use the **Start Server** button in the same preferences panel, and note that
the socket lives exactly as long as the Blender process: closing the window
takes the tools with it.

Headless, `--command` starts it and keeps it in the foreground:

```bash
blender --background --online-mode --command blender_mcp
# MCP server started on localhost:9876, press Ctrl+C to exit.
```

A background Blender with no file loaded still serves tools, but the scene is
the startup file, not your work — that is what the `*_for_cli` tools are for.
They do not need the extension or the bridge at all, and they never see unsaved
changes unless the running instance writes them out first.

## What the wrapper sets

| Variable | Points at |
| --- | --- |
| `BLENDER_PATH` | `blender` from nixpkgs: the `blender` argument this was built with |

That is the whole wrapper. It exists for the `*_for_cli` tools, which shell out
to `blender --background <file> --python-expr` and would otherwise need a
Blender on `PATH`; with it, those tools work in a client that passes a curated
environment and nothing else.

It is set with `--set-default`, so a `BLENDER_PATH` in the module's `env` wins —
including one pointing at a Blender you installed yourself, which is the only
way to move this off nixpkgs' single `blender`:

```nix
mcp-servers.programs.blender = {
  enable = true;
  env.BLENDER_PATH = "${myBlender}/bin/blender";
};
```

Blender is a string in that wrapper, not a build input: `nix build
.#blender-mcp` does not build it, and the twenty socket-backed tools never
execute it. The store scanner does record the path as a reference, so it is
rooted against collection and a closure copy drags it along — but a single path
copied on its own, into a store that does not have that exact path, leaves the
six `_for_cli` tools failing with `Blender executable not found at ...` while
the rest keep working. Set `env.BLENDER_PATH` on the far side, or install
Blender from the same channel.

A build-time check imports `blmcp` and asserts that `prompts.yml`, the API docs
and the manual made it into the wheel, so a pyproject change that stops packaging
the data files fails here rather than at the first search call.

## Security

The socket binds to loopback and takes no authentication, and
`execute_blender_code` runs arbitrary Python with full `bpy` access in the
Blender it reaches. Anything that can open that port can do all of that to your
scene, including every file it can read. Keep `host` at `localhost`, and if you
need the bridge on another machine, tunnel it rather than setting `host` to a
routable address.

## Bump it

```bash
nix-update --flake blender-mcp
nix build -L .#blender-mcp
```

Upstream tags track both halves, so the tag is the version: `nix-update` moves
`version`, `src.rev` and `src.hash` together, and the build then re-derives the
hash from the mismatch if the tag moved. Three things are still worth a look
across a bump: that `blender_version_min` in the manifest still matches the
`blender` argument (it is 5.1.0 now, and the directory rename this package does
only works because the manifest `id` stayed `mcp`); that `blender_manifest.toml`
has not gained a `[permissions]` entry that needs a word here; and that
`connection.py` still reads the same two environment variables the module sets.
