{
  lib,
  stdenv,
  buildNpmPackage,
  fetchurl,
  nodejs_22,
  jq,
  makeWrapper,
  ffmpeg-headless,
  playwright-driver,
  callPackage,
}:

# Built from the npm tarball rather than the monorepo: upstream's bun workspace
# bundles a dozen internal packages into dist/ with tsup, and the tarball is
# exactly that output. What it does not ship is a lockfile, so one is vendored
# here — regenerate it with the commands at the bottom of this file.
let
  # Chrome for Testing's headless shell, as nixpkgs' Playwright patches it.
  # hyperframes would download the same thing into ~/.cache on first render,
  # but an unpatched binary does not run on NixOS. Full chromium would work
  # too, only without HeadlessExperimental.beginFrame, so every render falls
  # back to the slower screenshot capture path.
  headlessShell = playwright-driver.browsers.override {
    withChromium = false;
    withChromiumHeadlessShell = true;
    withFirefox = false;
    withWebkit = false;
    withFfmpeg = false;
  };
in
buildNpmPackage (finalAttrs: {
  pname = "hyperframes";
  version = "0.8.181";

  src = fetchurl {
    url = "https://registry.npmjs.org/hyperframes/-/hyperframes-${finalAttrs.version}.tgz";
    hash = "sha256-SaJw0uG8AoqXmZ1ZdWu4mcstmoD3sRFL45SXXwZ2OYs=";
  };

  npmDepsHash = "sha256-ml8jeko3Vt56RGRYWtrKR9rN9aF+F7bnFsMPFFJhUGE=";

  nodejs = nodejs_22;

  # The published package.json still lists the monorepo's `workspace:*`
  # devDependencies, which npm cannot even parse; the bundle needs none of them.
  postPatch = ''
    ${lib.getExe jq} 'del(.devDependencies, .scripts)' package.json > package.json.tmp
    mv package.json.tmp package.json
    cp ${./package-lock.json} package-lock.json

    # `init` copies its templates with cpSync/copyFileSync, which carry the
    # store's read-only mode into the new project — and then fails writing to
    # its own index.html. Make every copy owner-writable. The bundle's chunk
    # names are content hashes, so find the two copy sites by what they say.
    getBuiltinFs='process.getBuiltinModule("node:fs")'
    copyDir=$(grep -l '^// src/utils/copyDir.ts$' dist/*.js)
    substituteInPlace "$copyDir" --replace-fail \
      'cpSync(src, dest, { ...options, recursive: true, filter: () => true });' \
      'cpSync(src, dest, { ...options, recursive: true, filter: () => true });
      for (const entry of ["", ...'"$getBuiltinFs"'.readdirSync(dest, { recursive: true })]) {
        const path = dest + "/" + entry;
        '"$getBuiltinFs"'.chmodSync(path, '"$getBuiltinFs"'.statSync(path).mode | 0o200);
      }'
    init=$(grep -l '^async function scaffoldProject(' dist/*.js)
    substituteInPlace "$init" --replace-fail \
      '        copyFileSync(src, dest);' \
      '        copyFileSync(src, dest);
        '"$getBuiltinFs"'.chmodSync(dest, 0o644);'
  '';

  nativeBuildInputs = [ makeWrapper ];

  dontNpmBuild = true;

  # sharp and esbuild resolve their platform binaries through optional
  # dependencies; their install scripts only re-verify those or try a network
  # fallback.
  npmFlags = [ "--ignore-scripts" ];
  npmRebuildFlags = [ "--ignore-scripts" ];

  # `--set-default` throughout, so any of these can still be overridden from the
  # environment. Updates and skill installs belong to Nix and home-manager, not
  # to the CLI rewriting ~/.claude behind their back.
  postFixup = ''
    ${lib.optionalString stdenv.hostPlatform.isLinux ''
      # The directory name embeds Playwright's revision and the arch, so look
      # the binary up instead of spelling it out.
      browser=$(find -L ${headlessShell} -type f -name chrome-headless-shell -perm -u+x | head -n1)
      test -n "$browser"
    ''}
    for bin in $out/bin/hyperframes $out/bin/hyperframes-localize-fonts; do
      wrapProgram "$bin" \
        --set-default HYPERFRAMES_FFMPEG_PATH ${lib.getExe' ffmpeg-headless "ffmpeg"} \
        --set-default HYPERFRAMES_FFPROBE_PATH ${lib.getExe' ffmpeg-headless "ffprobe"} \
        --set-default HYPERFRAMES_NO_UPDATE_CHECK 1 \
        --set-default HYPERFRAMES_NO_AUTO_INSTALL 1 \
        --set-default HYPERFRAMES_SKIP_SKILLS 1 \
        --set-default HYPERFRAMES_NO_TELEMETRY 1 \
        ${lib.optionalString stdenv.hostPlatform.isLinux "--set-default HYPERFRAMES_BROWSER_PATH \"$browser\""}
    done
  '';

  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck
    HOME=$TMPDIR $out/bin/hyperframes --version | grep -F ${finalAttrs.version}
    runHook postInstallCheck
  '';

  passthru = {
    # The skills, as a plugin wired to this CLI — see ./plugin.nix.
    plugin = callPackage ./plugin.nix { hyperframes = finalAttrs.finalPackage; };
  };

  meta = {
    description = "Write HTML, render video: deterministic MP4s from HTML, CSS and seekable animations";
    homepage = "https://hyperframes.heygen.com";
    changelog = "https://github.com/heygen-com/hyperframes/releases/tag/v${finalAttrs.version}";
    license = lib.licenses.asl20;
    maintainers = with lib.maintainers; [ antono ];
    mainProgram = "hyperframes";
    platforms = [
      "x86_64-linux"
      "aarch64-linux"
      "aarch64-darwin"
    ];
  };
})

# Bumping: change `version` and the src hash, then regenerate the lockfile
# against the new tarball and refresh npmDepsHash (and plugin.nix's src hash):
#
#   curl -sL https://registry.npmjs.org/hyperframes/-/hyperframes-$V.tgz | tar xz
#   cd package && jq 'del(.devDependencies, .scripts)' package.json > p && mv p package.json
#   npm install --package-lock-only --ignore-scripts && cp package-lock.json <sneg>/pkgs/hyperframes/
