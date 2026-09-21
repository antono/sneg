# Konnect — the Rust rewrite of KiCAD-MCP-Server, by the same author. One
# static binary that speaks MCP over stdio, driving KiCAD 10 through its
# official IPC API rather than the SWIG `pcbnew` bindings. So unlike
# ../kicad-mcp there is no Python side to assemble, and the KiCAD coupling is
# narrower: `kicad-cli` for exports and the stock symbol/footprint libraries
# for schematic work, both supplied by the wrapper below.
#
# The two are packaged side by side on purpose. This one is AGPL-3.0 and
# targets KiCAD 10 only; the MIT Python/TypeScript server stays maintained and
# still works against KiCAD 8 and 9.
{
  lib,
  cmake,
  fetchFromGitHub,
  kicad,
  makeWrapper,
  pkg-config,
  protobuf,
  rustPlatform,
  versionCheckHook,
}:

let
  # The commit `tag` below resolves to. Upstream's build script reads the
  # commit out of .git, which fetchFromGitHub does not produce, so without
  # this the `get_installation_info` tool reports a null commit and no client
  # can tell which build is answering it. Bump it with `version`.
  rev = "fa62e1ccb9eba359519bf8e3eab53a6cffeee33c";

  inherit (kicad.passthru.libraries) footprints symbols;
in
rustPlatform.buildRustPackage (finalAttrs: {
  pname = "konnect";
  version = "0.12.1";

  src = fetchFromGitHub {
    owner = "mixelpixx";
    repo = "Konnect";
    tag = "v${finalAttrs.version}";
    hash = "sha256-06cMovUbim50kYZRMsIXXXtrlMXWkOQBEGbNC16wsTY=";
  };

  cargoHash = "sha256-D/rSitPerFDPmYE512Pesuj83KWyDACoHVrhNQ24x9E=";

  nativeBuildInputs = [
    cmake
    makeWrapper
    pkg-config
    protobuf
  ];

  # cmake is here for the `nng` crate, which builds the NNG C library itself.
  # Without this the cmake setup hook would try to configure the workspace
  # root as a cmake project before cargo ever runs.
  dontUseCmakeConfigure = true;

  env = {
    KONNECT_BUILD_COMMIT = rev;

    # konnect-ipc/build.rs can find these on PATH, but naming them also makes
    # protobuf's well-known types resolve against the store path — upstream's
    # own flake does the same.
    PROTOC = lib.getExe protobuf;
    PROTOC_INCLUDE = "${protobuf}/include";
  };

  # The workspace also holds an xtask and a Tauri schematic viewer; neither is
  # the server, and the viewer is excluded from the workspace anyway.
  cargoBuildFlags = [
    "-p"
    "konnect"
    "--bin"
    "konnect"
  ];

  cargoTestFlags = [
    "-p"
    "konnect"
    "--lib"
    "--tests"
  ];

  # The protocol tests spawn the server they just built, and it wants a state
  # directory it can write to — which $HOME in the sandbox is not.
  preCheck = ''
    export KONNECT_STATE_DIR="$TMPDIR/konnect-state"
    mkdir -p "$KONNECT_STATE_DIR"
  '';

  # `plugin/` is the KiCAD-side half: a Python action plugin that adds a
  # Konnect button to the PCB editor and, optionally, the native Specctra
  # bridge. It cannot be loaded from the store — it writes settings.json
  # beside itself — so it is installed as a *source* directory to copy into
  # KiCAD's own 3rdparty/plugins, with the one path that must not be relative
  # rewritten to this binary. See ./README.md.
  postInstall = ''
    mkdir -p $out/share/konnect
    cp -R plugin $out/share/konnect/plugin

    substituteInPlace $out/share/konnect/plugin/__init__.py \
      --replace-fail \
        'BINARY_PATH = os.path.join(PLUGIN_DIR, "bin", BINARY_NAME)' \
        'BINARY_PATH = "${placeholder "out"}/bin/konnect"'

    wrapProgram $out/bin/konnect \
      --set-default KICAD_CLI ${lib.getExe' kicad "kicad-cli"} \
      --set-default KICAD_CLI_PATH ${lib.getExe' kicad "kicad-cli"} \
      --set-default KICAD10_SYMBOL_DIR ${symbols}/share/kicad/symbols \
      --set-default KICAD10_FOOTPRINT_DIR ${footprints}/share/kicad/footprints \
      --suffix PATH : ${lib.makeBinPath [ kicad ]}
  '';

  # `konnect --version` prints the workspace version, so this catches a stale
  # `version` against a bumped tag.
  versionCheckProgramArg = "--version";
  doInstallCheck = true;
  nativeInstallCheckInputs = [ versionCheckHook ];

  meta = {
    description = "MCP server for KiCAD 10: PCB, schematic, routing and manufacturing tools over its IPC API";
    homepage = "https://github.com/mixelpixx/Konnect";
    license = lib.licenses.agpl3Only;
    maintainers = with lib.maintainers; [ antono ];
    mainProgram = "konnect";
    platforms = lib.platforms.unix;
  };
})
