{
  lib,
  fetchFromGitHub,
  python3,
}:

let
  # nixpkgs moved `mcp` to 2.x and marked fastmcp 3.x broken against it; until
  # fastmcp 4 lands there, keep this server's closure on the 1.x SDK. Older
  # nixpkgs without `mcp_1` still has 1.x as plain `mcp`.
  python = python3.override {
    self = python;
    packageOverrides = final: prev: lib.optionalAttrs (prev ? mcp_1) { mcp = final.mcp_1; };
  };
  python3Packages = python.pkgs;
in
python3Packages.buildPythonApplication {
  pname = "greenhouse-mcp";
  version = "0.1.0-unstable-2026-08-25";

  # UladzislauRedzko's fork of alexmeckes/greenhouse-mcp — it carries the fix
  # for list_applications' return annotation, which FastMCP validates and which
  # makes the tool fail outright upstream, plus the move to Harvest API v3.
  src = fetchFromGitHub {
    owner = "UladzislauRedzko";
    repo = "greenhouse-mcp";
    rev = "e7cd2ae2dd195388ffe70bd1b67e6321caf4fbcb";
    hash = "sha256-Ye6y9mZVnlkmrsTcxExgIzZC+Hy9mqffXiglNuFOH1c=";
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
