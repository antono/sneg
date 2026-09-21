# KiCAD MCP server — PCB and schematic tools over stdio.
#
# Two processes, not one: `dist/index.js` is the MCP server proper, and it
# spawns `python/kicad_interface.py` as a long-lived child that does the actual
# work through KiCAD's own Python API. So this derivation has to satisfy both
# halves, and most of what follows is about the second one.
#
#   * The Python side needs `pcbnew`, which is a compiled extension module
#     built as part of KiCAD itself and installed into `kicad.base`, not into
#     nixpkgs' python package set. It is importable only from the *same*
#     interpreter KiCAD was built against — `pkgs.python3` — which is what
#     `pythonEnv` below is, with upstream's pure-Python requirements added.
#     The wrapper points `KICAD_PYTHON` at it and puts KiCAD's site-packages on
#     PYTHONPATH; `src/server.ts` honours both.
#
#   * KiCAD's symbol, footprint, 3D-model and template libraries are found
#     through `KICAD<major>_*_DIR`, which on nixpkgs are set by the `kicad`
#     wrapper — and nothing here runs under that wrapper. Unset, the library
#     lookups fall back to FHS paths that do not exist, so the wrapper sets
#     them too, from the same library derivations `kicad` itself uses.
#
# `kicad` is a package argument: override it to follow a different KiCAD, and
# the interpreter, the CLI and the library paths all move together.
{
  lib,
  buildNpmPackage,
  fetchFromGitHub,
  kicad,
  makeWrapper,
  nodejs,
  python3,
}:

let
  # Which KICAD<n>_*_DIR names this KiCAD answers to. Upstream's Python side
  # probes 8, 9 and 10; nixpkgs' wrapper sets whichever matches the version it
  # packages, and so does this.
  kicadMajor = lib.versions.major kicad.version;

  inherit (kicad.passthru.libraries) footprints packages3d symbols;

  # Only what `python/` actually imports. Upstream's requirements.txt is wider
  # than its imports — colorlog and pydantic are declared but never imported,
  # and are left out rather than carried.
  pythonEnv = python3.withPackages (ps: [
    ps.cairosvg # SVG -> PNG, second choice after pymupdf
    ps.kicad-python # `kipy`, the IPC backend
    ps.pillow
    ps.pymupdf # `fitz`, the preferred rasterizer
    ps.python-dotenv
    ps.requests
    ps.sexpdata
    (ps.callPackage ./kicad-skip.nix { })
  ]);
in
buildNpmPackage (finalAttrs: {
  pname = "kicad-mcp";
  version = "2.7.0";

  src = fetchFromGitHub {
    owner = "mixelpixx";
    repo = "KiCAD-MCP-Server";
    tag = "v${finalAttrs.version}";
    hash = "sha256-faCTkstk6LEm9qctoRObtlATUOW8JNQ645LepAFsgMI=";
  };

  npmDepsHash = "sha256-LBUZmYzYnaVyuU0/fwy6t3yoIIb8Qbve/mF/Fv6Y6qg=";

  nativeBuildInputs = [ makeWrapper ];

  # `prepare` is `npm run build`, so npm would run tsc during `npm ci` and
  # npmBuildHook would then run it again.
  npmFlags = [ "--ignore-scripts" ];

  # Upstream declares no `bin`, and `files` is absent too, so the default
  # install (an `npm pack` of what package.json lists) would produce neither an
  # executable nor the `python/` tree. Install the package root instead, the
  # way it is meant to run: `dist/index.js` resolves `../python` and
  # `../config` relative to itself, and its imports through a node_modules
  # beside it.
  installPhase = ''
    runHook preInstall

    npm prune --omit=dev --offline --no-audit --no-fund

    mkdir -p $out/lib/kicad-mcp
    cp -R package.json config dist node_modules python $out/lib/kicad-mcp/

    makeWrapper ${lib.getExe nodejs} $out/bin/kicad-mcp \
      --add-flags $out/lib/kicad-mcp/dist/index.js \
      --set-default KICAD_PYTHON ${pythonEnv}/bin/python3 \
      --set-default KICAD_CLI ${lib.getExe' kicad "kicad-cli"} \
      --prefix PYTHONPATH : ${kicad.base}/${python3.sitePackages} \
      --suffix PATH : ${lib.makeBinPath [ kicad ]} \
      --set-default KICAD${kicadMajor}_SYMBOL_DIR ${symbols}/share/kicad/symbols \
      --set-default KICAD${kicadMajor}_FOOTPRINT_DIR ${footprints}/share/kicad/footprints \
      --set-default KICAD${kicadMajor}_3DMODEL_DIR ${packages3d}/share/kicad/3dmodels \
      --set-default KICAD${kicadMajor}_TEMPLATE_DIR ${kicad.template_dir}

    runHook postInstall
  '';

  # The one assertion worth making at build time: that the interpreter the
  # wrapper hands to the server can import KiCAD's own bindings alongside
  # upstream's Python dependencies. `pcbnew` comes from PYTHONPATH and `skip`
  # from pythonEnv, so this fails if either path stops resolving — which is
  # exactly what a KiCAD bump or a python3 bump would break.
  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck

    PYTHONPATH=${kicad.base}/${python3.sitePackages} \
      ${pythonEnv}/bin/python3 -c 'import pcbnew, skip, sexpdata, kipy'

    runHook postInstallCheck
  '';

  meta = {
    description = "MCP server for KiCAD: PCB layout and schematic editing from an agent";
    homepage = "https://github.com/mixelpixx/KiCAD-MCP-Server";
    license = lib.licenses.mit;
    maintainers = with lib.maintainers; [ antono ];
    mainProgram = "kicad-mcp";
    # `kicad.meta.platforms` is `platforms.all`, so inheriting it would say
    # nothing. The real bound is the node/python pair this wraps.
    platforms = lib.platforms.unix;
  };
})
