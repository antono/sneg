{
  lib,
  buildGoModule,
  fetchFromGitHub,
  makeWrapper,
  # `browser` is appended to PATH so that go-rod's LookPath finds a usable
  # Chromium for `deplexity login`. Rod's own auto-download fetches a
  # dynamically linked binary that does not run on NixOS.
  browser ? null,
}:

let
  # Hard fork of clappingmonkey/Deplexity taken just before upstream #75 (it
  # changes the thread directory layout and duplicates existing archives). It
  # keeps threads/<uuid>/ and adds `export --attachments`. Not a tagged release.
  version = "0.3.0-unstable-2026-11-21";
in
buildGoModule {
  pname = "deplexity";
  inherit version;

  src = fetchFromGitHub {
    owner = "antono";
    repo = "Deplexity";
    rev = "e0087fae9dd1263df62b6189ad8886b97b16eaa2";
    hash = "sha256-vbr2NOUt/4KefV5k+eeyLH4lMxm0gn/y8cSit1RExTw=";
  };

  vendorHash = "sha256-2iVkSQC8yTAJv6Uyw5Lv62S0NMaSwDsqkzRIWAoMVDw=";

  ldflags = [
    "-s"
    "-w"
    "-X main.version=${version}"
    "-X main.buildTime=nix"
  ];

  nativeBuildInputs = lib.optional (browser != null) makeWrapper;

  postInstall = lib.optionalString (browser != null) ''
    wrapProgram $out/bin/deplexity \
      --suffix PATH : ${lib.makeBinPath [ browser ]}
  '';

  meta = {
    description = "Export your Perplexity AI conversations, spaces, and profile to JSON, Markdown and PDF";
    homepage = "https://github.com/antono/Deplexity";
    license = lib.licenses.mit;
    mainProgram = "deplexity";
    platforms = lib.platforms.unix;
  };
}
