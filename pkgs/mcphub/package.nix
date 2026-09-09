# mcphub — a self-hosted gateway that runs a set of MCP servers and re-exports
# them over one HTTP origin, with a React dashboard and a CLI on the side. It is
# a hub, not an MCP server itself, which is why it lives here and not under
# ../mcp-servers.
#
# Two things shape this derivation:
#
#   * There is no single-file bundle to install. `pnpm build` is `tsc` for the
#     backend plus `vite build` for the dashboard, and the result runs out of a
#     normal node package directory — dist/ resolving its imports through a
#     node_modules beside it. So the whole layout is installed under
#     lib/mcphub and `bin/mcphub` is a wrapper around node.
#
#   * Upstream never commits a version. package.json says `"version": "dev"`
#     and both release workflows rewrite it from the git tag with jq before
#     publishing, so a straight source build produces a hub that reports itself
#     as "dev" to its own dashboard, CLI and MCP handshake. postPatch does what
#     the workflow does — see the version check below, which is what would
#     catch it if that ever stopped working.
{
  lib,
  stdenvNoCC,
  fetchFromGitHub,
  fetchPnpmDeps,
  jq,
  makeWrapper,
  nodejs,
  pnpm_10,
  pnpmConfigHook,
  versionCheckHook,
}:

stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "mcphub";
  version = "1.0.35";

  src = fetchFromGitHub {
    owner = "samanhappy";
    repo = "mcphub";
    tag = "v${finalAttrs.version}";
    hash = "sha256-1GJqgsFNOq4e+zdQz76mIhLx13EyMPyvpMtb22dwHLQ=";
  };

  # `pnpm install --force` in the fetcher pulls every platform's optional
  # dependency, not just this host's, so one hash covers all three systems.
  pnpmDeps = fetchPnpmDeps {
    inherit (finalAttrs) pname version src;
    pnpm = pnpm_10;
    fetcherVersion = 4;
    hash = "sha256-fr7v6bqTNy+5RiL8WKv164BMYTcVH3YxKKLMxAkMhPc=";
  };

  # pnpm_10 rather than the default: upstream's lockfile is version 9.0 and its
  # `packageManager` field pins pnpm 10.12.4, which pnpm 11 would want to
  # migrate — and `--frozen-lockfile` will not let it.
  nativeBuildInputs = [
    jq
    makeWrapper
    nodejs
    pnpm_10
    pnpmConfigHook
  ];

  # What .github/workflows/npm-publish.yml does on a tag push.
  postPatch = ''
    jq '.version = "${finalAttrs.version}"' package.json > package.json.tmp
    mv package.json.tmp package.json
  '';

  buildPhase = ''
    runHook preBuild

    pnpm build

    # Rebuild node_modules with the devDependencies dropped. The build needed
    # them — typescript, vite, the whole React toolchain — but nothing at
    # runtime does, and they are the bulk of the tree.
    #
    # `rm -rf` first, and not just `pnpm install --prod` over the top: that
    # form re-links the top level and leaves node_modules/.pnpm exactly as it
    # was, which is where the weight actually is — pruning in place took the
    # visible entries from 907 to 40 and the output from 620M to 620M. The pnpm
    # store is still the one unpacked by pnpmConfigHook, so this stays offline.
    rm -rf node_modules
    pnpm install --prod --offline --frozen-lockfile --ignore-scripts

    runHook postBuild
  '';

  # Deliberately *not* installed: mcp_settings.json. Upstream ships an example
  # one in the package root, and getConfigFilePath() falls back to the package
  # root when neither MCPHUB_SETTING_PATH nor a file in the working directory
  # turns one up. Shipping it here would point that fallback at a read-only
  # store path holding someone else's example servers, and mcphub writes its
  # settings file — it would fail on the first write instead of on the first
  # read, which is much later and much less obvious. Without it the fallback
  # is `$PWD/mcp_settings.json`, which mcphub creates and owns.
  #
  # servers.json (the bundled marketplace index) and locales/ are read-only and
  # are installed. locales/ is resolved relative to the working directory, so
  # it is only found when mcphub runs from the package root; missing, i18next
  # falls back to English, which is what the published npm package does too —
  # its `files` list leaves locales/ out.
  installPhase = ''
    runHook preInstall

    mkdir -p $out/lib/mcphub/frontend
    cp -R package.json bin dist locales node_modules servers.json $out/lib/mcphub/
    cp -R frontend/dist $out/lib/mcphub/frontend/

    # bin/cli.js dispatches: a known subcommand runs the CLI against a remote
    # hub, anything else (including no arguments at all) boots the server. One
    # binary, both jobs — the service module runs it bare.
    #
    # nodejs on PATH is for the servers the hub spawns: `npx` is what most
    # stdio MCP server entries in an mcp_settings.json call, and the hub passes
    # its own PATH down to them. A suffix, so a system npx still wins.
    makeWrapper ${lib.getExe nodejs} $out/bin/mcphub \
      --add-flags $out/lib/mcphub/bin/cli.js \
      --suffix PATH : ${lib.makeBinPath [ nodejs ]}

    runHook postInstall
  '';

  # Runs `mcphub --version`, which reads package.json back out of the installed
  # package root — so it fails if postPatch stops landing.
  #
  # It covers the CLI only, and cannot be made to cover the server. The CLI
  # hands `getPackageVersion` an explicit search path; every server-side caller
  # leaves it to default to `process.cwd()`, and `findPackageRoot` searches only
  # that directory and its parents. So the running hub reports its version as
  # whatever it finds beside its *working directory*, which is why
  # ../../modules/mcphub.nix links package.json into the state directory it runs
  # from. Without that it answers "dev" to its own dashboard and to every MCP
  # handshake.
  nativeInstallCheckInputs = [ versionCheckHook ];
  versionCheckProgramArg = "--version";
  doInstallCheck = true;

  meta = {
    description = "Self-hosted MCP gateway that fronts many MCP servers behind one endpoint, with a dashboard";
    homepage = "https://github.com/samanhappy/mcphub";
    license = lib.licenses.asl20;
    maintainers = with lib.maintainers; [ antono ];
    mainProgram = "mcphub";
    platforms = lib.platforms.unix;
  };
})
