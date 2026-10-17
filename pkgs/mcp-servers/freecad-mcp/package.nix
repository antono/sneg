{
  lib,
  fetchFromGitHub,
  python3Packages,
}:

python3Packages.buildPythonApplication rec {
  pname = "freecad-mcp";
  version = "0.1.27";

  src = fetchFromGitHub {
    owner = "neka-nat";
    repo = "freecad-mcp";
    tag = "v${version}";
    hash = "sha256-BGxa7+wa9QwiR1R2fs//ksMVfhzqklr0sybPwHYgIYQ=";
  };

  pyproject = true;

  build-system = with python3Packages; [ hatchling ];

  dependencies = with python3Packages; [
    mcp
    validators
  ];

  # The addon half is tested against stubs of the FreeCAD modules, so the suite
  # runs without FreeCAD itself.
  nativeCheckInputs = with python3Packages; [ pytestCheckHook ];

  # Spawns the server through the SDK's stdio_client, which passes the child
  # only a whitelist of env vars. That drops the PYTHONPATH the check phase
  # runs on, so the child cannot import anyio and the session closes.
  disabledTests = [ "test_stdio_client_receives_error_flags_and_original_content" ];

  # The server talks to FreeCAD over XML-RPC; the other half of this pair is an
  # addon the user installs into FreeCAD itself (see upstream's README).
  meta = {
    description = "MCP server for FreeCAD: create and edit CAD documents from an agent";
    homepage = "https://github.com/neka-nat/freecad-mcp";
    license = lib.licenses.mit;
    maintainers = with lib.maintainers; [ antono ];
    mainProgram = "freecad-mcp";
  };
}
