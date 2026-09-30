# Blender MCP server — the one from the Blender Lab
# (https://projects.blender.org/lab/blender_mcp), which is not the unrelated
# project of the same name on PyPI. The Lab runs Forgejo, so `fetchFromGitHub`
# does not apply and `src` is a `fetchgit` pin; `nix-update` drives that as well
# as it drives a GitHub one.
#
# Two halves, like freecad-mcp and mcp-musescore:
#
#   * `mcp/` is the Python package below. A plain stdio MCP server that the
#     client launches and that does no Blender work itself — every tool call is
#     relayed to the add-on. It carries Blender's Python API reference and user
#     manual (~30 MB of RST) and serves them as MCP resources, which is why its
#     closure is larger than the tool count suggests.
#
#   * `addon/blender_mcp_addon/` is a Blender *extension*: the half that runs
#     Python inside Blender and answers over a TCP socket on localhost:9876.
#     Blender imports extensions only from its own per-version config
#     directory, so this one cannot be made importable from a store path. It is
#     shipped as source to symlink from — README.md beside this file has the
#     steps, and they are the whole reason this server is not self-contained.
#
# `blender` is a package argument for the same reason `kicad` is one in
# kicad-mcp: a second family of tools runs code in a *headless* Blender
# (`*_for_cli`, one per summary tool plus `execute_blender_code_for_cli`) and
# takes the binary from `BLENDER_PATH`, defaulting to `blender` on PATH. An MCP
# client starts this process with an environment it does not control, so the
# path belongs in the wrapper rather than in whatever the user has exported.
{
  lib,
  blender,
  fetchgit,
  makeWrapper,
  python3Packages,
}:

python3Packages.buildPythonApplication rec {
  pname = "blender-mcp";
  version = "1.0.3";

  src = fetchgit {
    url = "https://projects.blender.org/lab/blender_mcp";
    rev = "2cea8d566dde07fbac28a61d698909d69724e853"; # v1.0.3
    hash = "sha256-pYeByO4Oi5eyynsJhGVd1vBWXHvhGn+Y5LGit6Kazlw=";
  };

  # The Python package is the `mcp/` subdirectory of the repository; the add-on
  # beside it is installed by postInstall below.
  sourceRoot = "${src.name}/mcp";

  pyproject = true;

  build-system = with python3Packages; [ setuptools ];

  # `mcp[cli]` upstream: the `cli` extra is `typer` and `python-dotenv`, which
  # only the separate `mcp` command-line runner imports. This server's own entry
  # point never reaches either, so neither is carried here.
  dependencies = with python3Packages; [
    docutils
    mcp
    pyyaml
  ];

  nativeBuildInputs = [ makeWrapper ];

  # `postInstall` here is a *hook*, not a phase body: nixpkgs' default
  # installPhase for a `pyproject` package is pypaInstallPhase, which ends by
  # running the postInstall hooks — so this runs after the wheel is installed
  # and `$out/bin/blender-mcp` exists. Do not add `runHook postInstall` here:
  # a hook that runs the hook list that contains it recurses until the builder
  # dies on a stack overflow, which nix reports as `signal 11`.
  postInstall = ''
    # The other half, renamed from `blender_mcp_addon` to `mcp`: that is the
    # `id` in its blender_manifest.toml, and Blender requires the directory
    # inside a repository to carry the name the extension registers as, which
    # is why the module it is imported as is `bl_ext.<repo>.mcp`. Nothing in
    # the add-on refers to its own directory by name — its imports are all
    # relative — so the rename is safe.
    mkdir -p $out/share/blender-mcp/addon
    cp -r ${src}/addon/blender_mcp_addon $out/share/blender-mcp/addon/mcp

    # `--set-default`, so a `BLENDER_PATH` from the module's `env` wins.
    wrapProgram $out/bin/blender-mcp \
      --set-default BLENDER_PATH ${lib.getExe blender}
  '';

  # Importing `blmcp` proves the three dependencies above are the ones upstream
  # actually imports. The assertion worth adding is on the package data: the
  # tools are useless without the bundled API reference, the manual and
  # `prompts.yml` — `main()` reads that last one unconditionally at startup —
  # and upstream declares it through setuptools globs (`data/api/**/*.rst`) that
  # a setuptools bump could quietly stop matching.
  pythonImportsCheck = [ "blmcp" ];

  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck

    ${python3Packages.python.interpreter} -c "import blmcp, pathlib; \
      data = pathlib.Path(blmcp.__file__).parent / 'data'; \
      assert (data / 'prompts.yml').is_file(), 'prompts.yml not packaged'; \
      assert any((data / 'api').rglob('*.rst')), 'api/*.rst not packaged'; \
      assert any((data / 'manual').rglob('*.rst')), 'manual/*.rst not packaged'"

    runHook postInstallCheck
  '';

  meta = {
    description = "MCP server for Blender, from the Blender Lab (needs its add-on inside Blender)";
    homepage = "https://projects.blender.org/lab/blender_mcp";
    license = lib.licenses.gpl3Plus;
    maintainers = with lib.maintainers; [ antono ];
    mainProgram = "blender-mcp";
    # Not `platforms.all`: the headless tools above are bound to a Blender,
    # which is only packaged where its own dependency closure builds.
    platforms = blender.meta.platforms;
  };
}
