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
  version = "0.3.0";
in
buildGoModule {
  pname = "deplexity";
  inherit version;

  src = fetchFromGitHub {
    owner = "clappingmonkey";
    repo = "Deplexity";
    tag = "v${version}";
    hash = "sha256-eX0uT2hDqHsqkAXma25GejAmWHrDctqMI6iwW5aALn4=";
  };

  vendorHash = "sha256-cJ64PI6bF8LylyX+lVjTmKElkZDjRpTvQC9nHWs9/60=";

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
    homepage = "https://github.com/clappingmonkey/Deplexity";
    license = lib.licenses.mit;
    mainProgram = "deplexity";
    platforms = lib.platforms.unix;
  };
}
