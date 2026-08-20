{
  lib,
  fetchFromGitHub,
  python3Packages,
}:

python3Packages.buildPythonApplication {
  pname = "greenhouse-mcp";
  version = "0.1.0-unstable-2026-07-02";

  # UladzislauRedzko's fork of alexmeckes/greenhouse-mcp — it carries the fix
  # for list_applications' return annotation, which FastMCP validates and which
  # makes the tool fail outright upstream.
  src = fetchFromGitHub {
    owner = "UladzislauRedzko";
    repo = "greenhouse-mcp";
    rev = "4f9ee1cf08dee3cfed5f0bf5b341a234102cee50";
    hash = "sha256-uWXA+y6YKsfegvt2TPBSeWR4k+5h18tnrGdiMuZSGGE=";
  };

  pyproject = true;

  build-system = with python3Packages; [ setuptools ];

  dependencies = with python3Packages; [
    fastmcp
    httpx
    pydantic
    python-dotenv
  ];

  # Upstream's pyproject packages the tree as a top-level module literally named
  # `src`, and its console script is `src.greenhouse_mcp:main`.
  pythonImportsCheck = [ "src.greenhouse_mcp" ];

  meta = {
    description = "MCP server for the Greenhouse Harvest API";
    homepage = "https://github.com/UladzislauRedzko/greenhouse-mcp";
    license = lib.licenses.mit;
    maintainers = with lib.maintainers; [ antono ];
    mainProgram = "greenhouse-mcp";
  };
}
