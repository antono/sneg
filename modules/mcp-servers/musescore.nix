# Talks to MuseScore over a WebSocket opened by the QML plugin shipped in
# ${pkgs.mcp-musescore}/share/mcp-musescore, which has to be installed into
# MuseScore's own plugins directory by hand.
{ mkServerModule, ... }:
{
  imports = [
    (mkServerModule {
      name = "musescore";
      packageName = "mcp-musescore";
    })
  ];
}
