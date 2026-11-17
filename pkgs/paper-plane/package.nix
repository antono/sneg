# paper-plane — GTK4/libadwaita Telegram client. vitlav's fork of
# paper-plane-developers/paper-plane: upstream has had no commits since June
# 2024 and was dropped from nixpkgs (pinned to a vulnerable TDLib 1.8.19). The
# fork ports it to tdlib-rs and current TDLib and merges the stalled PRs.
#
# The fork has no tags, so the pin is a commit and the version is the crate
# version plus `-unstable-<date>`. Advance both together.
#
# TDLib's JSON API changes between releases, and tdlib-rs generates its
# bindings from the TL schema of the exact library it links, so TDLib is
# pinned to the release the fork targets (1.8.65, the commit in its Flatpak
# manifest). nixpkgs' 1.8.68 does not work: its schema has a recursive type
# (richTextButton) that tdlib-rs' generator emits without a Box, and the
# bindings fail to compile (E0072). Advance this pin only with the fork.
{
  lib,
  stdenv,
  fetchFromGitHub,
  rustPlatform,
  meson,
  ninja,
  pkg-config,
  rustc,
  cargo,
  wrapGAppsHook4,
  desktop-file-utils,
  blueprint-compiler,
  libxml2,
  gtk4,
  libadwaita,
  libshumate,
  tdlib,
  rlottie,
  gst_all_1,
  # Telegram API credentials. These are the ones nixpkgs shipped, which
  # Paper Plane's developers permitted for redistribution in nixpkgs, for use
  # with Paper Plane only. Override with your own from my.telegram.org, or
  # pass `--client-id`/`--client-secret` at run time.
  tgApiId ? 22303002,
  tgApiHash ? "3cc0969992690f032197e6609b296599",
}:

let
  tdlib-paperplane = tdlib.overrideAttrs {
    pname = "tdlib-paperplane";
    version = "1.8.65";
    src = fetchFromGitHub {
      owner = "tdlib";
      repo = "td";
      rev = "a8f21f5230172634becc1739050ef23ecd6ea291";
      hash = "sha256-cCNXRyeu6ZMf/0oxipPPUyniGuLzvWFLWCvklPIYvzk=";
    };
  };

  # Paper Plane renders animated stickers with its own rlottie fork; this is
  # the pin nixpkgs used.
  rlottie-paperplane = rlottie.overrideAttrs (prev: {
    pname = "rlottie-paperplane";
    version = "0-unstable-2022-09-14";
    src = fetchFromGitHub {
      owner = "paper-plane-developers";
      repo = "rlottie";
      rev = "1dd47cec7eb8e1f657f02dce9c497ae60f7cf8c5";
      hash = "sha256-OIKnDikuJuRIR9Jvl1PnUA9UAV09EmgGdDTeWoVi7jk=";
    };
    patches = [ ];
    env = (prev.env or { }) // {
      NIX_CFLAGS_COMPILE = (prev.env.NIX_CFLAGS_COMPILE or "") + " -Wno-error";
    };
  });
in
stdenv.mkDerivation (finalAttrs: {
  pname = "paper-plane";
  version = "0.1.0-beta.6-unstable-2026-10-19";

  src = fetchFromGitHub {
    owner = "vitlav";
    repo = "paper-plane";
    rev = "b9295d01c3923a9416121f23d6f79a24ca49f762";
    hash = "sha256-DCNd3FyQQu14hCuCJR2rxT1sTgnPBUfHmxP+WZJ0pSM=";
  };

  cargoDeps = rustPlatform.fetchCargoVendor {
    inherit (finalAttrs) src;
    hash = "sha256-LY3Nx0UsVRk4UXahZoo7C29ygVQLYeF5NoeVfBQu56c=";
  };

  strictDeps = true;

  nativeBuildInputs = [
    meson
    ninja
    pkg-config
    rustPlatform.cargoSetupHook
    rustPlatform.bindgenHook
    rustc
    cargo
    wrapGAppsHook4
    desktop-file-utils
    blueprint-compiler # called by the gtk4-rs `blueprint` feature at build time
    libxml2.bin # xmllint, for compressed gresources
  ];

  buildInputs = [
    gtk4
    libadwaita
    libshumate
    tdlib-paperplane
    rlottie-paperplane
    gst_all_1.gstreamer
    gst_all_1.gst-libav
    gst_all_1.gst-plugins-base
    gst_all_1.gst-plugins-good
  ];

  mesonFlags = [
    (lib.mesonOption "tg_api_id" (toString tgApiId))
    (lib.mesonOption "tg_api_hash" tgApiHash)
  ];

  env = {
    # Upstream's release profile is fat LTO with one codegen unit, which makes
    # the aarch64 build crawl (and under binfmt emulation, for hours).
    CARGO_PROFILE_RELEASE_LTO = "thin";
    CARGO_PROFILE_RELEASE_CODEGEN_UNITS = "16";
  };

  meta = {
    homepage = "https://github.com/vitlav/paper-plane";
    description = "Chat over Telegram on a modern and elegant client";
    longDescription = ''
      Paper Plane is an alternative Telegram client. It uses libadwaita
      for its user interface and strives to meet the design principles
      of the GNOME desktop.
    '';
    license = lib.licenses.gpl3Plus;
    mainProgram = "paper-plane";
    platforms = lib.platforms.linux;
  };
})
