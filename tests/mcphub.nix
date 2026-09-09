# Checks ../modules/mcphub.nix without making home-manager an input.
#
# Same trick as ./home-manager.nix: the module only ever reads a handful of
# home-manager options, so this declares stand-ins for exactly those and
# evaluates the module against them. What comes out — the systemd unit, the
# launchd agent and the generated JSON — is then asserted on as text.
#
# The parts worth protecting are the ones a refactor can quietly break without
# failing to evaluate: that `--port` carries the configured port at all, that
# both config files reach the command line *in precedence order* (home-manager's
# first, mcphub's own second, `extraConfigFiles` last), that the mcphub-only
# servers actually land in the file that second path points at, and that the
# unit changes between generations — which is the only thing that makes
# `home-manager switch` reach a running hub.
#
# Both platform branches are exercised on every system: the module gates them on
# `pkgs.stdenv.hostPlatform`, so the evaluations below run against a pkgs whose
# platform flags are forced either way. That keeps the darwin branch — the more
# intricate of the two — from being invisible to a linux builder, and keeps this
# check evaluating at all on aarch64-darwin, where the systemd unit is absent.
#
# Every positive assertion is paired with a negative one — a check that only
# ever greps for things that are present cannot fail.
{ pkgs }:
let
  inherit (pkgs) lib;

  # The home-manager surface ../modules/mcphub.nix touches, and nothing else.
  # Loose types on purpose: this stands in for home-manager's real options, it
  # is not trying to re-implement them.
  #
  # The one thing it does model faithfully is *when* `programs.mcp` writes its
  # file — under both `mkIf cfg.enable` and `mkIf (cfg.servers != { })`. The
  # module's assertion and its restart trigger both hinge on that, so a stub
  # that always wrote the file would test neither.
  homeManagerStub =
    { config, ... }:
    {
      options = {
        home.packages = lib.mkOption {
          type = lib.types.listOf lib.types.package;
          default = [ ];
        };
        home.file = lib.mkOption {
          type = lib.types.attrsOf lib.types.anything;
          default = { };
        };
        programs.mcp.enable = lib.mkEnableOption "programs.mcp";
        programs.mcp.servers = lib.mkOption {
          type = lib.types.attrsOf lib.types.anything;
          default = { };
        };
        xdg.configHome = lib.mkOption { type = lib.types.str; };
        xdg.cacheHome = lib.mkOption { type = lib.types.str; };
        xdg.configFile = lib.mkOption {
          type = lib.types.attrsOf lib.types.anything;
          default = { };
        };
        systemd.user.services = lib.mkOption {
          type = lib.types.attrsOf lib.types.anything;
          default = { };
        };
        launchd.agents = lib.mkOption {
          type = lib.types.attrsOf lib.types.anything;
          default = { };
        };
        assertions = lib.mkOption {
          type = lib.types.listOf lib.types.anything;
          default = [ ];
        };
        warnings = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [ ];
        };
      };

      config = {
        xdg = {
          configHome = "/home/test/.config";
          cacheHome = "/home/test/.cache";

          configFile = lib.mkIf (config.programs.mcp.enable && config.programs.mcp.servers != { }) {
            "mcp/mcp.json".source = pkgs.writeText "mcp.json" (
              builtins.toJSON { mcpServers = config.programs.mcp.servers; }
            );
          };
        };
      };
    };

  # ../modules/mcphub.nix is curried over sneg's overlay so `package` can
  # default without the consumer applying it. Feeding it the real overlay is
  # part of the test: it proves the default resolves to a derivation.
  #
  # `inputs` is empty because only tolaria reads it, and ../pkgs/default.nix
  # binds tolaria lazily — nothing here forces it.
  mcphubModule = import ../modules/mcphub.nix {
    overlay = import ../overlay.nix { };
  };

  # Only the platform predicates are faked. `pkgs.extend`, `pkgs.formats` and
  # `pkgs.runtimeShell` come through the `//` untouched, so the module resolves
  # its default package and renders its files exactly as it would in anger —
  # which is also why the darwin assertions below stay structural and never
  # pin an interpreter's store path.
  withPlatform =
    flags:
    pkgs
    // {
      stdenv = pkgs.stdenv // {
        hostPlatform = pkgs.stdenv.hostPlatform // flags;
      };
    };

  linuxPkgs = withPlatform {
    isLinux = true;
    isDarwin = false;
  };
  darwinPkgs = withPlatform {
    isLinux = false;
    isDarwin = true;
  };

  evalWith =
    platformPkgs: module:
    (lib.evalModules {
      specialArgs = {
        pkgs = platformPkgs;
      };
      modules = [
        homeManagerStub
        mcphubModule
        module
      ];
    }).config;

  evalLinux = evalWith linuxPkgs;
  evalDarwin = evalWith darwinPkgs;

  # Everything on: both config sources, an extra runtime path, and a
  # deliberately space-containing one so a regression in `escapeShellArgs`
  # shows up as a broken argument rather than a silently split one.
  fullModule = {
    programs.mcp.servers.shared.command = "/run/current-system/sw/bin/shared-server";

    services.mcphub = {
      enable = true;
      servers.hub-only = {
        command = "/run/current-system/sw/bin/hub-only-server";
        args = [ "--stdio" ];
      };
      settings.nativeMCPServers.neovim.disabled = false;
      extraConfigFiles = [ "/run/user/1000/mcphub extra.json" ];
      shutdownDelay = 137;
      environment.MCP_HUB_ENV = ''{"PROJECT_ROOT":"/home/test/Code"}'';
      environmentFile = "/run/secrets/mcphub env.env";
    };
  };

  full = evalLinux fullModule;

  # The same configuration one generation later: only the *contents* of the two
  # generated files differ, and both stable ~/.config paths on the command line
  # stay put. If the restart triggers do not move, nothing restarts the hub and
  # it serves the previous generation forever.
  nextGeneration = evalLinux (
    lib.recursiveUpdate fullModule {
      programs.mcp.servers.shared.args = [ "--verbose" ];
      services.mcphub.servers.hub-only.args = [
        "--stdio"
        "--verbose"
      ];
    }
  );

  # The mirror image: no home-manager file, no watching, a port that is not the
  # default, no secrets file. Anything the first case greps *for*, this one
  # greps for the absence of.
  minimal = evalLinux {
    services.mcphub = {
      enable = true;
      port = 41337;
      useHomeManagerServers = false;
      watch = false;
      servers.hub-only.command = "/run/current-system/sw/bin/hub-only-server";
    };
  };

  # The only case where `--auto-shutdown` may appear.
  shutdown = evalLinux {
    services.mcphub = {
      enable = true;
      autoShutdown = true;
      servers.hub-only.command = "/run/current-system/sw/bin/hub-only-server";
    };
  };

  # No source at all: `--config` is required and mcp-hub comes up broken
  # without one, so the module has to catch this itself.
  unconfigured = evalLinux {
    services.mcphub = {
      enable = true;
      useHomeManagerServers = false;
    };
  };

  # The subtler shape of the same mistake: `useHomeManagerServers` left at its
  # default, but nothing declared for `programs.mcp` to write. `--config` is
  # then present and points at a file that never exists, which mcp-hub skips
  # without a word.
  phantomConfig = evalLinux {
    services.mcphub.enable = true;
  };

  # home-manager says off, mcp-hub hears nothing and starts it anyway.
  disabledServer = evalLinux {
    programs.mcp.servers.off = {
      command = "/run/current-system/sw/bin/off-server";
      enabled = false;
    };
    services.mcphub = {
      enable = true;
      servers.hub-only.command = "/run/current-system/sw/bin/hub-only-server";
    };
  };

  # ...unless it has been restated on the hub's side, which is the documented
  # fix and must therefore not trip the assertion.
  disabledServerShadowed = evalLinux {
    programs.mcp.servers.off = {
      command = "/run/current-system/sw/bin/off-server";
      enabled = false;
    };
    services.mcphub = {
      enable = true;
      servers.off = {
        command = "/run/current-system/sw/bin/off-server";
        disabled = true;
      };
    };
  };

  # `{file:...}` is home-manager's secret idiom and not part of mcp-hub's
  # placeholder vocabulary, so the hub's copy of this server gets the token
  # text as its credential.
  fileRefServer = evalLinux {
    programs.mcp.servers.secretive = {
      command = "/run/current-system/sw/bin/secretive-server";
      env.TOKEN.file = "/run/secrets/token";
    };
    services.mcphub.enable = true;
  };

  # darwin, with a secrets file: the shell wrapper is the branch with no
  # systemd counterpart, so it is the one worth pinning.
  darwin = evalDarwin {
    services.mcphub = {
      enable = true;
      servers.hub-only.command = "/run/current-system/sw/bin/hub-only-server";
      environmentFile = "/run/secrets/mcphub env.env";
    };
  };

  # darwin without one: no wrapper at all, and `autoShutdown` must turn
  # `KeepAlive` into something that does not relaunch a clean exit.
  darwinPlain = evalDarwin {
    services.mcphub = {
      enable = true;
      autoShutdown = true;
      servers.hub-only.command = "/run/current-system/sw/bin/hub-only-server";
    };
  };

  darwinArgv = darwin.launchd.agents.mcphub.config.ProgramArguments;
  assertionsOf = evaluated: builtins.toJSON (map (a: a.assertion) evaluated.assertions);
