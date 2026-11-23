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
  version = "0.3.0-unstable-2026-11-23";
in
buildGoModule {
  pname = "deplexity";
  inherit version;

  src = fetchFromGitHub {
    owner = "antono";
    repo = "Deplexity";
    rev = "b8526d9d23ad48c763a16c8494e80b0b17694afc";
    hash = "sha256-GwRHUA+DA0GTmZ8bUI7AL6VyOE5Woo0EK2ZLbVfMUQ8=";
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
