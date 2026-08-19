{
  pkgs,
  lib,
  src,
  version,
}:

# Fetches the pnpm dependency graph deterministically using `pnpm-lock.yaml`,
# honoring the `pnpm.overrides` and `pnpm.patchedDependencies` blocks from
# package.json. The output is a /nix/store path containing an offline pnpm
# store that the Tauri build consumes via `pnpm install --offline`.
#
# Hash workflow:
#   1. First build fails with the real hash on `got:` line.
#   2. Replace `hash` below with that value.
#   3. Re-run `nix build .#tolaria-node-modules`.
#
# When dependencies change (pnpm-lock.yaml, patches/, or package.json
# overrides), repeat the dance — the hash is content-addressed. Note it does
# NOT change just because `src` was re-pinned: this is a fixed-output
# derivation keyed on the resolved dependency graph.

let
  pnpmConfigMerge = import ./merge-pnpm-config.nix { inherit pkgs; };
in
pkgs.fetchPnpmDeps {
  pname = "tolaria-pnpm-deps";
  inherit src version;
  # Pin to pnpm 11 to match the project (package.json field implicit, lockfile
  # version 9 + v11 store layout). fetcherVersion 4 is required by nixpkgs
  # 26.11+ for pnpm 11 (v3 dumps a non-reproducible SQLite index.db; v4 stores
  # it as an index.db.sql dump reconstructed by pnpmConfigHook/our consumers).
  pnpm = pkgs.pnpm_11 or pkgs.pnpm;
  fetcherVersion = 4;
  hash = "sha256-w3wjhidsEDbw9CCvxG/apQW79+ik3r083oSS2vP5V9c=";

  # Mirror pnpm.overrides + pnpm.patchedDependencies from package.json into
  # pnpm-workspace.yaml so pnpm 11's strict frozen-install reads them, and
  # raise pnpm's network timeout/concurrency so the fetcher tolerates slow
  # registry responses.
  postPatch = ''
    ${pnpmConfigMerge}
    cat > .npmrc <<'EOF'
    network-timeout=600000
    network-concurrency=4
    fetch-retries=6
    fetch-retry-mintimeout=20000
    fetch-retry-maxtimeout=120000
    EOF
  '';
}