in
pkgs.runCommand "sneg-mcphub"
  {
    fullExecStart = full.systemd.user.services.mcphub.Service.ExecStart;
    fullJson = full.xdg.configFile."mcphub/servers.json".source;
    fullMcpEnabled = lib.boolToString full.programs.mcp.enable;
    fullPackages = toString full.home.packages;
    fullAssertions = assertionsOf full;
    fullWarnings = toString (lib.length full.warnings);
    fullEnvironment = lib.concatStringsSep "\n" full.systemd.user.services.mcphub.Service.Environment;
    fullEnvFile = full.systemd.user.services.mcphub.Service.EnvironmentFile;
    fullTriggers = toString full.systemd.user.services.mcphub.Unit."X-Restart-Triggers";
    fullAgents = toString (lib.attrNames full.launchd.agents);
    fullHomeFiles = toString (lib.attrNames full.home.file);

    nextTriggers = toString nextGeneration.systemd.user.services.mcphub.Unit."X-Restart-Triggers";

    minimalExecStart = minimal.systemd.user.services.mcphub.Service.ExecStart;
    minimalEnvFile = minimal.systemd.user.services.mcphub.Service.EnvironmentFile or "";
    minimalTriggers = toString minimal.systemd.user.services.mcphub.Unit."X-Restart-Triggers";

    shutdownExecStart = shutdown.systemd.user.services.mcphub.Service.ExecStart;

    unconfiguredAssertions = assertionsOf unconfigured;
    phantomAssertions = assertionsOf phantomConfig;
    disabledAssertions = assertionsOf disabledServer;
    shadowedAssertions = assertionsOf disabledServerShadowed;

    fileRefWarnings = toString (lib.length fileRefServer.warnings);
    fileRefWarningText = toString fileRefServer.warnings;

    darwinArgc = toString (lib.length darwinArgv);
    darwinFlag = lib.elemAt darwinArgv 1;
    darwinScript = lib.elemAt darwinArgv 2;
    darwinKeepAlive = builtins.toJSON darwin.launchd.agents.mcphub.config.KeepAlive;
    darwinGeneration =
      darwin.launchd.agents.mcphub.config.EnvironmentVariables.MCPHUB_CONFIG_GENERATION;
    darwinHomeFiles = toString (lib.attrNames darwin.home.file);
    darwinUnits = toString (lib.attrNames darwin.systemd.user.services);

    darwinPlainArgv = builtins.toJSON darwinPlain.launchd.agents.mcphub.config.ProgramArguments;
    darwinPlainArgc = toString (lib.length darwinPlain.launchd.agents.mcphub.config.ProgramArguments);
    darwinPlainKeepAlive = builtins.toJSON darwinPlain.launchd.agents.mcphub.config.KeepAlive;
  }
  ''
    fail() { echo "$@" >&2; exit 1; }

    echo "$fullExecStart" > "$out"

    # --- the fully configured unit -------------------------------------------

    # The default port is mcphub.nvim's convention; getting it wrong makes every
    # client silently fail to find the hub.
    grep -qE -- '--port 37373( |$)' "$out" || fail "--port missing or not the default"

    # Order is precedence, so assert the order and not just the membership.
    grep -qE -- \
      "--config /home/test/.config/mcp/mcp.json .*--config /home/test/.config/mcphub/servers.json .*--config '/run/user/1000/mcphub extra.json'" \
      "$out" || fail "config files missing, out of order, or badly quoted"

    grep -q -- '--watch' "$out" || fail "--watch missing while watch = true"
    grep -qE -- '--shutdown-delay 137( |$)' "$out" || fail "--shutdown-delay not plumbed"
    grep -q -- '/bin/mcp-hub' "$out" || fail "ExecStart does not run mcp-hub"

    # autoShutdown is off by default; its flag must not appear on its own.
    if grep -q -- '--auto-shutdown' "$out"; then
      fail "--auto-shutdown appeared without autoShutdown being set"
    fi

    # --- the file the second --config points at ------------------------------

    grep -q '"hub-only"' "$fullJson" || fail "mcphub-only server missing from generated config"
    grep -q 'hub-only-server' "$fullJson" || fail "mcphub-only server command missing"
    grep -q '"mcpServers"' "$fullJson" || fail "generated config is not in mcp-hub's schema"
    grep -q '"nativeMCPServers"' "$fullJson" || fail "settings not merged into generated config"

    # --- reaching a running hub on `home-manager switch` ---------------------

    # Both generated files must be triggers: the command line is stable across
    # generations, so these store paths are the only thing that tells sd-switch
    # the hub needs restarting. `--watch` cannot see either of them change.
    printf '%s\n' "$fullTriggers" > triggers
    grep -q 'mcphub-servers.json' triggers || fail "mcphub's own config is not a restart trigger"
    grep -q 'mcp.json' triggers || fail "home-manager's config is not a restart trigger"

    [ "$fullTriggers" != "$nextTriggers" ] \
      || fail "restart triggers identical across generations with different config"

    # The runtime-only path is deliberately not a trigger: it has no store path,
    # and edited in place it is what --watch is actually for.
    if grep -q 'mcphub extra.json' triggers; then
      fail "extraConfigFiles leaked into the restart triggers"
    fi

    # No home-manager file to point at, so nothing from it to trigger on.
    printf '%s\n' "$minimalTriggers" > minimal-triggers
    if grep -q '/mcp.json' minimal-triggers; then
      fail "home-manager config triggered on despite useHomeManagerServers = false"
    fi

    # --- the hub's own environment -------------------------------------------

    # systemd unquotes and unescapes Environment= itself, so the value has to be
    # a quoted C string; plain interpolation truncates this JSON at the first
    # space and leaves the quotes in.
    printf '%s\n' "$fullEnvironment" > env
    grep -qxF -- 'MCP_HUB_ENV="{\"PROJECT_ROOT\":\"/home/test/Code\"}"' env \
      || fail "Environment= not quoted/escaped for systemd's unquoting parser"

    [ "$fullEnvFile" = "/run/secrets/mcphub env.env" ] \
      || fail "environmentFile not plumbed to EnvironmentFile="
    [ -z "$minimalEnvFile" ] || fail "EnvironmentFile= emitted without environmentFile"

    # --- the rest of the home-manager side -----------------------------------

    [ "$fullMcpEnabled" = "true" ] || fail "useHomeManagerServers did not enable programs.mcp"

    case "$fullPackages" in
      *mcp-hub*) ;;
      *) fail "mcp-hub not added to home.packages" ;;
    esac

    case "$fullAssertions" in
      *false*) fail "a valid configuration tripped an assertion" ;;
    esac

    [ "$fullWarnings" = 0 ] || fail "a valid configuration produced a warning"

    # The launchd log directory is a darwin concern only.
    [ -z "$fullHomeFiles" ] || fail "home.file written on linux: $fullHomeFiles"
    [ -z "$fullAgents" ] || fail "launchd agent emitted on linux: $fullAgents"

    # --- the mirror image ----------------------------------------------------

    echo "$minimalExecStart" > minimal

    grep -qE -- '--port 41337( |$)' minimal || fail "port not plumbed through to --port"

    if grep -q -- '/mcp/mcp.json' minimal; then
      fail "home-manager config passed despite useHomeManagerServers = false"
    fi

    if grep -q -- '--watch' minimal; then
      fail "--watch passed despite watch = false"
    fi

    if grep -q -- '--shutdown-delay' minimal; then
      fail "--shutdown-delay passed despite shutdownDelay = null"
    fi

    # --- autoShutdown on -----------------------------------------------------

    echo "$shutdownExecStart" > shutdown

    grep -q -- '--auto-shutdown' shutdown || fail "--auto-shutdown missing while autoShutdown = true"

    # --- and the cases that must be rejected ---------------------------------

    case "$unconfiguredAssertions" in
      *false*) ;;
      *) fail "a configuration with no --config source was accepted" ;;
    esac

    # `useHomeManagerServers` alone is not a config source: programs.mcp writes
    # nothing without servers, and mcp-hub skips the missing file in silence.
    case "$phantomAssertions" in
      *false*) ;;
      *) fail "a --config path that nothing writes was accepted as a source" ;;
    esac

    # mcp-hub reads `disabled`, home-manager writes `enabled`; a server switched
    # off in programs.mcp would run under the hub.
    case "$disabledAssertions" in
      *false*) ;;
      *) fail "a server disabled in programs.mcp was accepted unshadowed" ;;
    esac

    case "$shadowedAssertions" in
      *false*) fail "restating the disabled server on the hub's side still failed" ;;
    esac

    # --- and the case that must only warn ------------------------------------

    [ "$fileRefWarnings" = 1 ] || fail "no warning for an unresolvable {file:...} env reference"
    case "$fileRefWarningText" in
      *secretive*) ;;
      *) fail "the {file:...} warning does not name the server" ;;
    esac

    # --- darwin, with a secrets file -----------------------------------------

    # Structural only: `runtimeShell` here is whatever the builder's pkgs
    # provides, so the interpreter's path says nothing. The shape does — a lost
    # `exec` orphans the hub from launchd, and a lost quote splits the path.
    [ "$darwinArgc" = 3 ] || fail "environmentFile wrapper is not [shell -c script]"
    [ "$darwinFlag" = "-c" ] || fail "environmentFile wrapper does not pass -c"

    printf '%s\n' "$darwinScript" > darwin-script
    grep -qE -- "^set -a; \. '/run/secrets/mcphub env\.env'; set \+a; exec .*/bin/mcp-hub " \
      darwin-script || fail "environmentFile wrapper malformed, unquoted, or missing exec"

    # launchd has no X-Restart-Triggers, so the store paths ride along in the
    # environment purely to make the plist differ between generations.
    case "$darwinGeneration" in
      *mcphub-servers.json*) ;;
      *) fail "launchd plist carries no generation marker, so it never reloads" ;;
    esac

    [ "$darwinKeepAlive" = "true" ] || fail "KeepAlive weakened without autoShutdown"

    case "$darwinHomeFiles" in
      */home/test/.cache/mcphub/.keep*) ;;
      *) fail "launchd log directory is never created" ;;
    esac

    [ -z "$darwinUnits" ] || fail "systemd unit emitted on darwin: $darwinUnits"

    # --- darwin, without one -------------------------------------------------

    [ "$darwinPlainArgc" -gt 3 ] || fail "plain darwin argv looks like a shell wrapper"

    printf '%s\n' "$darwinPlainArgv" > darwin-plain
    if grep -q -- '"-c"' darwin-plain; then
      fail "shell wrapper used despite environmentFile = null"
    fi

    # `KeepAlive = true` would relaunch the hub the instant --auto-shutdown
    # exits, which is a spawn loop rather than a shutdown.
    [ "$darwinPlainKeepAlive" = '{"SuccessfulExit":false}' ] \
      || fail "autoShutdown left KeepAlive relaunching a clean exit: $darwinPlainKeepAlive"
  ''
