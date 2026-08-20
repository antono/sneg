# Proves the composition holds: the six servers taken from mcp-servers-nix and
# the six kept here resolve their packages and render into one config file.
#
# Building this is the whole assertion — a missing package name, an option that
# does not exist, or two modules fighting over the same `settings.servers` key
# all fail here rather than at the consumer.
#
# `executable` is pinned to a plain path on purpose: the defaults are
# `pkgs.chromium` / `pkgs.google-chrome`, and interpolating those would make
# this check build a browser.
{ snegLib, pkgs }:
snegLib.mkConfig pkgs {
  fileName = "mcp-servers-check.json";

  programs = {
    # From mcp-servers-nix.
    chrome-devtools = {
      enable = true;
      executable = "/run/current-system/sw/bin/chromium";
    };
    context7.enable = true;
    home-assistant.enable = true;
    nixos.enable = true;
    playwright = {
      enable = true;
      executable = "/run/current-system/sw/bin/chromium";
    };
    terraform.enable = true;

    # From sneg.
    argocd = {
      enable = true;
      baseUrl = "https://argocd.example.com";
      readOnly = true;
    };
    fibery = {
      enable = true;
      host = "example.fibery.io";
    };
    freecad.enable = true;
    greenhouse.enable = true;
    musescore.enable = true;

    # Also exercises the wrapper upstream generates for secrets, since that is
    # how every token in here is meant to be supplied.
    signoz = {
      enable = true;
      env.SIGNOZ_URL = "https://signoz.example.com";
      passwordCommand.SIGNOZ_API_KEY = [
        "cat"
        "/run/secrets/signoz-api-key"
      ];
    };
  };
}
