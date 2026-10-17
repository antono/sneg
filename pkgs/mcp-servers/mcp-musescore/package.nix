{
  lib,
  stdenvNoCC,
  fetchFromGitHub,
  python3,
  makeWrapper,
}:

let
  # Upstream asks for fastmcp>=4,<5; nixpkgs has 3.4.7. Everything the server
  # imports from it — FastMCP, fastmcp.apps, ToolResult, ToolError — is already
  # in 3.x, and the check below runs upstream's suite against this env.
  pythonDeps = ps: [
    ps.fastmcp
    ps.websockets
  ];
  pythonEnv = python3.withPackages pythonDeps;
in
stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "mcp-musescore";
  version = "0-unstable-2026-10-07";

  src = fetchFromGitHub {
    owner = "ghchen99";
    repo = "mcp-musescore";
    rev = "cab6a74bb8c534bc5159c10ba8693d3267624d0e";
    hash = "sha256-c/LqgWymo6VYy1zYecZQHqOhtPY8CxxGQqkkwP/B0PE=";
  };

  nativeBuildInputs = [ makeWrapper ];

  # tests/ drives the server against a mock of the QML plugin's websocket, so
  # it needs no MuseScore.
  #
  # Two assertions read results through fastmcp 4's client, which renamed the
  # MCP fields to snake_case; on 3.x they still carry the protocol's own names.
  # The server never touches either, so the tests are pointed at the 3.x
  # spelling rather than dropped — they still check what they were written to.
  doCheck = true;
  preCheck = ''
    substituteInPlace tests/test_integration.py \
      --replace-fail 'page.mime_type' 'page.mimeType'
    substituteInPlace tests/test_server.py \
      --replace-fail 'tool.input_schema' 'tool.inputSchema'
  '';
  nativeCheckInputs = [ (python3.withPackages (ps: pythonDeps ps ++ [ ps.pytest ])) ];
  checkPhase = ''
    runHook preCheck
    pytest -p no:cacheprovider
    runHook postCheck
  '';

  # Upstream ships no packaging metadata (no pyproject.toml, no setup.py) — just
  # a top-level server.py importing from ./src. Install the sources verbatim and
  # wrap the interpreter; Python puts the script's own directory on sys.path, so
  # the `src` package resolves at runtime.
  installPhase = ''
    runHook preInstall

    mkdir -p $out/share/mcp-musescore
    cp -r server.py src $out/share/mcp-musescore/

    # The other half is a QML plugin the user must copy into MuseScore's own
    # plugins directory; ship it here so there is something to point at.
    install -Dm644 musescore-mcp-websocket.qml \
      $out/share/mcp-musescore/musescore-mcp-websocket.qml

    makeWrapper ${lib.getExe pythonEnv} $out/bin/mcp-musescore \
      --add-flags "$out/share/mcp-musescore/server.py"

    runHook postInstall
  '';

  meta = {
    description = "MCP server that drives MuseScore: compose, add lyrics, navigate scores";
    homepage = "https://github.com/ghchen99/mcp-musescore";
    license = lib.licenses.mit;
    maintainers = with lib.maintainers; [ antono ];
    mainProgram = "mcp-musescore";
    platforms = lib.platforms.all;
  };
})
