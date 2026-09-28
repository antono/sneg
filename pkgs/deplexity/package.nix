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
  version = "0.4.3";
in
buildGoModule {
  pname = "deplexity";
  inherit version;

  src = fetchFromGitHub {
    owner = "clappingmonkey";
    repo = "Deplexity";
    tag = "v${version}";
    hash = "sha256-+uQ9PR52AAmgQRLK1RxDOrVfI6YslCSTMlJ16UN5IGI=";
  };

  vendorHash = "sha256-rsroyKHlSNknt66vjgKtjUq2TjCZnr4yMjLcPo45VVY=";

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
