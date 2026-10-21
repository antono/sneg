# Checks homeManagerModules.hyperframes against stand-ins for the home-manager
# options it writes, the same way ./home-manager.nix does for the MCP bridge —
# so home-manager need not be an input.
#
# What matters is that every agent gets the skills in plugin shape, and that
# nothing in the plugin still reaches for `npx hyperframes`.
{ pkgs, overlay }:
let
  inherit (pkgs) lib;

  stub =
    type: default:
    lib.mkOption {
      inherit type default;
    };

  evalWith =
    settings:
    (lib.evalModules {
      specialArgs = { inherit pkgs lib; };
      modules = [
        {
          options = {
            warnings = stub (lib.types.listOf lib.types.str) [ ];
            home.packages = stub (lib.types.listOf lib.types.package) [ ];
            home.file = stub (lib.types.attrsOf lib.types.anything) { };
            programs.claude-code = {
              enable = stub lib.types.bool false;
              plugins = stub (lib.types.attrsOf lib.types.package) { };
            };
            programs.codex = {
              enable = stub lib.types.bool false;
              plugins = stub (lib.types.listOf lib.types.package) [ ];
            };
          };
        }
        (import ../modules/hyperframes.nix { inherit overlay; })
        {
          programs.hyperframes.enable = true;
          programs.claude-code.enable = true;
          programs.codex.enable = true;
        }
        settings
      ];
    }).config;

  # Plugins only: claude-code and codex each get one.
  plugins = evalWith { };
  inherit (plugins.programs.hyperframes) package plugin;

  # ~/.agents too, which turns the codex plugin off by default…
  agents = evalWith { programs.hyperframes.enableAgentsSkills = true; };
  agentFiles = lib.attrNames agents.home.file;

  # …and warns when it is forced back on.
  both = evalWith {
    programs.hyperframes.enableAgentsSkills = true;
    programs.hyperframes.enableCodexIntegration = true;
  };
in
assert lib.elem package plugins.home.packages;
assert plugins.programs.claude-code.plugins.hyperframes == plugin;
assert plugins.programs.codex.plugins == [ plugin ];
assert plugins.home.file == { };

assert agents.programs.claude-code.plugins.hyperframes == plugin;
assert agents.programs.codex.plugins == [ ];
assert agents.warnings == [ ];
assert lib.elem ".agents/plugin.json" agentFiles;
assert lib.elem ".agents/skills/hyperframes" agentFiles;
assert lib.length agentFiles == lib.length plugin.skillNames + 1;

assert lib.length both.warnings == 1;
pkgs.runCommand "sneg-hyperframes-module" { nativeBuildInputs = [ pkgs.nodejs ]; } ''
  export HOME=$TMPDIR

  # The patched launcher must answer before reaching the npx fallback.
  launcher=${plugin}/skills/hyperframes/scripts/plugin-cli.mjs
  node --input-type=module -e "
    const { invocation } = await import('$launcher');
    const { command } = invocation(['--version']);
    if (command !== '${lib.getExe package}') throw new Error('launcher runs ' + command);
  "

  # Still true once the skill is copied out of the plugin, away from its
  # manifests, the way agent-skills-nix lays out ~/.agents/skills.
  cp -r ${plugin}/skills/hyperframes loose
  [ "$(node loose/scripts/plugin-cli.mjs --version)" = ${plugin.version} ]

  # Both media-use resolvers, called the way their callers do.
  node --input-type=module -e "
    const { resolveNpxInvocation } = await import('${plugin}/skills/media-use/scripts/lib/npx-sync.mjs');
    const { resolveSpawnCommand } = await import('${plugin}/skills/media-use/audio/scripts/lib/tts.mjs');
    for (const r of [
      resolveNpxInvocation(['--yes', 'hyperframes@1.2.3', 'media-use', 'resolve'], {}),
      resolveNpxInvocation(['hyperframes', 'transcribe', 'a.wav'], {}),
      resolveSpawnCommand('npx', ['hyperframes', 'tts', 'x.txt']),
    ]) {
      if (r.cmd !== '${lib.getExe package}' || r.args[0] === 'hyperframes')
        throw new Error('resolved to ' + JSON.stringify(r));
    }
  "

  # A tripwire for bumps: the npx calls above all go through those resolvers,
  # so a script spawning npx *directly* is a new call site the plugin does not
  # patch yet. Tests may; scripts may not.
  if grep -rnE '\b(spawn|spawnSync|execFile|execFileSync|exec|execSync)\(\s*"npx"' ${plugin}/skills \
       --include='*.mjs' --include='*.js' | grep -v '\.test\.mjs:'; then
    echo "a skill script spawns npx directly; route it to the Nix CLI in plugin.nix" >&2
    exit 1
  fi
  if grep -rnE '^[^#]*npx (--yes |-y )?hyperframes' ${plugin}/skills --include='*.sh' --include='*.py'; then
    echo "a skill shell/python script runs hyperframes through npx" >&2
    exit 1
  fi

  for manifest in plugin.json .claude-plugin/plugin.json .codex-plugin/plugin.json; do
    test -f ${plugin}/$manifest
  done
  for name in ${lib.escapeShellArgs plugin.skillNames}; do
    test -f ${plugin}/skills/$name/SKILL.md
  done

  touch $out
''
