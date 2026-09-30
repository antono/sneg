# Checks ../modules/mcphub.nix without making home-manager an input.
#
# Same trick as ./home-manager.nix: the module only ever reads a handful of
# home-manager options, so this declares stand-ins for exactly those and
# evaluates the module against them. What comes out — the systemd unit, the
# launchd agent, the start script and the generated JSON — is then asserted on
# as text.
#
# The parts worth protecting are the ones a refactor can quietly break without
# failing to evaluate: that the settings file the hub is pointed at is the
# writable one and not a store path, that home-manager's servers are staged
# from the path home-manager actually writes, that the unit changes between
# generations — which is the only thing that makes `home-manager switch` reach
# a running hub — and, above all, that the merge does what the module's whole
# design rests on. That last one is not asserted as text: the jq program is a
# store path, so this runs it against fabricated inputs and looks at the JSON
# that comes out.
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
  # module's restart trigger hinges on that, so a stub that always wrote the
  # file would test nothing.
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
        xdg.dataHome = lib.mkOption { type = lib.types.str; };
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
          dataHome = "/home/test/.local/share";

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

  # Only the platform predicates are faked. `pkgs.extend`, `pkgs.formats`,
  # `pkgs.writeText` and `pkgs.writeShellScript` come through the `//`
  # untouched, so the module resolves its default package and renders its files
  # exactly as it would in anger.
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

  # Everything on: both server sources, extra runners on PATH, a settings key
  # that is not `mcpServers`, and a secrets file whose path contains a space so
  # that a regression in the quoting shows up as a broken script rather than as
  # a silently split argument.
  fullModule = {
    programs.mcp.servers.shared.command = "/run/current-system/sw/bin/shared-server";

    services.mcphub = {
      enable = true;
      basePath = "/mcphub";
      servers.hub-only = {
        command = "/run/current-system/sw/bin/hub-only-server";
        args = [ "--stdio" ];
      };
      settings.systemConfig.routing.enableGlobalRoute = true;
      extraPackages = [ pkgs.jq ];
      environment.DEFAULT_REQUEST_TIMEOUT = "137000";
      environment.MCPHUB_NOTE = ''{"spaced":"value here"}'';
      environmentFile = "/run/secrets/mcphub env.env";
    };
  };

  full = evalLinux fullModule;

  # The same configuration one generation later. The paths in the unit are all
  # stable ~/.config and ~/.local/share ones, so the *only* thing that can tell
  # sd-switch the hub needs restarting is the start script's own store path
  # moving. mcphub re-reads its settings file when the mtime changes, but the
  # merge that would move it runs at start — so if this stops differing, the hub
  # serves the previous generation until the next login.
  nextGeneration = evalLinux (
    lib.recursiveUpdate fullModule {
      services.mcphub.servers.hub-only.args = [
        "--stdio"
        "--verbose"
      ];
    }
  );

  # The mirror image: no home-manager servers, no extra PATH, no secrets file,
  # a port that is not the default and nothing declared for Nix to own. Anything
  # the first case greps *for*, this one greps for the absence of.
  minimal = evalLinux {
    services.mcphub = {
      enable = true;
      port = 41337;
      useHomeManagerServers = false;
      # Deliberately space-containing: `escapeShellArg` leaves an ordinary path
      # unquoted, so this is the only scenario where a regression in the
      # quoting shows up as a broken script rather than as a path that happened
      # not to need it.
      stateDir = "/home/test/.local/share/mcphub 137";
    };
  };

  # `{file:...}` is home-manager's secret idiom, not part of any vocabulary
  # mcphub knows; the hub's copy of this server gets the token text as its
  # credential.
  fileRefServer = evalLinux {
    programs.mcp.servers.secretive = {
      command = "/run/current-system/sw/bin/secretive-server";
      env.TOKEN.file = "/run/secrets/token";
    };
    services.mcphub.enable = true;
  };

  # ...unless it has been restated on the hub's side, which is the documented
  # fix and must therefore not warn.
  fileRefShadowed = evalLinux {
    programs.mcp.servers.secretive = {
      command = "/run/current-system/sw/bin/secretive-server";
      env.TOKEN.file = "/run/secrets/token";
    };
    services.mcphub = {
      enable = true;
      servers.secretive = {
        command = "/run/current-system/sw/bin/secretive-server";
        env.TOKEN = "\${TOKEN}";
      };
    };
  };

  # A stateDir the service manager resolves for itself, which is how the
  # settings file ends up somewhere nobody named.
  relativeState = evalLinux {
    services.mcphub = {
      enable = true;
      stateDir = "mcphub";
    };
  };

  # Turning authentication off on a process that listens on every interface is
  # worth saying out loud.
  skipAuth = evalLinux {
    services.mcphub = {
      enable = true;
      settings.systemConfig.routing.skipAuth = true;
    };
  };

  # darwin, with a secrets file: sourcing it in the start script is the branch
  # with no systemd counterpart, so it is the one worth pinning.
  darwin = evalDarwin {
    services.mcphub = {
      enable = true;
      servers.hub-only.command = "/run/current-system/sw/bin/hub-only-server";
      environmentFile = "/run/secrets/mcphub env.env";
    };
  };

  # darwin without one: nothing sourced, and nothing that looks like it.
  darwinPlain = evalDarwin {
    services.mcphub = {
      enable = true;
      servers.hub-only.command = "/run/current-system/sw/bin/hub-only-server";
    };
  };

  darwinNext = evalDarwin {
    services.mcphub = {
      enable = true;
      servers.hub-only.command = "/run/current-system/sw/bin/other-server";
    };
  };

  darwinArgv = darwin.launchd.agents.mcphub.config.ProgramArguments;
  assertionsOf = evaluated: builtins.toJSON (map (a: a.assertion) evaluated.assertions);
