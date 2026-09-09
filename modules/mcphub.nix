# Runs mcphub as a user service.
#
# mcphub is not an MCP server; it is a gateway. It starts the servers listed in
# its settings file and re-exports all of them over one HTTP origin — plus a
# React dashboard, a bearer-key system and a CLI — so a client that cannot
# spawn stdio children gets one stable port instead of N processes.
#
# The thing that shapes this whole module is that mcphub *owns its settings
# file*. There is exactly one, `mcp_settings.json`, and mcphub does not merely
# read it: the admin user's password hash is written into it on first boot,
# every bearer key and OAuth client the dashboard mints is appended to it, and
# every server toggled in the UI is written back. A store symlink would fail on
# the first write, and a file regenerated wholesale on every `home-manager
# switch` would throw away the credentials that make the dashboard reachable.
#
# So the file is runtime state, and this module merges into it rather than
# generating it. One rule, applied by the start script below:
#
#   every top-level key this module declares replaces that key in the live
#   file; every top-level key it does not declare is left alone.
#
# `servers` and `useHomeManagerServers` declare `mcpServers`; `settings`
# declares whatever else is named in it. `users`, `bearerKeys`, `groups`,
# `oauthClients`, `oauthTokens`, `prompts` and `resources` are therefore
# preserved untouched unless you name them — and `mcpServers`, once declared,
# is declared *entirely*: a server added through the dashboard is dropped at the
# next restart, which is what asking Nix to own the server list means.
#
# Curried over sneg's overlay so `package` can default to sneg's mcphub without
# the consumer having to apply the overlay to their own nixpkgs first.
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

  # The keys this module claims. Written to the store, merged into the live
  # settings file at every start — see the script below.
  declaredSettings =
    cfg.settings // lib.optionalAttrs (cfg.servers != { }) { mcpServers = cfg.servers; };

  declaredSettingsFile = jsonFormat.generate "mcphub-declared-settings.json" declaredSettings;

  settingsPath = "${cfg.stateDir}/mcp_settings.json";
  homeManagerConfigPath = "${config.xdg.configHome}/mcp/mcp.json";

  # `programs.mcp` writes mcp.json only when it is *both* enabled and has
  # servers to put in it — its `xdg.configFile` sits under a second
  # `mkIf (cfg.servers != { })`. So the entry is absent, not null, whenever
  # home-manager decides not to write the file, and both the restart trigger
  # below and the start script have to cope with that path not existing.
  hmConfigEntry = config.xdg.configFile."mcp/mcp.json" or null;

  # Servers whose env carries a `{file:...}` reference. home-manager renders
  # `env.<VAR>.file` into mcp.json as that literal token and leaves it to its
  # per-client modules to rewrite; mcphub has no such placeholder and passes the
  # token through to the server as its secret. Servers restated under
  # `services.mcphub.servers` are fine — that entry replaces this one.
  fileRefHomeManagerServers = lib.optionals cfg.useHomeManagerServers (
    lib.attrNames (
      lib.filterAttrs (
        name: server:
        !(cfg.servers ? ${name})
        && lib.any (value: lib.isAttrs value && value ? file) (lib.attrValues (server.env or { }))
      ) config.programs.mcp.servers
    )
  );

  # mcphub is configured by environment variable, not by command line — it takes
  # no arguments at all in server mode. `MCPHUB_SETTING_PATH` is deliberately
  # not here: the start script exports it, so it stays right next to the merge
  # that produces the file it names.
  hubEnv = {
    PORT = toString cfg.port;
  }
  // lib.optionalAttrs (cfg.basePath != null) { BASE_PATH = cfg.basePath; }
  // cfg.environment;

  # jq, not nix: two of the three inputs only exist at runtime. The live
  # settings file is state, and ~/.config/mcp/mcp.json is a path this module
  # deliberately reads late so it picks up whatever home-manager actually wrote
  # rather than re-deriving it from `programs.mcp.servers`.
  #
  # `$state + $own` is a shallow, right-biased merge: that is the "declared keys
  # replace, undeclared keys survive" rule, and it is shallow on purpose — a
  # recursive merge would leave half-overwritten `systemConfig` subtrees that
  # match neither what Nix said nor what the dashboard said.
  #
  # Its own file rather than an argument, so it is a store path the test can
  # pick out of the script and run jq against directly — the merge rule is the
  # one piece of this module that is neither Nix nor systemd, and asserting on
  # the text of a shell command would prove nothing about what it does.
  mergeProgram = pkgs.writeText "mcphub-merge.jq" ''
    .[0] as $state | .[1] as $hm | .[2] as $own
    | (($hm.mcpServers // {}) + ($own.mcpServers // {})) as $servers
    | ($state + $own)
    | if $servers == {} then . else .mcpServers = $servers end
  '';

  # Prepended, not replaced: mcphub hands its own PATH to every stdio server it
  # spawns, and the wrapper around the binary has already put its nodejs — and
  # therefore npx — on the end of it.
  pathPreamble = lib.optionalString (cfg.extraPackages != [ ]) ''
    export PATH=${lib.makeBinPath cfg.extraPackages}:"$PATH"
  '';

  # launchd has no EnvironmentFile equivalent — EnvironmentVariables is a
  # literal plist dict, and a secret must not go there. `set -a` exports what
  # the file defines. On linux systemd reads the same file itself, so this is
  # empty there and the secret never passes through a shell.
  environmentFilePreamble =
    lib.optionalString (pkgs.stdenv.hostPlatform.isDarwin && cfg.environmentFile != null)
      ''
        set -a
        . ${lib.escapeShellArg cfg.environmentFile}
        set +a
      '';

  # Read late, on purpose: this picks up whatever home-manager actually wrote,
  # rather than re-deriving it here from `programs.mcp.servers`. A missing file
  # is not an error — see `hmConfigEntry` above for when that happens.
  stageHomeManagerServers =
    if cfg.useHomeManagerServers then
      ''
        if [ -e ${lib.escapeShellArg homeManagerConfigPath} ]; then
          cp ${lib.escapeShellArg homeManagerConfigPath} "$work/hm.json"
        else
          echo '{}' > "$work/hm.json"
        fi
      ''
    else
      ''
        echo '{}' > "$work/hm.json"
      '';

  # One script for both platforms. It also carries the whole configuration in
  # its own store path, which is what makes a `home-manager switch` restart the
  # service: the unit's ExecStart and the agent's ProgramArguments change
  # whenever anything here does. mcphub re-reads its settings file when the
  # mtime moves, but nothing moves it — the merge only runs at start — so the
  # restart is the reload.
  startScript = pkgs.writeShellScript "mcphub-start" ''
    set -euo pipefail
    umask 077

    ${pathPreamble}
    ${environmentFilePreamble}

    # Not `WorkingDirectory=` / launchd's `WorkingDirectory`: both chdir before
    # anything of ours runs and both fail hard when the directory is missing,
    # which is precisely the state of a first boot. Creating it and stepping
    # into it here is the only order that works.
    mkdir -p ${lib.escapeShellArg cfg.stateDir}
    cd ${lib.escapeShellArg cfg.stateDir}

    # Three of mcphub's own lookups resolve against $PWD rather than against the
    # package it was started from, so they only work when it runs out of its
    # package root — which it cannot, because it needs a writable working
    # directory. Linking them in is what buys both:
    #
    #   * package.json is what `getPackageVersion` finds; without it the hub
    #     answers "dev" to its dashboard and to every MCP handshake, because
    #     every server-side caller lets the search path default to $PWD.
    #   * locales/ is i18next's load path; without it the hub falls back to
    #     English, exactly as the published npm package does.
    #   * servers.json is the bundled marketplace index the discover/install
    #     commands read.
    #
    # Relinked on every start so they follow the package across generations.
    for shared in package.json locales servers.json; do
      ln -sfn ${cfg.package}/lib/mcphub/"$shared" "$shared"
    done

    settings=${lib.escapeShellArg settingsPath}
    [ -e "$settings" ] || echo '{}' > "$settings"

    work=$(mktemp -d ${lib.escapeShellArg cfg.stateDir}/.merge.XXXXXX)
    trap 'rm -rf "$work"' EXIT

    ${stageHomeManagerServers}

    ${lib.getExe pkgs.jq} -s -f ${mergeProgram} \
      "$settings" "$work/hm.json" ${declaredSettingsFile} > "$work/merged.json"
    mv "$work/merged.json" "$settings"

    # The file holds the admin password hash and every bearer key mcphub has
    # issued. umask covers what this script creates; chmod covers what it
    # inherited from an earlier, laxer generation.
    chmod 600 "$settings"

    # Explicitly, and not only through the trap: `exec` replaces this shell
    # without running EXIT handlers, so every start would otherwise leave
    # another .merge.XXXXXX behind in the state directory.
    rm -rf "$work"

    export MCPHUB_SETTING_PATH="$settings"
    exec ${lib.getExe cfg.package}
  '';
in
{
  options.services.mcphub = {
    enable = lib.mkEnableOption "mcphub, a self-hosted gateway that fronts many MCP servers behind one endpoint";

    package = lib.mkOption {
      type = lib.types.package;
      default = (pkgs.extend overlay).mcphub;
      defaultText = lib.literalExpression "sneg.packages.\${system}.mcphub";
      description = ''
        The mcphub package to run. Also added to `home.packages`, because the
        same binary is the CLI — `mcphub servers list`, `mcphub call`,
        `mcphub keys create` — and that is worth having on PATH.
      '';
    };

    port = lib.mkOption {
      type = lib.types.port;
      default = 3000;
      description = ''
        TCP port the hub listens on, as `PORT`. This is upstream's default and
        the one its documentation, its Docker image and its CLI's `--url`
        examples all assume.

        Note that mcphub binds every interface — it calls `listen(port)` with no
        host — and there is no option upstream to narrow that. On a machine
        reachable from anywhere but the loopback, put it behind something that
        is, and read `settings.systemConfig.routing.skipAuth` below before
        touching it.
      '';
    };

    basePath = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = ''
        Sub-path to mount the dashboard and the API under, as `BASE_PATH`, for
        serving mcphub from behind a reverse proxy that does not give it a host
        of its own. `null` leaves it at the root.
      '';
      example = "/mcphub";
    };

    stateDir = lib.mkOption {
      type = lib.types.str;
      default = "${config.xdg.dataHome}/mcphub";
      defaultText = lib.literalExpression ''"''${config.xdg.dataHome}/mcphub"'';
      description = ''
        Directory the hub runs in and keeps its state under. It has to be
        writable: `mcp_settings.json` lives here, and mcphub rewrites it —
        first-boot admin credentials, bearer keys, OAuth clients, and anything
        toggled in the dashboard.

        It is also the process's working directory, which matters because a few
        of mcphub's own lookups are relative to it.
      '';
    };

    useHomeManagerServers = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Whether to merge home-manager's own MCP configuration
        (`~/.config/mcp/mcp.json`, generated by `programs.mcp`) into the hub's
        `mcpServers`. This is the way to declare a server once and have both
        the direct clients and the hub see it. Enabling this also enables
        `programs.mcp`, so the file is actually written.

        The two schemas line up better than they look: `type`, `command`,
        `args`, `env`, `url`, `headers` and — importantly — `enabled` all mean
        the same thing on both sides, so a server switched off in
        `programs.mcp` is switched off in the hub too.

        The one thing that does not survive the trip is
        `programs.mcp.servers.<name>.env.<VAR>.file`. home-manager renders a
        file reference as the literal string `{file:/path}` and leaves the
        rewriting to its per-client modules; mcphub has no such placeholder and
        hands the token to the server as its secret. That is caught at
        evaluation time — see the warning below — and the fix is
        `env.<VAR> = "''${VAR}"` plus `environmentFile`, which mcphub does
        understand.

        The file is read when the service starts, not when the configuration is
        built, so it is whatever home-manager last wrote. Servers named in
        `services.mcphub.servers` are merged after it and win.
      '';
    };

    servers = lib.mkOption {
      type = lib.types.attrsOf (lib.types.submodule { freeformType = jsonFormat.type; });
      default = { };
      description = ''
        Servers for the hub, in mcphub's own schema: `command`/`args`/`env` for
        stdio servers, `url`/`headers` with
        `type = "sse" | "streamable-http" | "openapi"` for remote ones,
        `enabled = false` to keep one from starting, plus the per-server
        `tools`, `prompts`, `resources`, `options` and `oauth` sub-objects the
        dashboard also writes.

        Declaring anything here (or through `useHomeManagerServers`) hands the
        whole `mcpServers` key to Nix: servers added through the dashboard are
        dropped at the next restart. Leave both empty and the dashboard owns
        the list.

        This is rendered into a /nix/store file, which is world-readable. For
        anything secret use `''${VAR}` — mcphub expands `''${VAR}` and `$VAR`
        from its *own* environment across a server's `env`, `args`, `headers`
        and `url` — and supply the variable through `environmentFile`.
      '';
      example = lib.literalExpression ''
        {
          fetch = {
            command = "uvx";
            args = [ "mcp-server-fetch" ];
          };

          deploy-notes = {
            type = "streamable-http";
            url = "https://notes.example.com/mcp";
            # Expanded by mcphub from its own environment, so the token itself
            # never reaches the store — see `environmentFile`.
            headers.Authorization = "Bearer ''${NOTES_TOKEN}";
          };
        }
      '';
    };

    settings = lib.mkOption {
      type = lib.types.submodule { freeformType = jsonFormat.type; };
      default = { };
      description = ''
        Further top-level keys of `mcp_settings.json` for Nix to own. Each key
        named here replaces that key in the live file at every start; each key
        left out keeps whatever mcphub last wrote.

        `systemConfig` is the interesting one — routing, smart routing,
        install behaviour. Restate it whole: the merge is shallow, so a
        `systemConfig` given here is the `systemConfig`, not a patch onto the
        dashboard's.

        `users` and `bearerKeys` are credentials mcphub generates and hashes
        itself. Naming them here is how you would pin them, and also how you
        would put a password hash in the world-readable store; there is very
        little reason to.
      '';
      example = lib.literalExpression ''
        {
          systemConfig = {
            routing.enableGlobalRoute = true;
            install.npmRegistry = "https://registry.npmmirror.com";
          };
        }
      '';
    };

    extraPackages = lib.mkOption {
      type = lib.types.listOf lib.types.package;
      default = [ ];
      description = ''
        Packages to prepend to the hub's PATH. mcphub passes its own PATH down
        to every stdio server it spawns, so this is where the runners those
        servers need go — `uv` for `uvx`, `python3`, `docker`. `npx` is already
        there: the package puts its own nodejs on PATH for exactly this reason.
      '';
      example = lib.literalExpression "[ pkgs.uv pkgs.python3 ]";
    };

    environment = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = { };
      description = ''
        Extra environment variables for the hub process.

        These land in the generated unit or agent file, which is world-readable
        in /nix/store — the same caveat as `env` on sneg's server modules. Use
        `environmentFile` for anything secret.

        The ones worth knowing: `ADMIN_PASSWORD` seeds the admin account on
        first boot instead of letting mcphub generate a password and print it
        to the log; `DISABLE_WEB = "true"` runs the API and the MCP endpoints
        without the dashboard; `READONLY = "true"` refuses configuration
        changes through the API, which pairs well with a fully declared
        `servers`; `DEFAULT_REQUEST_TIMEOUT` and `INIT_TIMEOUT` are
        milliseconds.
      '';
      example = {
        READONLY = "true";
        DEFAULT_REQUEST_TIMEOUT = "137000";
      };
    };

    environmentFile = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = ''
        Path to a `KEY=value` file sourced into the hub's environment at start.
        Read at runtime and never copied into the store, so this is where API
        tokens and `ADMIN_PASSWORD` belong — and, together with the `''${VAR}`
        expansion mcphub does on server entries, how a per-server secret stays
        out of the store.
      '';
      example = "/run/secrets/mcphub.env";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        # An assertion and not a warning: a relative path is resolved against
        # whatever directory systemd or launchd happened to start the hub in,
        # so the settings file — the admin password hash, every bearer key —
        # lands somewhere nobody named, and lands somewhere *else* the next
        # time the supervisor's idea of that directory changes.
        assertion = lib.hasPrefix "/" cfg.stateDir;
        message = ''
          services.mcphub: `stateDir` is ${cfg.stateDir}, which is not an
          absolute path. The hub runs from this directory and keeps
          mcp_settings.json in it, so a relative path means its credentials go
          wherever the service manager's working directory happens to point.
        '';
      }
    ];

    # A warning rather than an assertion: keeping such a server for the direct
    # clients and not caring that the hub's copy of it cannot authenticate is a
    # legitimate, if unusual, position.
    warnings =
      lib.optional (fileRefHomeManagerServers != [ ]) ''
        services.mcphub: ${lib.concatStringsSep ", " fileRefHomeManagerServers} use
        `programs.mcp.servers.<name>.env.<VAR>.file`, which home-manager renders
        into mcp.json as the literal string `{file:/path}`. mcphub has no
        `{file:...}` placeholder and passes it through unresolved, so the server
        starts under the hub with the token text as its secret and fails to
        authenticate. Restate the server under `services.mcphub.servers` with
        `env.<VAR> = "''${VAR}"` and supply VAR through
        `services.mcphub.environmentFile`.
      ''
      ++ lib.optional (cfg.settings.systemConfig.routing.skipAuth or false) ''
        services.mcphub: `settings.systemConfig.routing.skipAuth` is enabled.
        That disables dashboard authentication entirely and treats every API
        caller as an admin — and mcphub listens on every interface, so anyone
        who can reach port ${toString cfg.port} can read the settings file,
        export its secrets and register a stdio server, which is arbitrary code
        execution as your user.
      '';

    # The CLI half of the same binary: `mcphub servers list`, `mcphub call`.
    home.packages = [ cfg.package ];

    # No point merging a file nothing writes.
    programs.mcp.enable = lib.mkIf cfg.useHomeManagerServers (lib.mkDefault true);

    # launchd does not create the parent of StandardOutPath/StandardErrorPath;
    # it fails to open them and the output is lost, which is the worst possible
    # thing to lose silently — mcphub prints the generated admin password
    # exactly once, to its log. A placeholder file is enough, and goes through
    # home-manager's link generation, which runs before the launch agents.
    home.file = lib.mkIf pkgs.stdenv.hostPlatform.isDarwin {
      "${config.xdg.cacheHome}/mcphub/.keep".text = "";
    };

    systemd.user.services.mcphub = lib.mkIf pkgs.stdenv.hostPlatform.isLinux {
      Unit = {
        Description = "mcphub, MCP gateway";
        Documentation = "https://github.com/samanhappy/mcphub";
        After = [ "network.target" ];
        # The start script's store path already changes with the configuration,
        # so ExecStart alone is enough to make sd-switch restart the hub. This
        # covers the one input that is *not* baked into it: the servers
        # home-manager writes to a stable ~/.config path.
        X-Restart-Triggers = lib.optional (
          cfg.useHomeManagerServers && hmConfigEntry != null
        ) "${hmConfigEntry.source}";
      };

      Service = {
        ExecStart = "${startScript}";
        Restart = "on-failure";
        RestartSec = 5;
        # Quoted so values containing spaces survive systemd's own splitting.
        Environment = lib.mapAttrsToList (name: value: "${name}=${builtins.toJSON value}") hubEnv;
      }
      // lib.optionalAttrs (cfg.environmentFile != null) {
        EnvironmentFile = cfg.environmentFile;
      };

      Install.WantedBy = [ "default.target" ];
    };

    launchd.agents.mcphub = lib.mkIf pkgs.stdenv.hostPlatform.isDarwin {
      enable = true;
      config = {
        # `environmentFile` is sourced inside the start script on darwin —
        # EnvironmentVariables is a literal plist dict and no place for a
        # secret. See the script above.
        ProgramArguments = [ "${startScript}" ];
        EnvironmentVariables = hubEnv;
        RunAtLoad = true;
        KeepAlive = true;
        StandardOutPath = "${config.xdg.cacheHome}/mcphub/stdout.log";
        StandardErrorPath = "${config.xdg.cacheHome}/mcphub/stderr.log";
      };
    };
  };
}
