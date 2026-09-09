# mcp-hub — a manager process that supervises a set of MCP servers and exposes
# them over one HTTP endpoint, so several clients can share one set of running
# servers instead of each spawning its own. It is a hub, not an MCP server
# itself, which is why it lives here and not under ../mcp-servers.
#
# There is almost nothing to install: `npm run build` (scripts/build.js) is an
# esbuild bundle with an empty `external` list, so *every* dependency — the
# lone runtime dep json5 and the whole pile of devDependencies that are really
# runtime code (yargs, express, @modelcontextprotocol/sdk, chokidar, open,
# uuid, reconnecting-eventsource, fast-deep-equal) — is inlined into a single
# 1.8M minified dist/cli.js. So the output is that one file plus nodejs; the
# json5 copy npm still installs beside it is dead weight, not a real link.
{
  lib,
  fetchFromGitHub,
  buildNpmPackage,
  versionCheckHook,
}:

buildNpmPackage (finalAttrs: {
  pname = "mcp-hub";
  version = "4.2.1";

  src = fetchFromGitHub {
    owner = "ravitemer";
    repo = "mcp-hub";
    tag = "v${finalAttrs.version}";
    hash = "sha256-KakvXZf0vjdqzyT+LsAKHEr4GLICGXPmxl1hZ3tI7Yg=";
  };

  npmDepsHash = "sha256-nyenuxsKRAL0PU/UPSJsz8ftHIF+LBTGdygTqxti38g=";

  # The version yargs reports is not read from package.json at runtime; esbuild
  # substitutes it via `define` at build time, falling back to a literal
  # "v0.0.0" if the define ever stops firing. So the version check below is a
  # real test of the bundle, not just of the wrapper — if it starts printing
  # v0.0.0, upstream's build has silently broken.
  nativeInstallCheckInputs = [ versionCheckHook ];
  versionCheckProgramArg = "--version";
  doInstallCheck = true;

  meta = {
    description = "Manager server for MCP servers, handling process management and tool routing";
    homepage = "https://github.com/ravitemer/mcp-hub";
    license = lib.licenses.mit;
    maintainers = with lib.maintainers; [ antono ];
    mainProgram = "mcp-hub";
    platforms = lib.platforms.unix;
  };
})
