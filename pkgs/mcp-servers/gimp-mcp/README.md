# gimp-mcp

[GIMP MCP](https://github.com/gimp-mcp/gimp-mcp) over stdio: 80 tools that drive
a running GIMP 3.2 — open and export images, layers, selections, adjustments,
transforms, text, filters, and `get_state_snapshot`, which hands the agent a
PNG preview so it can check each step.

The server does no image work itself. Every call goes over TCP
(`localhost:9877`) to a Python plug-in running inside GIMP, so that plug-in has
to be loaded and started. Skip it and every tool call comes back with a
connection error.

## Enable it

With Home Manager, this one block is the whole setup: the client config, and a
GIMP that loads the plug-in and starts it on launch, on the same port.

```nix
{
  imports = [ inputs.sneg.homeManagerModules.default ];

  mcp-servers.programs.gimp = {
    enable = true;
    withGimp = true;   # gimp3-with-plugins carrying the plug-in, in home.packages
    autostart = true;  # start the plug-in's server when GIMP launches
    port = 9877;       # plug-in and server both; this is the default
    timeout = 900;     # GIMP_MCP_TIMEOUT, seconds per command
  };
}
```

`withGimp` installs GIMP itself, so drop any other `gimp`/`gimp3` from your
packages to avoid two of them on PATH. For more plug-ins, set `gimpPackage` to
`pkgs.gimp3-with-plugins.override { plugins = [ … ]; }`; gimp-mcp is appended
to that list.

`autostart` and `port` are baked into the package as the plug-in's
*defaults*. What GIMP's **Tools > MCP > MCP Server Settings…** dialog saves to
`~/.config/GIMP/3.2/gimp-mcp.json` still wins, so the dialog keeps working; delete
that file to go back to what Nix says.

Through `sneg.lib.mkConfig` the same options apply to the server and the
package, but `withGimp` does nothing — load the plug-in as below.

## Load the plug-in yourself

Only needed without `withGimp`. Pick one.

**Declaratively**, with nixpkgs' plug-in wrapper (needs `sneg.overlays.default`
or `sneg.overlays.mcp-servers`):

```nix
home.packages = [
  (pkgs.gimp3-with-plugins.override {
    plugins = [ (pkgs.gimp-mcp.override { autostart = true; }) ];
  })
];
```

The plug-in is then part of GIMP's own plug-in folder and is updated with the
package — nothing to redo after an upgrade.

**Into your GIMP config**, for a GIMP you already run. Start GIMP once so it
creates `~/.config/GIMP/3.2`, close it, then:

```bash
nix run github:antono/sneg#gimp-mcp -- install-plugin
```

This copy does not follow package updates: rerun it after updating, and after
every GIMP minor upgrade (GIMP moves to a new config folder each time).
`check_server` reports a version mismatch between the two halves.

Either way, the plug-in runs on nixpkgs' python3 with PyGObject rather than on
upstream's `#!/usr/bin/env python3`, which on NixOS has no `gi` and makes GIMP
drop the plug-in without a word.

## Start it

With `autostart`, nothing to do. Otherwise, in GIMP: **Tools > MCP > Start MCP
Server** (or tick **Start MCP server when GIMP launches** in **Tools > MCP > MCP
Server Settings…**).

The plug-in binds to localhost and takes no authentication: anything that can
reach the port can run Python inside GIMP.
