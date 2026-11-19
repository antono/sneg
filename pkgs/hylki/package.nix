# hylki — GNOME-native email client (Rust, GTK4/libadwaita, WebKitGTK 6),
# formerly Vireo. Not in nixpkgs. Upstream: hyprlab/hylki (the many GitHub
# copies are forks). Packaged after its Flatpak manifest
# (co.hyprlab.Hylki.yml): plain `cargo build --release`, then the same files
# installed by hand. Upstream ships fast; stable tags only.
{
  lib,
  rustPlatform,
  fetchFromGitHub,
  pkg-config,
  gettext,
  glib,
  wrapGAppsHook4,
  gtk4,
  libadwaita,
  webkitgtk_6_0,
  poppler,
  cairo,
  pango,
  openssl,
  wayland,
  glib-networking,
}:

rustPlatform.buildRustPackage (finalAttrs: {
  pname = "hylki";
  version = "1.48.4";

  src = fetchFromGitHub {
    owner = "hyprlab";
    repo = "hylki";
    tag = "v${finalAttrs.version}";
    hash = "sha256-YU+OWRjIPn1PyIoa+Vyg/gKp4B9RyUOje9IOWLkUDR8=";
  };

  cargoHash = "sha256-zAqlnMQkFNVaVMb1CZdUsuYbLLFgtMdnJv33wfVPCpY=";

  nativeBuildInputs = [
    pkg-config
    gettext # msgfmt for the desktop entry, metainfo and catalogues
    glib # glib-compile-resources, used by build.rs (glib-build-tools)
    wrapGAppsHook4
  ];

  buildInputs = [
    gtk4
    libadwaita
    webkitgtk_6_0
    poppler # poppler-glib: PDF attachment thumbnails
    cairo
    pango
    openssl # native-tls, and libcrypto for the bundled SQLCipher
    wayland # wayland-backend client_system
    glib-networking # TLS for WebKit
  ];

  # Integration tests talk to mail servers / a session bus.
  doCheck = false;

  postInstall = ''
    for po in po/*.po; do
      [ -e "$po" ] || continue
      lang=$(basename "$po" .po)
      install -d $out/share/locale/$lang/LC_MESSAGES
      msgfmt -o $out/share/locale/$lang/LC_MESSAGES/hylki.mo "$po"
    done
    install -d $out/share/applications $out/share/metainfo
    msgfmt --desktop --template=data/co.hyprlab.Hylki.desktop -d po \
      -o $out/share/applications/co.hyprlab.Hylki.desktop
    msgfmt --xml --template=data/co.hyprlab.Hylki.metainfo.xml -d po \
      -o $out/share/metainfo/co.hyprlab.Hylki.metainfo.xml
    for size in 256x256 512x512; do
      install -Dm644 data/icons/hicolor/$size/apps/co.hyprlab.Hylki.png \
        $out/share/icons/hicolor/$size/apps/co.hyprlab.Hylki.png
    done
    install -Dm644 data/icons/hicolor/scalable/apps/co.hyprlab.Hylki.svg \
      $out/share/icons/hicolor/scalable/apps/co.hyprlab.Hylki.svg
    install -Dm644 data/icons/hicolor/symbolic/apps/co.hyprlab.Hylki-symbolic.svg \
      $out/share/icons/hicolor/symbolic/apps/co.hyprlab.Hylki-symbolic.svg
    install -Dm644 data/fontconfig/fallback.conf $out/share/hylki/fontconfig/fallback.conf
    # Restart helper (Settings -> App icon -> Restart Now); upstream's file
    # points at the Flatpak path.
    install -Dm644 data/co.hyprlab.Hylki.Restart.service \
      $out/share/dbus-1/services/co.hyprlab.Hylki.Restart.service
    substituteInPlace $out/share/dbus-1/services/co.hyprlab.Hylki.Restart.service \
      --replace-fail /app/bin/hylki $out/bin/hylki
  '';

  meta = {
    description = "Fast, GNOME-native email client built with Rust and libadwaita";
    homepage = "https://hylki.app";
    changelog = "https://github.com/hyprlab/hylki/blob/v${finalAttrs.version}/CHANGELOG.md";
    license = lib.licenses.agpl3Plus;
    mainProgram = "hylki";
    platforms = lib.platforms.linux;
  };
})
