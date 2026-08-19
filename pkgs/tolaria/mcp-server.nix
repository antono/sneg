{
  pkgs,
  lib,
  src,
  version,
  nodeModules,
}:

# tolaria-mcp: stdio MCP server that exposes vault tools (search_notes,
# get_note, vault_context, ...) to AI agents. Bundles mcp-server/index.js
# and mcp-server/ws-bridge.js with esbuild into self-contained CJS so the
# only runtime requirement is `node`.
#
# Configure VAULT_PATH (or VAULT_PATHS) in the MCP client config:
#   {
#     "mcpServers": {
#       "tolaria": {
#         "command": "tolaria-mcp",
#         "env": { "VAULT_PATH": "/home/you/Vault" }
#       }
#     }
#   }

let
  pnpm = pkgs.pnpm_11 or pkgs.pnpm;
  pnpmConfigMerge = import ./merge-pnpm-config.nix { inherit pkgs; };
in
pkgs.stdenv.mkDerivation {
  pname = "tolaria-mcp";
  inherit src version;

  nativeBuildInputs = [
    pnpm
    pkgs.nodejs_24
    pkgs.sqlite
    pkgs.makeWrapper
  ];

  configurePhase = ''
    runHook preConfigure

    export HOME=$(mktemp -d)
    export COREPACK_ENABLE_DOWNLOAD_PROMPT=0

    pnpmStore=$(mktemp -d)
    ${pkgs.zstd}/bin/zstd -d --stdout "${nodeModules}/pnpm-store.tar.zst" \
      | tar -x -C "$pnpmStore"
    chmod -R u+w "$pnpmStore"

    # fetcherVersion 4 ships the pnpm v11 store index as an SQL dump instead of
    # the binary index.db (for reproducibility); reconstruct it before install.
    if [ -f "$pnpmStore/v11/index.db.sql" ]; then
      sqlite3 "$pnpmStore/v11/index.db" < "$pnpmStore/v11/index.db.sql"
      rm "$pnpmStore/v11/index.db.sql"
    fi

    # pnpm 11 strict install needs overrides + patched deps in
    # pnpm-workspace.yaml; mirror them from package.json#pnpm in-place.
    ${pnpmConfigMerge}

    pnpm config set store-dir "$pnpmStore"
    pnpm config set package-import-method clone-or-copy
    pnpm install --offline --frozen-lockfile --ignore-scripts

    runHook postConfigure
  '';

  buildPhase = ''
    runHook preBuild
    # Produces src-tauri/resources/mcp-server/{index.js,ws-bridge.js,package.json}
    pnpm run bundle-mcp
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall

    install -d $out/share/tolaria-mcp
    install -m644 src-tauri/resources/mcp-server/index.js      $out/share/tolaria-mcp/index.js
    install -m644 src-tauri/resources/mcp-server/ws-bridge.js  $out/share/tolaria-mcp/ws-bridge.js
    install -m644 src-tauri/resources/mcp-server/package.json  $out/share/tolaria-mcp/package.json

    # tolaria-mcp -> stdio MCP server (for Claude Desktop, Codex, Gemini, etc.)
    makeWrapper ${pkgs.nodejs_24}/bin/node $out/bin/tolaria-mcp \
      --add-flags "$out/share/tolaria-mcp/index.js"

    # tolaria-mcp-bridge -> WebSocket bridge used by the desktop app. Exposed
    # for advanced users who want to run the bridge standalone against a
    # vault path passed via VAULT_PATH.
    makeWrapper ${pkgs.nodejs_24}/bin/node $out/bin/tolaria-mcp-bridge \
      --add-flags "$out/share/tolaria-mcp/ws-bridge.js"

    runHook postInstall
  '';

  meta = {
    description = "Tolaria MCP server — vault tools for AI agents (stdio + WebSocket bridge)";
    homepage = "https://tolaria.app";
    license = lib.licenses.agpl3Plus;
    platforms = lib.platforms.unix;
    mainProgram = "tolaria-mcp";
  };
}
