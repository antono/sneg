# GIMP MCP server (https://github.com/gimp-mcp/gimp-mcp), published on PyPI as
# `gimp-mcp-plugin`.
#
# Two halves, like blender-mcp and freecad-mcp:
#
#   * `gimp_mcp_server.py` is a plain stdio MCP server that does no image work
#     itself — every tool call is relayed over TCP (localhost:9877) to the plug-in.
#
#   * `gimp-mcp-plugin.py` is a GIMP 3 Python plug-in that answers on that port
#     once it is started from Tools > MCP inside GIMP.
#
# Upstream's plug-in starts with `#!/usr/bin/env python3` and imports `gi`. On
# NixOS that finds whatever python3 is on PATH, which has no PyGObject, so GIMP
# silently drops the plug-in. Both copies of it shipped here — the one that
# `gimp-mcp-server install-plugin` copies into ~/.config/GIMP/3.x and the one
# under lib/gimp for `gimp3-with-plugins` — get the same interpreter nixpkgs'
# GIMP uses for its own Python plug-ins: python3 with pygobject3. The typelibs
# come from GIMP itself, whose wrapper exports GI_TYPELIB_PATH to its plug-ins.
{
  lib,
  fetchFromGitHub,
  gimp3,
  python3,
}:

let
  # Upstream pins mcp<2 (the server is written against FastMCP), and nixpkgs
  # now ships mcp 2.x; keep its closure on the 1.x SDK. Older nixpkgs without
  # `mcp_1` still has 1.x as plain `mcp`.
  python = python3.override {
    self = python;
    packageOverrides = final: prev: lib.optionalAttrs (prev ? mcp_1) { mcp = final.mcp_1; };
  };
  python3Packages = python.pkgs;

  # What the plug-in runs on inside GIMP; see above.
  pluginPython = python3.withPackages (ps: [ ps.pygobject3 ]);
in
python3Packages.buildPythonApplication rec {
  pname = "gimp-mcp";
  version = "0.5.0";

  src = fetchFromGitHub {
    owner = "gimp-mcp";
    repo = "gimp-mcp";
    tag = "v${version}";
    hash = "sha256-Ekg9fUxhErKluKWVyQO5yogmFvlLjlQVg0n7FuAAPSw=";
  };

  pyproject = true;

  build-system = with python3Packages; [ setuptools ];

  dependencies = with python3Packages; [ mcp ];

  # The version-mismatch warnings tell the user to run `uvx gimp-mcp-plugin@…`,
  # which would fetch a second, unpinned copy from PyPI; point them at the
  # command this package installs instead.
  postPatch = ''
    substituteInPlace gimp-mcp-plugin.py \
      --replace-fail '#!/usr/bin/env python3' '#!${pluginPython.interpreter}'

    substituteInPlace gimp_mcp_server.py \
      --replace-fail 'f"uvx gimp-mcp-plugin@{SERVER_VERSION} install-plugin"' \
                     '"gimp-mcp-server install-plugin"' \
      --replace-fail '"use gimp-mcp-plugin@latest in your MCP client config"' \
                     '"update the gimp-mcp package"'
  '';

  # A hook, not a phase body — see blender-mcp for why there is no runHook here.
  postInstall = ''
    install -Dm755 gimp-mcp-plugin.py \
      $out/${gimp3.targetPluginDir}/gimp-mcp-plugin/gimp-mcp-plugin.py
  '';

  # The test suite is a set of standalone scripts, most of them driving a live
  # GIMP; the install check below covers what matters for packaging.
  pythonImportsCheck = [ "gimp_mcp_server" ];

  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck

    # install-plugin must find the plug-in next to the server module and copy
    # it with the patched shebang.
    export HOME=$(mktemp -d)
    $out/bin/gimp-mcp-server install-plugin --gimp-dir "$HOME/GIMP/3.2"
    installed="$HOME/GIMP/3.2/plug-ins/gimp-mcp-plugin/gimp-mcp-plugin.py"
    test -x "$installed"
    head -1 "$installed" | grep -qF '${pluginPython.interpreter}'
    ${pluginPython.interpreter} -c 'import gi'

    # The MCP prompts read these at runtime. `gimp_mcp_docs` has no __init__.py,
    # so it is a namespace package and only importlib.resources can locate it.
    ${python3Packages.python.interpreter} -c "from importlib import resources; \
      assert resources.files('gimp_mcp_docs').joinpath('best_practices.md').is_file(), 'docs not packaged'"

    runHook postInstallCheck
  '';

  meta = {
    description = "MCP server for GIMP 3.2 (needs its plug-in running inside GIMP)";
    homepage = "https://github.com/gimp-mcp/gimp-mcp";
    changelog = "https://github.com/gimp-mcp/gimp-mcp/blob/v${version}/CHANGELOG.md";
    license = lib.licenses.gpl3Plus;
    maintainers = with lib.maintainers; [ antono ];
    mainProgram = "gimp-mcp-server";
  };
}
