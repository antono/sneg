{ pkgs }:

# Python script that mirrors `pnpm.overrides` and `pnpm.patchedDependencies`
# from package.json into pnpm-workspace.yaml. Required because pnpm 11's
# strict frozen-install reads workspace-scoped config from
# pnpm-workspace.yaml, while this project still keeps the truth in
# package.json#pnpm. The synthesised file is consumed inside the Nix
# sandbox only; the repo source is untouched.
#
# It also sets `trustLockfile: true`: pnpm 11's default supply-chain pass
# ("Verifying lockfile against supply-chain policies") re-validates every
# entry against the registry, which needs network access. The deps are
# pre-fetched by fetchPnpmDeps and installed with `--offline`, so we trust
# the already-frozen lockfile and skip that online pass inside the sandbox.

pkgs.writers.writePython3 "merge-pnpm-config"
  {
    libraries = [ pkgs.python3Packages.pyyaml ];
  }
  ''
    import json
    import yaml

    pkg = json.load(open("package.json"))
    pnpm_block = pkg.get("pnpm", {})

    workspace = {}
    try:
        with open("pnpm-workspace.yaml") as fh:
            workspace = yaml.safe_load(fh) or {}
    except FileNotFoundError:
        pass

    overrides = pnpm_block.get("overrides", {})
    patched = pnpm_block.get("patchedDependencies", {})

    if overrides:
        workspace.setdefault("overrides", {}).update(overrides)
    if patched:
        workspace.setdefault("patchedDependencies", {}).update(patched)

    # Offline sandbox builds: skip pnpm 11's registry-backed supply-chain pass.
    workspace["trustLockfile"] = True

    with open("pnpm-workspace.yaml", "w") as fh:
        yaml.safe_dump(workspace, fh, sort_keys=False)
  ''
