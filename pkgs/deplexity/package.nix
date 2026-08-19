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
  version = "0.2.5";
in
buildGoModule {
  pname = "deplexity";
  inherit version;

  src = fetchFromGitHub {
    owner = "clappingmonkey";
    repo = "Deplexity";
    tag = "v${version}";
    hash = "sha256-kPmDpJdDJurNlXydPYqSaFwypSkvs+lsuzNa9fsCDHc=";
  };

  vendorHash = "sha256-1xdJ7M7sW20WfzZMws5/yIHPPQdki7f3fCwvkkLS6Pg=";

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
