# Runs mcp-hub as a user service.
#
# mcp-hub is not an MCP server; it is a supervisor that starts the servers it
# is given and re-exports them over one HTTP endpoint, so clients that cannot
# spawn processes themselves (mcphub.nvim above all) get a single stable port
# to talk to instead of N stdio children.
#
# The interesting seam is its config format: `--config` takes a JSON file whose
# top-level `mcpServers` key is exactly the shape home-manager's `programs.mcp`
# already writes to ${xdg.configHome}/mcp/mcp.json. So the servers declared once
# for claude-code, opencode and friends — including the ones sneg's
# ./home-manager.nix bridge feeds in — can be handed to mcp-hub as they are,
# with no second source of truth. That is what `useHomeManagerServers` does.
#
# "As they are" is the point and also the limit. Two things do not survive the
# trip, and both are silent, so the module diagnoses them at evaluation time
# rather than letting them surface as a mystery at runtime:
#
#   * on/off state. home-manager normalises it to `enabled`; mcp-hub only reads
#     `disabled` and starts anything else. A server switched off in
#     `programs.mcp` would therefore be *running* under the hub — see the
#     assertion below.
#   * file-backed secrets. `env.<VAR>.file` is rendered by home-manager as the
#     literal token `{file:/path}`, which only its per-client modules rewrite.
#     mcp-hub's placeholder vocabulary is `${VAR}`, `${env:VAR}`, `${cmd: ...}`,
#     `${userHome}` and `${workspaceFolder}`; anything else is passed through
#     untouched — see the warning below.
#
# This module is independent of ./home-manager.nix and does not import it: the
# bridge writes `programs.mcp.servers`, this passes the file that option
# generates to the hub. It does read `programs.mcp.servers` itself, but only to
# raise the two diagnostics above — never to re-render it.
#
# Curried over sneg's overlay so `package` can default to sneg's mcp-hub
# without the consumer having to apply `overlays.default` first — the same
# trick ../lib/default.nix uses.
{ overlay }:
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.services.mcphub;

  jsonFormat = pkgs.formats.json { };

  # The mcphub-only config file, written only when there is something to put in
  # it. An empty file would still be a valid `--config` argument, and would
  # therefore silently satisfy the assertion below — better to leave it out.
  hasOwnConfig = cfg.servers != { } || cfg.settings != { };

  ownConfigFile = jsonFormat.generate "mcphub-servers.json" (
    cfg.settings // { mcpServers = cfg.servers; }
  );

  ownConfigPath = "${config.xdg.configHome}/mcphub/servers.json";
  homeManagerConfigPath = "${config.xdg.configHome}/mcp/mcp.json";

  # `programs.mcp` writes mcp.json only when it is *both* enabled and has
  # servers to put in it — its `xdg.configFile` sits under a second
  # `mkIf (cfg.servers != { })`. So `useHomeManagerServers` on its own is not
  # evidence that the first `--config` path will ever exist, and the assertion
  # below must not treat it as one.
  hasHomeManagerServers =
    cfg.useHomeManagerServers && config.programs.mcp.enable && config.programs.mcp.servers != { };

  # Same reason, from the other end: the entry is absent, not null, when
  # `programs.mcp` decides not to write the file, so this has to be an `or`
  # rather than a check on `useHomeManagerServers`.
  hmConfigEntry = config.xdg.configFile."mcp/mcp.json" or null;

  # Store paths standing in for "the configuration changed". They are never
  # passed to mcp-hub — their only job is to make the generated unit and plist
  # differ between generations, so home-manager restarts the hub.
  #
  # This is not something `--watch` can do. The paths on the command line are
  # stable ~/.config paths, so the unit text is otherwise byte-identical across
  # generations; and mcp-hub's watcher follows the symlink and holds an inotify
  # watch on the /nix/store inode it resolved at startup, which is immutable and
  # is never written to. Repointing the symlink fires no event. `extraConfigFiles`
  # is deliberately left out: those are runtime paths with no store path, and
  # edited in place they are exactly the case `--watch` does handle.
  restartTriggers =
    lib.optional hasOwnConfig "${ownConfigFile}"
    ++ lib.optional (cfg.useHomeManagerServers && hmConfigEntry != null) "${hmConfigEntry.source}";

  # Servers `programs.mcp` has switched off. home-manager strips `disabled` and
  # emits `enabled` (lib.hm.mcp.resolveEnabled); mcp-hub reads `disabled` and
  # nothing else, so it would spawn these. Ones the user has already restated
  # under `services.mcphub.servers` are fine — that entry replaces this one.
  disabledHomeManagerServers = lib.optionals cfg.useHomeManagerServers (
    lib.attrNames (
      lib.filterAttrs (
        name: server: (server.enabled or null) == false && !(cfg.servers ? ${name})
      ) config.programs.mcp.servers
    )
  );

  # Servers whose env carries a `{file:...}` reference, which mcp-hub does not
  # resolve. Same shadowing rule: a restatement under `services.mcphub.servers`
  # is the documented fix, so a shadowed server is not reported.
  fileRefHomeManagerServers = lib.optionals cfg.useHomeManagerServers (
    lib.attrNames (
      lib.filterAttrs (
        name: server:
        !(cfg.servers ? ${name})
        && lib.any (value: lib.isAttrs value && value ? file) (lib.attrValues (server.env or { }))
      ) config.programs.mcp.servers
    )
  );

  # Order is precedence. mcp-hub merges the `mcpServers` sections of every
  # `--config` in the order given (a later file's entry replaces an earlier
  # file's entry of the same name — *replaces*, not merges into) but overwrites
  # every other top-level key outright with the last file that sets it. Hence:
  # shared home-manager servers first, mcphub-only servers and `settings` second
  # so they win, and anything the user names explicitly last so it wins over both.
  #
  # Missing files are skipped by mcp-hub without error, which is what makes
  # `extraConfigFiles` usable for a runtime path such as a sops-decrypted file.
  configPaths =
    lib.optional cfg.useHomeManagerServers homeManagerConfigPath
    ++ lib.optional hasOwnConfig ownConfigPath
    ++ cfg.extraConfigFiles;

  hubArgs = [
    "--port"
    (toString cfg.port)
  ]
  ++ lib.concatMap (path: [
    "--config"
    path
  ]) configPaths
  ++ lib.optional cfg.watch "--watch"
  ++ lib.optional cfg.autoShutdown "--auto-shutdown"
  ++ lib.optionals (cfg.shutdownDelay != null) [
    "--shutdown-delay"
    (toString cfg.shutdownDelay)
  ];

  command = [ (lib.getExe cfg.package) ] ++ hubArgs;
