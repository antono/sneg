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

```nix
{
  imports = [ inputs.sneg.homeManagerModules.default ];

  mcp-servers.programs.gimp.enable = true;
}
```

Or through `sneg.lib.mkConfig`:

```nix
programs.mcp.configFile = inputs.sneg.lib.mkConfig pkgs {
  programs.gimp = {
    enable = true;
    port = 9877;     # GIMP_MCP_PORT, must match the plug-in's setting
    timeout = 900;   # GIMP_MCP_TIMEOUT, seconds per command
  };
};
```

## Load the plug-in into GIMP

Pick one.

**Declaratively**, with nixpkgs' plug-in wrapper (needs `sneg.overlays.default`
or `sneg.overlays.mcp-servers`):

```nix
home.packages = [
  (pkgs.gimp3-with-plugins.override { plugins = [ pkgs.gimp-mcp ]; })
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

In GIMP, **Tools > MCP > Start MCP Server**. To skip that on every launch, tick
**Start MCP server when GIMP launches** in **Tools > MCP > MCP Server Settings…**
and restart GIMP. The same dialog sets the port.

The plug-in binds to localhost and takes no authentication: anything that can
reach the port can run Python inside GIMP.
