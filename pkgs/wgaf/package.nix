# wgaf — Wayland automation framework for GNOME Shell. Two binaries from one
# cargo workspace: `wgaf-daemon`, which owns /dev/uinput, AT-SPI and the
# session keymap and serves them over D-Bus, and the `wgaf` CLI that talks to
# it. Window, workspace and monitor control go through a GNOME Shell extension
# shipped in the same repo, since only the compositor knows that geometry.
#
# Everything upstream's `make install` scatters over $HOME lands under $out
# instead: the systemd user unit, the extension (with its schema compiled) and
# the template configs. Wiring them into a session — enabling the unit and the
# extension, the /dev/uinput udev rule and `input` group — is left to the
# consumer's NixOS/home-manager config, as upstream leaves it to the user.
{
  lib,
  dbus,
  fetchFromGitHub,
  gjs,
  glib,
  installShellFiles,
  libxkbcommon,
  rustPlatform,
  stdenv,
  versionCheckHook,
}:

rustPlatform.buildRustPackage (finalAttrs: {
  pname = "wgaf";
  version = "0.8.8";

  src = fetchFromGitHub {
    owner = "Ranrar";
    repo = "wgaf";
    tag = "v${finalAttrs.version}";
    hash = "sha256-2Pz/oGIeQRuxavrC603JiGlO5D+fR1d0Vw9eFrfA340=";
  };

  cargoHash = "sha256-+Atz1Inz5k2QuM5NJC+Frkzuxn9XI74fAZoWFmEM1nc=";

  nativeBuildInputs = [
    glib # glib-compile-schemas, for the extension
    installShellFiles
  ];

  # The daemon links the C libxkbcommon to resolve the session keymap the same
  # way the compositor does; wayland-client is pure Rust and needs nothing.
  buildInputs = [ libxkbcommon ];

  # Upstream CI's own unit-test step. Three permissions::notify tests register
  # a stub notification service, so they want a private session bus. The
  # integration suites under wgaf-daemon/tests start a real daemon and are
  # left to upstream's CI.
  cargoTestFlags = [
    "--workspace"
    "--bins"
    "--lib"
  ];

  nativeCheckInputs = [
    dbus
    gjs
  ];

  # A bus of our own rather than wrapping the run in dbus-run-session, so
  # cargoCheckHook still drives the tests and reuses the build's artifacts.
  preCheck = ''
    export DBUS_SESSION_BUS_ADDRESS=$(dbus-daemon --fork --print-address \
      --config-file=${dbus}/share/dbus-1/session.conf)
  '';

  # The extension's unit tests: plain gjs, no Shell session needed.
  postCheck = ''
    make -C extension test
  '';

  postInstall = ''
    install -Dm644 packaging/systemd/wgaf-daemon.service -t $out/lib/systemd/user
    substituteInPlace $out/lib/systemd/user/wgaf-daemon.service \
      --replace-fail '%h/.cargo/bin/wgaf-daemon' "$out/bin/wgaf-daemon"

    # Templates only: the daemon refuses group/world-writable configs, so they
    # are copied (mode 600) into ~/.config/wgaf, never linked from the store.
    install -Dm644 packaging/config.toml packaging/permissions.toml -t $out/share/wgaf

    extdir=$out/share/gnome-shell/extensions/wgaf@wgaf.dev
    install -Dm644 -t $extdir \
      extension/{metadata,extension,dbusInterface,windows,pointer,confirm}.*
    install -Dm644 extension/schemas/*.gschema.xml -t $extdir/schemas
    glib-compile-schemas $extdir/schemas
  ''
  + lib.optionalString (stdenv.buildPlatform.canExecute stdenv.hostPlatform) ''
    installShellCompletion --cmd wgaf \
      --bash <($out/bin/wgaf completions bash) \
      --fish <($out/bin/wgaf completions fish) \
      --zsh <($out/bin/wgaf completions zsh)
  '';

  # `wgaf --version` prints the workspace version, so this catches a stale
  # `version` against a bumped tag.
  versionCheckProgramArg = "--version";
  doInstallCheck = true;
  nativeInstallCheckInputs = [ versionCheckHook ];

  meta = {
    description = "Wayland automation for GNOME Shell: windows, keyboard/mouse input and AT-SPI UI automation";
    homepage = "https://github.com/Ranrar/wgaf";
    changelog = "https://github.com/Ranrar/wgaf/blob/v${finalAttrs.version}/CHANGELOG.md";
    license = lib.licenses.mit;
    maintainers = with lib.maintainers; [ antono ];
    mainProgram = "wgaf";
    # /dev/uinput, Wayland and GNOME Shell.
    platforms = lib.platforms.linux;
  };
})