in
{
  options.services.mcphub = {
    enable = lib.mkEnableOption "mcp-hub, a local hub that supervises MCP servers behind one HTTP port";

    package = lib.mkOption {
      type = lib.types.package;
      default = (pkgs.extend overlay).mcp-hub;
      defaultText = lib.literalExpression "sneg.packages.\${system}.mcp-hub";
      description = ''
        The mcp-hub package to run. Also added to `home.packages`, because
        clients such as mcphub.nvim look the `mcp-hub` binary up on PATH.
      '';
    };

    port = lib.mkOption {
      type = lib.types.port;
      default = 37373;
      description = ''
        TCP port the hub listens on. mcp-hub has no built-in default — `--port`
        is a required argument — so this one is mcphub.nvim's convention, which
        is what makes the client work with no extra configuration.
      '';
    };

    useHomeManagerServers = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Whether to feed home-manager's own MCP configuration
        (`~/.config/mcp/mcp.json`, generated by `programs.mcp`) to the hub as
        the first `--config` file. This is the way to declare a server once and
        have both the direct clients and the hub see it. Enabling this also
        enables `programs.mcp`, so the file is actually written.

        Two things in that file do not mean to mcp-hub what they mean to a
        direct client, and both are caught at evaluation time rather than left
        to fail at runtime:

        - `programs.mcp.servers.<name>.enabled = false`. home-manager
          normalises on/off state onto `enabled`; mcp-hub reads `disabled` and
          starts everything else, so such a server would run under the hub.
        - `programs.mcp.servers.<name>.env.<VAR>.file`. home-manager renders a
          file reference as the literal string `{file:/path}`, which only its
          per-client modules rewrite. mcp-hub resolves `''${VAR}`,
          `''${env:VAR}`, `''${cmd: ...}`, `''${userHome}` and
          `''${workspaceFolder}`, and passes anything else through untouched —
          so the server receives the token text as its secret.

        The fix for either is to restate that server under
        `services.mcphub.servers`, which is merged later and therefore wins.
        Restate it *whole* — mcp-hub replaces a same-named entry rather than
        merging into it, so a lone `disabled = true` would drop `command` and
        take the hub down with a config error at startup. For a secret, use
        `env.<VAR> = "''${cmd: cat /run/secrets/...}"`: that string is a
        placeholder resolved by the hub, not the secret itself, so it is safe
        in the store.
      '';
    };

    servers = lib.mkOption {
      type = lib.types.attrsOf (lib.types.submodule { freeformType = jsonFormat.type; });
      default = { };
      description = ''
        Servers exposed through the hub only, in mcp-hub's own schema:
        `command`/`args`/`env`/`cwd` for stdio servers, `url`/`headers` for
        remote ones, `disabled` to keep one from starting. Values may use
        mcp-hub's placeholders — `''${VAR}`, `''${env:VAR}`, `''${cmd: ...}`,
        `''${userHome}`, `''${workspaceFolder}`.

        These are merged after `useHomeManagerServers`, so a server named here
        replaces one of the same name from `programs.mcp` — the whole entry,
        not field by field, so restate it in full.

        Note that this is rendered into a /nix/store file, which is
        world-readable: use a `''${cmd: ...}` placeholder or `environmentFile`
        for anything secret.
      '';
      example = lib.literalExpression ''
        {
          deploy-notes = {
            url = "https://notes.example.com/mcp";
            headers.Authorization = "Bearer ''${cmd: cat /run/secrets/notes-token}";
          };
        }
      '';
    };

    settings = lib.mkOption {
      type = lib.types.submodule { freeformType = jsonFormat.type; };
      default = { };
      description = ''
        Extra top-level keys merged into the same generated config file as
        `servers`. Anything mcp-hub reads outside `mcpServers` goes here.
      '';
    };

    extraConfigFiles = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = ''
        Additional `--config` paths, appended last and therefore winning over
        everything above. Paths that do not exist are skipped by mcp-hub
        without error, so a file produced at runtime — a sops-decrypted one, or
        a per-project config — is fine here.
      '';
      example = [ "/run/user/1000/secrets/mcphub-servers.json" ];
    };

    watch = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Whether to pass `--watch`, making the hub reload when a config file's
        *contents* change in place. That is what `extraConfigFiles` looks like:
        a runtime path rewritten by sops or a project tool.

        It is not what a `home-manager switch` looks like. Those files are
        store symlinks, and mcp-hub's watcher follows the symlink to hold an
        inotify watch on the immutable /nix/store inode it resolved at startup,
        so repointing the link fires no event. New generations are handled by
        restarting the service instead — `Unit.X-Restart-Triggers` on linux, a
        generation marker in the agent's environment on darwin.
      '';
    };

    autoShutdown = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Whether to pass `--auto-shutdown`, so the hub exits once its last
        client disconnects.

        Off by default because nothing here starts it again: the exit is clean,
        and neither the systemd unit (`Restart = "on-failure"`) nor the launchd
        agent (`KeepAlive.SuccessfulExit = false`, set for exactly this reason)
        restarts a clean exit, and there is no socket activation. The hub stays
        down until the next login or `systemctl --user start mcphub`, and a
        client that cannot spawn servers itself — the whole reason the hub
        exists — finds nothing on the port.
      '';
    };

    shutdownDelay = lib.mkOption {
      type = lib.types.nullOr lib.types.int;
      default = null;
      description = ''
        Grace period in milliseconds before `autoShutdown` actually exits, as
        `--shutdown-delay`. Only meaningful together with `autoShutdown`;
        `null` leaves mcp-hub's own default (0) alone.
      '';
      example = 137;
    };

    environment = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = { };
      description = ''
        Extra environment variables for the hub process itself.

        These land in the generated unit or agent file, which is world-readable
        in /nix/store — the same caveat as `env` on sneg's server modules. Use
        `environmentFile` for anything secret.

        `MCP_HUB_ENV` is the notable one: a JSON string whose keys are injected
        into the environment of every server the hub manages.
      '';
      example = {
        MCP_HUB_ENV = ''{"PROJECT_ROOT":"/home/antono/Code"}'';
      };
    };

    environmentFile = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = ''
        Path to a `KEY=value` file sourced into the hub's environment at start.
        Read at runtime and never copied into the store, so this is where API
        tokens belong.
      '';
      example = "/run/secrets/mcphub.env";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        # Not `configPaths != []`: `useHomeManagerServers` contributes a path
        # whether or not anything writes it, and mcp-hub skips a missing
        # `--config` silently, so the hub would come up, bind the port and
        # serve nothing at all.
        assertion = hasHomeManagerServers || hasOwnConfig || cfg.extraConfigFiles != [ ];
        message = ''
          services.mcphub: no configuration source that will actually exist.
          `useHomeManagerServers` points --config at ${homeManagerConfigPath},
          but `programs.mcp` writes that file only when it is enabled *and*
          `programs.mcp.servers` is non-empty; otherwise mcp-hub starts, binds
          the port and serves no servers at all. Declare
          `programs.mcp.servers`, or `services.mcphub.servers`, or — if that
          file comes from somewhere other than home-manager — name it in
          `services.mcphub.extraConfigFiles`.
        '';
      }
      {
        # An assertion and not a warning: the outcome is a server the user has
        # declared to be off, running anyway and re-exported to every client on
        # the hub. That is worth failing the build over.
        assertion = disabledHomeManagerServers == [ ];
        message = ''
          services.mcphub: ${lib.concatStringsSep ", " disabledHomeManagerServers} ${
            if lib.length disabledHomeManagerServers == 1 then "is" else "are"
          } disabled in `programs.mcp`, but mcp-hub does not understand
          home-manager's `enabled` flag — it reads `disabled` and starts
          everything else — so the hub would run ${
            if lib.length disabledHomeManagerServers == 1 then "it" else "them"
          } regardless.

          Restate the server whole under `services.mcphub.servers` with
          `disabled = true` (mcp-hub *replaces* a same-named entry rather than
          merging into it, so `command`/`url` must come along or the hub dies
          with a config error), drop it from `programs.mcp.servers`, or set
          `services.mcphub.useHomeManagerServers = false`.
        '';
      }
    ];

    # A warning rather than an assertion: keeping such a server for the direct
    # clients and not caring that the hub's copy of it cannot authenticate is a
    # legitimate, if unusual, position.
    warnings = lib.optional (fileRefHomeManagerServers != [ ]) ''
      services.mcphub: ${lib.concatStringsSep ", " fileRefHomeManagerServers} use
      `programs.mcp.servers.<name>.env.<VAR>.file`, which home-manager renders
      into mcp.json as the literal string `{file:/path}`. mcp-hub has no
      `{file:...}` placeholder and passes it through unresolved, so the server
      will start under the hub with the token text as its secret and fail to
      authenticate. Restate the server under `services.mcphub.servers` with
      `env.<VAR> = "''${cmd: cat /path}"` instead.
    '';

    # On PATH for clients that shell out to `mcp-hub` (mcphub.nvim does).
    home.packages = [ cfg.package ];

    # No point pointing `--config` at a file nothing writes.
    programs.mcp.enable = lib.mkIf cfg.useHomeManagerServers (lib.mkDefault true);

    xdg.configFile = lib.mkIf hasOwnConfig {
      "mcphub/servers.json".source = ownConfigFile;
    };

    # launchd does not create the parent of StandardOutPath/StandardErrorPath;
    # it fails to open them and the output is lost, which is the worst possible
    # thing to lose silently. A placeholder file is enough, and goes through
    # home-manager's link generation, which runs before the launch agents are
    # set up.
    home.file = lib.mkIf pkgs.stdenv.hostPlatform.isDarwin {
      "${config.xdg.cacheHome}/mcphub/.keep".text = "";
    };

    systemd.user.services.mcphub = lib.mkIf pkgs.stdenv.hostPlatform.isLinux {
      Unit = {
        Description = "mcp-hub, MCP server hub";
        Documentation = "https://github.com/ravitemer/mcp-hub";
        After = [ "network.target" ];
        # Makes the unit text differ when the generated config differs, so
        # sd-switch restarts the hub on `home-manager switch`. See
        # `restartTriggers` above for why `--watch` cannot cover this.
        X-Restart-Triggers = restartTriggers;
      };

      Service = {
        # escapeShellArgs because config paths are user-supplied strings and
        # systemd splits ExecStart on whitespace.
        ExecStart = lib.escapeShellArgs command;
        Restart = "on-failure";
        RestartSec = 5;
        # Quoted so values containing spaces survive systemd's own splitting.
        Environment = lib.mapAttrsToList (name: value: "${name}=${builtins.toJSON value}") cfg.environment;
      }
      // lib.optionalAttrs (cfg.environmentFile != null) {
        EnvironmentFile = cfg.environmentFile;
      };

      Install.WantedBy = [ "default.target" ];
    };

    launchd.agents.mcphub = lib.mkIf pkgs.stdenv.hostPlatform.isDarwin {
      enable = true;
      config = {
        # launchd has no EnvironmentFile equivalent — EnvironmentVariables is a
        # literal plist dict, and secrets must not go there. Rather than making
        # `environmentFile` silently do nothing on darwin, run the hub under a
        # shell that sources the file first. `set -a` exports what it defines;
        # `exec` keeps the shell out of the process tree so launchd still
        # supervises mcp-hub itself.
        ProgramArguments =
          if cfg.environmentFile == null then
            command
          else
            [
              pkgs.runtimeShell
              "-c"
              "set -a; . ${lib.escapeShellArg cfg.environmentFile}; set +a; exec ${lib.escapeShellArgs command}"
            ];

        EnvironmentVariables =
          cfg.environment
          // lib.optionalAttrs (restartTriggers != [ ]) {
            # `X-Restart-Triggers` is a systemd key and means nothing here, and
            # home-manager skips an agent whose plist compares equal to the
            # installed one. mcp-hub ignores this variable; it exists only so
            # the plist actually differs when the config does, and the agent
            # gets reloaded.
            MCPHUB_CONFIG_GENERATION = lib.concatStringsSep ":" restartTriggers;
          };

        RunAtLoad = true;
        # `true` would relaunch the hub immediately after an `--auto-shutdown`
        # exit, turning the option into a spawn loop. Restart on failure only,
        # matching what the systemd unit does.
        KeepAlive = if cfg.autoShutdown then { SuccessfulExit = false; } else true;
        StandardOutPath = "${config.xdg.cacheHome}/mcphub/stdout.log";
        StandardErrorPath = "${config.xdg.cacheHome}/mcphub/stderr.log";
      };
    };
  };
}
