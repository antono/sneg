# hacktv — analogue TV transmitter. captainjack64's fork of fsphil/hacktv,
# which adds the conditional-access modes (Videocrypt/Syster/Eurocrypt
# variants) and the built-in test cards that the original leaves out.
#
# Upstream has no tags and no release commits, so the pin is a commit and the
# version follows the nixpkgs `-unstable-<date>` convention. Advance both
# together.
{
  lib,
  stdenv,
  fetchFromGitHub,
  pkg-config,
  ffmpeg,
  freetype,
  hackrf,
  libpng,
  soapysdr,
  zlib,
}:

let
  version = "0-unstable-2026-06-05";
in
stdenv.mkDerivation {
  pname = "hacktv";
  inherit version;

  src = fetchFromGitHub {
    owner = "captainjack64";
    repo = "hacktv";
    rev = "6e135bfe6261f9b45efe49fdde11920843f88ecf";
    hash = "sha256-x7cB3R/baMt2xEmYN4IKwB1B2VLRIUwk97XC7inRV3E=";
  };

  # The Makefile lives in src/, not at the repo root.
  sourceRoot = "source/src";

  strictDeps = true;

  nativeBuildInputs = [ pkg-config ];

  # The Makefile discovers the radio backends with `pkg-config --exists` and
  # compiles in whichever it finds, so the buildInputs decide which -o modes
  # exist. osmo-fl2k is not in nixpkgs, hence no `fl2k` output mode.
  buildInputs = [
    ffmpeg
    freetype
    hackrf
    libpng
    soapysdr
    zlib
  ];

  # Upstream derives VERSION from `git log`/`git describe`; there is no git
  # metadata in the fetched tree, so pass it in rather than build a binary
  # that reports its version as "-".
  makeFlags = [ "VERSION=${version}" ];

  # `make install` hardcodes $(PREFIX)/usr/local/bin.
  installPhase = ''
    runHook preInstall
    install -Dm755 hacktv -t $out/bin
    install -Dm644 hacktv.1 -t $out/share/man/man1
    runHook postInstall
  '';

  meta = {
    description = "Analogue TV transmitter for the HackRF, with conditional-access and test card modes";
    homepage = "https://github.com/captainjack64/hacktv";
    license = lib.licenses.gpl3Plus;
    mainProgram = "hacktv";
    platforms = lib.platforms.unix;
  };
}