in
pkgs.runCommand "sneg-mcphub-module"
  {
    nativeBuildInputs = [ pkgs.jq ];

    fullStartScript = full.systemd.user.services.mcphub.Service.ExecStart;
    fullWorkingDirectory = full.systemd.user.services.mcphub.Service.WorkingDirectory or "";
    fullMcpEnabled = lib.boolToString full.programs.mcp.enable;
    fullPackages = toString full.home.packages;
    fullAssertions = assertionsOf full;
    fullWarnings = toString (lib.length full.warnings);
    fullEnvironment = lib.concatStringsSep "\n" full.systemd.user.services.mcphub.Service.Environment;
    fullEnvFile = full.systemd.user.services.mcphub.Service.EnvironmentFile;
    fullTriggers = toString full.systemd.user.services.mcphub.Unit."X-Restart-Triggers";
    fullAgents = toString (lib.attrNames full.launchd.agents);
    fullHomeFiles = toString (lib.attrNames full.home.file);

    nextStartScript = nextGeneration.systemd.user.services.mcphub.Service.ExecStart;

    minimalStartScript = minimal.systemd.user.services.mcphub.Service.ExecStart;
    minimalEnvFile = minimal.systemd.user.services.mcphub.Service.EnvironmentFile or "";
    minimalEnvironment = lib.concatStringsSep "\n" minimal.systemd.user.services.mcphub.Service.Environment;
    minimalTriggers = toString minimal.systemd.user.services.mcphub.Unit."X-Restart-Triggers";

    fileRefWarnings = toString (lib.length fileRefServer.warnings);
    fileRefWarningText = toString fileRefServer.warnings;
    shadowedWarnings = toString (lib.length fileRefShadowed.warnings);
    skipAuthWarningText = toString skipAuth.warnings;
    relativeStateAssertions = assertionsOf relativeState;

    darwinArgc = toString (lib.length darwinArgv);
    darwinStartScript = lib.elemAt darwinArgv 0;
    darwinNextStartScript = lib.elemAt darwinNext.launchd.agents.mcphub.config.ProgramArguments 0;
    darwinKeepAlive = builtins.toJSON darwin.launchd.agents.mcphub.config.KeepAlive;
    darwinHomeFiles = toString (lib.attrNames darwin.home.file);
    darwinUnits = toString (lib.attrNames darwin.systemd.user.services);

    darwinPlainStartScript = lib.elemAt darwinPlain.launchd.agents.mcphub.config.ProgramArguments 0;
  }
  ''
    fail() { echo "$@" >&2; exit 1; }

    cp "$fullStartScript" full.sh
    echo "$fullStartScript" > "$out"

    # --- the fully configured start script -----------------------------------

    # The settings file has to be the writable one under stateDir. mcphub
    # rewrites it — the admin password hash on first boot, every bearer key
    # after that — so pointing MCPHUB_SETTING_PATH at anything in the store
    # would fail on the first write rather than the first read.
    grep -qF -- "MCPHUB_SETTING_PATH=" full.sh || fail "the hub is never told where its settings live"
    grep -qF -- "settings=/home/test/.local/share/mcphub/mcp_settings.json" full.sh \
      || fail "settings file is not the writable one under stateDir"
    grep -qF -- "chmod 600" full.sh || fail "the file holding the admin hash is left world-readable"

    grep -qF -- "cd /home/test/.local/share/mcphub" full.sh \
      || fail "the hub does not run from a writable working directory"

    # ...and because it runs from there rather than from its package root, the
    # three files mcphub resolves against $PWD have to be linked in. package.json
    # is the load-bearing one: without it the hub reports its version as "dev"
    # to its dashboard and to every MCP handshake.
    grep -qF -- 'for shared in package.json locales servers.json; do' full.sh \
      || fail "the files mcphub looks for beside \$PWD are not linked into the state dir"

    # Staged from the path home-manager writes, at start rather than at build
    # time, and tolerating its absence.
    grep -qF -- "/home/test/.config/mcp/mcp.json" full.sh \
      || fail "home-manager's servers are never staged for the merge"

    grep -qE -- '^ *export PATH=.*-jq-.*/bin:' full.sh \
      || fail "extraPackages did not reach the PATH the hub hands to its servers"

    grep -qE -- '^ *exec /nix/store/.*/bin/mcphub$' full.sh \
      || fail "the script does not exec mcphub, so the supervisor watches a shell"

    # `environmentFile` is systemd's job on linux; sourcing it here as well
    # would put the secret through a shell for no reason.
    if grep -q -- 'set -a' full.sh; then
      fail "linux start script sources environmentFile despite EnvironmentFile="
    fi

    # --- the merge rule, actually run ----------------------------------------

    # The whole module rests on this: keys Nix declares replace, keys it does
    # not survive, and mcpServers is the union with Nix winning per name.
    merge=$(grep -oE '/nix/store/[^ ]*-mcphub-merge\.jq' full.sh | head -1)
    [ -n "$merge" ] || fail "no jq merge program in the start script"

    cat > state.json <<'JSON'
    {
      "users": [ { "username": "admin", "password": "hash" } ],
      "bearerKeys": [ { "key": "kept" } ],
      "systemConfig": { "routing": { "skipAuth": true } },
      "mcpServers": {
        "added-in-dashboard": { "command": "gone" },
        "authorized": {
          "type": "streamable-http",
          "url": "https://mcp.example.com/mcp",
          "oauth": {
            "clientId": "cid", "accessToken": "at",
            "refreshToken": "rt", "scopes": [ "openid" ],
            "pendingAuthorization": { "codeVerifier": "half-done" }
          }
        },
        "moved": {
          "type": "streamable-http",
          "url": "https://old.example.com/mcp",
          "oauth": { "clientId": "cid", "accessToken": "at" }
        }
      }
    }
    JSON
    cat > hm.json <<'JSON'
    { "mcpServers": { "shared": { "command": "shared" }, "clash": { "command": "from-hm" } } }
    JSON
    cat > own.json <<'JSON'
    {
      "mcpServers": {
        "hub-only": { "command": "hub" },
        "clash": { "command": "from-nix" },
        "authorized": {
          "type": "streamable-http",
          "url": "https://mcp.example.com/mcp",
          "oauth": { "resource": "https://mcp.example.com/mcp" }
        },
        "moved": {
          "type": "streamable-http",
          "url": "https://new.example.com/mcp",
          "oauth": { "resource": "https://new.example.com/mcp" }
        }
      },
      "systemConfig": { "routing": { "enableGlobalRoute": true } }
    }
    JSON

    jq -s -f "$merge" state.json hm.json own.json > merged.json || fail "the merge program is not valid jq"

    [ "$(jq -r '.users[0].password' merged.json)" = "hash" ] \
      || fail "the merge dropped the admin credentials, locking the dashboard out"
    [ "$(jq -r '.bearerKeys[0].key' merged.json)" = "kept" ] \
      || fail "the merge dropped runtime state it never declared"

    # Declared keys replace outright, and shallowly: a recursive merge would
    # leave skipAuth = true here, which is exactly the setting nobody wants
    # surviving by accident.
    [ "$(jq -r '.systemConfig.routing.enableGlobalRoute' merged.json)" = "true" ] \
      || fail "a declared key did not replace the live one"
    [ "$(jq -r '.systemConfig.routing.skipAuth' merged.json)" = "null" ] \
      || fail "the systemConfig merge is recursive, so undeclared subkeys survive"

    [ "$(jq -r '.mcpServers.shared.command' merged.json)" = "shared" ] \
      || fail "home-manager's servers did not reach the merged settings"
    [ "$(jq -r '.mcpServers["hub-only"].command' merged.json)" = "hub" ] \
      || fail "the module's own servers did not reach the merged settings"
    [ "$(jq -r '.mcpServers.clash.command' merged.json)" = "from-nix" ] \
      || fail "services.mcphub.servers lost to programs.mcp on a name clash"
    [ "$(jq -r '.mcpServers["added-in-dashboard"]' merged.json)" = "null" ] \
      || fail "a dashboard-added server survived a declared mcpServers"

    # A remote server's OAuth credentials are the exception to that wipe, and
    # they are the whole reason a declared remote server is usable at all: the
    # hub has to re-run the browser authorization after every switch otherwise.
    [ "$(jq -r '.mcpServers.authorized.oauth.accessToken' merged.json)" = "at" ] \
      || fail "the merge discarded a token the hub had already obtained"
    [ "$(jq -r '.mcpServers.authorized.oauth.clientId' merged.json)" = "cid" ] \
      || fail "the merge discarded the client registration, forcing a new one"
    [ "$(jq -r '.mcpServers.authorized.oauth.resource' merged.json)" = "https://mcp.example.com/mcp" ] \
      || fail "the merge let runtime state overwrite declared oauth config"
    [ "$(jq -r '.mcpServers.authorized.oauth.pendingAuthorization' merged.json)" = "null" ] \
      || fail "the merge resumed a half-finished authorization across a restart"
    # Same name, different place: a credential minted for the old url says
    # nothing to the new one, so it goes with everything else.
    [ "$(jq -r '.mcpServers.moved.oauth.accessToken' merged.json)" = "null" ] \
      || fail "the merge carried a token across a change of url"
    # Nothing in the state under this name, so nothing to carry.
    [ "$(jq -r '.mcpServers["hub-only"].oauth' merged.json)" = "null" ] \
      || fail "the merge invented an oauth block for a server that never had one"

    # ...and with nothing declared, the dashboard keeps its list.
    echo '{}' > empty.json
    jq -s -f "$merge" state.json empty.json empty.json > untouched.json
    [ "$(jq -r '.mcpServers["added-in-dashboard"].command' untouched.json)" = "gone" ] \
      || fail "an undeclared mcpServers was cleared anyway"

    # --- reaching a running hub on `home-manager switch` ---------------------

    [ "$fullStartScript" != "$nextStartScript" ] \
      || fail "start script identical across generations with different config"

    # The one input that is not baked into the script: a stable ~/.config path
    # whose store source moves.
    printf '%s\n' "$fullTriggers" > triggers
    grep -q 'mcp.json' triggers || fail "home-manager's config is not a restart trigger"

    printf '%s\n' "$minimalTriggers" > minimal-triggers
    if grep -q '/mcp.json' minimal-triggers; then
      fail "home-manager config triggered on despite useHomeManagerServers = false"
    fi

    # --- the hub's own environment -------------------------------------------

    printf '%s\n' "$fullEnvironment" > env

    grep -qxF -- 'PORT="3000"' env || fail "PORT missing or not upstream's default"
    grep -qxF -- 'BASE_PATH="/mcphub"' env || fail "basePath not plumbed to BASE_PATH"
    grep -qxF -- 'DEFAULT_REQUEST_TIMEOUT="137000"' env || fail "environment not plumbed"

    # systemd unquotes and unescapes Environment= itself, so the value has to be
    # a quoted C string; plain interpolation truncates this at the first space
    # and leaves the quotes in.
    grep -qxF -- 'MCPHUB_NOTE="{\"spaced\":\"value here\"}"' env \
      || fail "Environment= not quoted/escaped for systemd's unquoting parser"

    # MCPHUB_SETTING_PATH is the script's to export, next to the merge that
    # produces the file it names.
    if grep -q 'MCPHUB_SETTING_PATH' env; then
      fail "settings path set in two places at once"
    fi

    [ "$fullEnvFile" = "/run/secrets/mcphub env.env" ] \
      || fail "environmentFile not plumbed to EnvironmentFile="
    [ -z "$minimalEnvFile" ] || fail "EnvironmentFile= emitted without environmentFile"

    # Not the unit's job: systemd chdirs before ExecStart and fails hard on a
    # missing directory, which is what a first boot looks like.
    [ -z "$fullWorkingDirectory" ] \
      || fail "WorkingDirectory= set, so the first boot fails before it can create it"

    # --- the rest of the home-manager side -----------------------------------

    [ "$fullMcpEnabled" = "true" ] || fail "useHomeManagerServers did not enable programs.mcp"

    case "$fullPackages" in
      *mcphub*) ;;
      *) fail "mcphub not added to home.packages" ;;
    esac

    case "$fullAssertions" in
      *false*) fail "a valid configuration tripped an assertion" ;;
    esac

    [ "$fullWarnings" = 0 ] || fail "a valid configuration produced a warning"

    # The launchd log directory is a darwin concern only.
    [ -z "$fullHomeFiles" ] || fail "home.file written on linux: $fullHomeFiles"
    [ -z "$fullAgents" ] || fail "launchd agent emitted on linux: $fullAgents"

    # --- the mirror image ----------------------------------------------------

    cp "$minimalStartScript" minimal.sh

    printf '%s\n' "$minimalEnvironment" > minimal-env
    grep -qxF -- 'PORT="41337"' minimal-env || fail "port not plumbed through to PORT"
    if grep -q 'BASE_PATH' minimal-env; then
      fail "BASE_PATH emitted despite basePath = null"
    fi

    if grep -q -- '/mcp/mcp.json' minimal.sh; then
      fail "home-manager config staged despite useHomeManagerServers = false"
    fi

    if grep -qE -- '^ *export PATH=' minimal.sh; then
      fail "PATH rewritten despite extraPackages = [ ]"
    fi

    # Still merges: the declared side is empty, so this is the run that must
    # leave the live file exactly as mcphub left it.
    grep -qF -- "-mcphub-merge.jq" minimal.sh || fail "the merge is skipped when nothing is declared"

    grep -qF -- "cd '/home/test/.local/share/mcphub 137'" minimal.sh \
      || fail "a stateDir needing quotes was spliced in unquoted"
    grep -qF -- "settings='/home/test/.local/share/mcphub 137/mcp_settings.json'" minimal.sh \
      || fail "a settings path needing quotes was spliced in unquoted"

    # --- and the case that must be rejected ----------------------------------

    case "$relativeStateAssertions" in
      *false*) ;;
      *) fail "a relative stateDir was accepted" ;;
    esac

    # --- and the cases that must only warn -----------------------------------

    [ "$fileRefWarnings" = 1 ] || fail "no warning for an unresolvable {file:...} env reference"
    case "$fileRefWarningText" in
      *secretive*) ;;
      *) fail "the {file:...} warning does not name the server" ;;
    esac

    [ "$shadowedWarnings" = 0 ] \
      || fail "restating the server on the hub's side still warned"

    case "$skipAuthWarningText" in
      *skipAuth*) ;;
      *) fail "disabling authentication on a hub that binds every interface went unremarked" ;;
    esac

    # --- darwin, with a secrets file -----------------------------------------

    [ "$darwinArgc" = 1 ] || fail "launchd runs something other than the start script alone"

    cp "$darwinStartScript" darwin.sh

    # launchd has no EnvironmentFile equivalent, so the file is sourced in the
    # script instead. A lost quote splits the path; a lost `exec` orphans the
    # hub from launchd.
    grep -qF -- ". '/run/secrets/mcphub env.env'" darwin.sh \
      || fail "environmentFile not sourced, or unquoted, on darwin"
    grep -q -- 'set -a' darwin.sh || fail "sourced environmentFile is never exported"
    grep -qE -- '^ *exec /nix/store/.*/bin/mcphub$' darwin.sh \
      || fail "darwin start script does not exec mcphub"

    # home-manager skips an agent whose plist compares equal to the installed
    # one, and every path in this plist is stable — so the script's store path
    # is the only thing that can differ.
    [ "$darwinStartScript" != "$darwinNextStartScript" ] \
      || fail "launchd plist identical across generations, so it never reloads"

    [ "$darwinKeepAlive" = "true" ] || fail "the hub is not kept alive"

    case "$darwinHomeFiles" in
      */home/test/.cache/mcphub/.keep*) ;;
      *) fail "launchd log directory is never created" ;;
    esac

    [ -z "$darwinUnits" ] || fail "systemd unit emitted on darwin: $darwinUnits"

    # --- darwin, without one -------------------------------------------------

    cp "$darwinPlainStartScript" darwin-plain.sh

    if grep -q -- 'set -a' darwin-plain.sh; then
      fail "environmentFile sourced despite environmentFile = null"
    fi
  ''
