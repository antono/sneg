{
  lib,
  stdenvNoCC,
  fetchFromGitHub,
  jq,
  hyperframes,
}:

# The published skills, laid out the way upstream's own plugin archive is
# (scripts/package-agent-plugin.mjs): manifests, assets, LICENSE and skills/.
#
# Shipping them as a plugin rather than as loose skill directories is what
# makes them behave under Nix. The router checks for a plugin manifest two
# levels above its SKILL.md; finding one, it treats the install as read-only —
# no `hyperframes skills update`, no `npx skills add` — and routes every CLI
# call through skills/hyperframes/scripts/plugin-cli.mjs. That launcher would
# fetch `hyperframes@<version>` through npx; patched, it runs ours.
#
# pname is `hyperframes`, not `hyperframes-plugin`: home-manager's codex module
# names a plugin derivation after its pname, which must match the manifest.
stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "hyperframes";
  inherit (hyperframes) version;

  src = fetchFromGitHub {
    owner = "heygen-com";
    repo = "hyperframes";
    tag = "v${finalAttrs.version}";
    hash = "sha256-IHUjGz5WMbTDrSuxjLc/cAE8D0VFlUGfnpNM9uUX2IQ=";
  };

  nativeBuildInputs = [ jq ];

  dontConfigure = true;
  dontBuild = true;

  # Every place the skills reach for the CLI through npx. Left alone, each one
  # downloads hyperframes from npm — pinned or latest — instead of running ours.
  # --replace-fail throughout, so a bump that moves any of them fails loudly.
  postPatch =
    let
      cli = lib.getExe hyperframes;
    in
    ''
      # The launcher every skill command goes through in plugin mode.
      substituteInPlace skills/hyperframes/scripts/plugin-cli.mjs --replace-fail \
        'const cliArgs = ["--yes", `hyperframes@''${version}`, ...args];' \
        'return { command: "${cli}", args, env: childEnv };
        const cliArgs = ["--yes", `hyperframes@''${version}`, ...args];'

      # media-use's two npx resolvers: one behind its sync helpers (transcribe,
      # and the plugin-mode branch of resolve.mjs), one behind the audio
      # engine's spawnP (tts, transcribeWav). Both see `[--yes] hyperframes[@v]
      # <command> ...`.
      substituteInPlace skills/media-use/scripts/lib/npx-sync.mjs --replace-fail \
        '  pathExists = existsSync,
      ) {' \
        '  pathExists = existsSync,
      ) {
        const rest = argv[0] === "--yes" ? argv.slice(1) : argv;
        if (/^hyperframes(@|$)/.test(String(rest[0]))) {
          return { cmd: "${cli}", args: rest.slice(1).map(String), opts: { stdio: "ignore", ...opts } };
        }'
      substituteInPlace skills/media-use/audio/scripts/lib/tts.mjs --replace-fail \
        '  if (cmd !== "npx" || platform !== "win32") {' \
        '  if (cmd === "npx" && /^hyperframes(@|$)/.test(String(args[0]))) {
          return { cmd: "${cli}", args: args.slice(1), opts: { stdio: "ignore", ...opts } };
        }
        if (cmd !== "npx" || platform !== "win32") {'

      substituteInPlace skills/pr-to-video/scripts/preflight.mjs --replace-fail \
        'spawn("npx", ["hyperframes", "--help"], {' \
        'spawn("${cli}", ["--help"], {'
    '';

  installPhase = ''
    runHook preInstall

    for manifest in plugin.json gemini-extension.json .claude-plugin/plugin.json \
                    .cursor-plugin/plugin.json .codex-plugin/plugin.json; do
      version=$(jq -r .version "$manifest")
      if [ "$version" != "${finalAttrs.version}" ]; then
        echo "$manifest is $version, expected ${finalAttrs.version}" >&2
        exit 1
      fi
      install -Dm644 "$manifest" "$out/$manifest"
    done

    mkdir -p $out
    cp -r assets LICENSE skills skills-manifest.json $out/

    runHook postInstall
  '';

  # The skill directory names, read from upstream's manifest in the fetched
  # source rather than from $out, so listing them only needs the fetch, not a
  # build of the CLI the launcher points at. homeManagerModules.hyperframes
  # links each one into ~/.agents/skills.
  passthru.skillNames = lib.attrNames (lib.importJSON "${finalAttrs.src}/skills-manifest.json")
    .skills;

  meta = removeAttrs hyperframes.meta [ "mainProgram" ] // {
    description = "HyperFrames agent skills, packaged as a plugin wired to the Nix-built CLI";
    platforms = lib.platforms.all;
  };
})
