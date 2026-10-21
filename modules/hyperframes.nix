# Installs the hyperframes CLI and hands its skills to the coding agents.
#
# The skills go in as a *plugin*, never as loose skill directories. The router
# skill decides how to behave by looking for a plugin manifest two levels
# above its own SKILL.md: with one, it treats the install as read-only and runs
# the CLI through the plugin's launcher, which sneg patches to this package.
# Loose skills under ~/.claude/skills/<name> find no manifest, fall back to
# standalone mode, and start running `npx hyperframes skills update` — which
# downloads a second CLI from npm and tries to rewrite skills that live in the
# store.
#
# claude-code and codex take plugins through their own home-manager modules.
# Everything else that reads ~/.agents/skills (codex too, opencode, gemini-cli
# and the rest of the Agent Skills crowd) is served by `enableAgentsSkills`,
# which keeps the plugin shape by hand: each skill is linked to
# ~/.agents/skills/<name>, and the plugin's manifest to ~/.agents/plugin.json —
# two levels above every SKILL.md, which is where the router looks.
#
# Curried over sneg's overlay so `package` can default to sneg's hyperframes
# without the consumer having to apply the overlay to their own nixpkgs first.
{ overlay }:
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.programs.hyperframes;

  snegPkgs = pkgs.extend overlay;
in
{
  options.programs.hyperframes = {
    enable = lib.mkEnableOption "the HyperFrames CLI and its agent skills";

    package = lib.mkOption {
      type = lib.types.package;
      default = snegPkgs.hyperframes;
      defaultText = lib.literalExpression "sneg.packages.\${system}.hyperframes";
      description = "The hyperframes CLI.";
    };

    plugin = lib.mkOption {
      type = lib.types.package;
      default = cfg.package.plugin;
      defaultText = lib.literalExpression "config.programs.hyperframes.package.plugin";
      description = ''
        The skills plugin handed to the agents. The default runs
        {option}`programs.hyperframes.package`, so overriding that is enough to
        move both together.
      '';
    };

    enableClaudeCodeIntegration = lib.mkOption {
      type = lib.types.bool;
      default = config.programs.claude-code.enable or false;
      defaultText = lib.literalExpression "config.programs.claude-code.enable";
      description = ''
        Whether to install the skills as a Claude Code plugin, through
        {option}`programs.claude-code.plugins`. The router is then
        `/hyperframes:hyperframes`.
      '';
    };

    enableCodexIntegration = lib.mkOption {
      type = lib.types.bool;
      default = (config.programs.codex.enable or false) && !cfg.enableAgentsSkills;
      defaultText = lib.literalExpression "config.programs.codex.enable && !config.programs.hyperframes.enableAgentsSkills";
      description = ''
        Whether to install the skills as a Codex plugin, through
        {option}`programs.codex.plugins`. Off by default when
        {option}`programs.hyperframes.enableAgentsSkills` is on, since Codex
        reads {file}`~/.agents/skills` too and would see every skill twice.
      '';
    };

    enableAgentsSkills = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Whether to link each skill into {file}`~/.agents/skills/<name>`, the
        user-level directory of the Agent Skills convention, read by Codex,
        opencode, gemini-cli and others. {file}`~/.agents/skills` stays a normal
        directory, so skills installed by other means sit beside these.

        This also writes {file}`~/.agents/plugin.json`, the plugin's portable
        manifest. The router skill looks two levels above its own
        {file}`SKILL.md` for it; without it the skills fall back to standalone
        mode and fetch a second CLI from npm.
      '';
    };
  };

  config = lib.mkIf cfg.enable (
    lib.mkMerge [
      { home.packages = [ cfg.package ]; }

      (lib.mkIf cfg.enableClaudeCodeIntegration {
        programs.claude-code.plugins.hyperframes = cfg.plugin;
      })

      (lib.mkIf cfg.enableCodexIntegration {
        programs.codex.plugins = [ cfg.plugin ];
      })

      (lib.mkIf cfg.enableAgentsSkills {
        home.file = {
          ".agents/plugin.json".source = "${cfg.plugin}/plugin.json";
        }
        // lib.listToAttrs (
          map (
            name: lib.nameValuePair ".agents/skills/${name}" { source = "${cfg.plugin}/skills/${name}"; }
          ) cfg.plugin.skillNames
        );

        warnings = lib.optional cfg.enableCodexIntegration ''
          programs.hyperframes: enableCodexIntegration and enableAgentsSkills are
          both on. Codex reads ~/.agents/skills as well as its plugins, so it will
          see every HyperFrames skill twice.
        '';
      })
    ]
  );
}
