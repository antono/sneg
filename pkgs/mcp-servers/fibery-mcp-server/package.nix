{
  lib,
  fetchFromGitHub,
  python3Packages,
}:

python3Packages.buildPythonApplication rec {
  pname = "fibery-mcp-server";
  version = "0.1.8";

  # Upstream tags no releases; this is the commit that bears the 0.1.8 bump.
  src = fetchFromGitHub {
    owner = "Fibery-inc";
    repo = "fibery-mcp-server";
    rev = "8fef67be956808d183ce5f5f6e7c388794d08a74";
    hash = "sha256-cnYW5RMOMvSS0829WmHhW55PxFq+3khz53kWU8qRsaU=";
  };

  pyproject = true;

  build-system = with python3Packages; [ hatchling ];

  dependencies = with python3Packages; [
    click
    httpx
    mcp
    pydantic
    python-dotenv
  ];

  pythonImportsCheck = [ "fibery_mcp_server" ];

  meta = {
    description = "MCP server for Fibery: query and mutate entities over the Fibery API";
    homepage = "https://github.com/Fibery-inc/fibery-mcp-server";
    license = lib.licenses.mit;
    maintainers = with lib.maintainers; [ antono ];
    mainProgram = "fibery-mcp-server";
  };
}
