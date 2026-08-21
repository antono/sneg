# This server signs in as a *user* account, not a bot, so the credentials it
# needs are unusually sensitive: TELEGRAM_SESSION_STRING is a bearer token for
# a logged-in Telegram account, and TELEGRAM_API_HASH is a secret too. Neither
# is an option here, because both `env` and `args` land in the world-readable
# /nix/store — supply them via `envFile` or `passwordCommand`. Generate the
# session string with the `telegram-mcp-generate-session` script the package
# installs.
#
# The server exits at startup unless TELEGRAM_API_ID, TELEGRAM_API_HASH and one
# of TELEGRAM_SESSION_STRING / TELEGRAM_SESSION_NAME are all present: its
# module-level bootstrap builds the Telethon client before any tool is called.
{
  config,
  lib,
  mkServerModule,
  ...
}:
let
  cfg = config.programs.telegram;
in
{
  imports = [
    (mkServerModule {
      name = "telegram";
      packageName = "telegram-mcp";
    })
  ];

  options.programs.telegram = {
    apiId = lib.mkOption {
      type = lib.types.nullOr lib.types.int;
      default = null;
      description = ''
        Telegram application ID from https://my.telegram.org, exported as
        TELEGRAM_API_ID. Not a secret on its own — the paired API hash is.
      '';
      example = 137;
    };

    sessionName = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = ''
        Name of an on-disk Telethon session, exported as
        TELEGRAM_SESSION_NAME. An alternative to TELEGRAM_SESSION_STRING for
        hosts where a session file is preferable to a secret in the
        environment; the file is created relative to the server's working
        directory.
      '';
      example = "telegram_session";
    };

    exposedTools = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = ''
        Which tools to expose, as TELEGRAM_EXPOSED_TOOLS. Either `all`
        (upstream's default), `read-only` to keep only tools annotated
        readOnlyHint, or `read-only+<tool>,<tool>` to add named write tools to
        the read-only set. Worth setting: the default grants an LLM the
        ability to send messages as you.
      '';
      example = "read-only+send_message";
    };
  };

  config.settings.servers = lib.mkIf cfg.enable {
    telegram = {
      env =
        lib.optionalAttrs (cfg.apiId != null) { TELEGRAM_API_ID = toString cfg.apiId; }
        // lib.optionalAttrs (cfg.sessionName != null) { TELEGRAM_SESSION_NAME = cfg.sessionName; }
        // lib.optionalAttrs (cfg.exposedTools != null) { TELEGRAM_EXPOSED_TOOLS = cfg.exposedTools; };
    };
  };
}
