{
  lib,
  stdenvNoCC,
  fetchFromGitHub,
  nodejs,
  pnpm_10,
  fetchPnpmDeps,
  pnpmConfigHook,
  makeWrapper,
}:

# Upstream builds with pnpm; its package-lock.json is a leftover that stopped
# tracking package.json (it still resolves the MCP SDK at ^1.10), so it must
# not be what decides the dependency closure.
stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "argocd-mcp";
  version = "0.9.0";

  src = fetchFromGitHub {
    owner = "argoproj-labs";
    repo = "mcp-for-argocd";
    rev = "v${finalAttrs.version}";
    hash = "sha256-D94APT+e/PRxZ3JQSvc2N3sTFjSvu3br1MybcnGVd14=";
  };

  pnpmDeps = fetchPnpmDeps {
    inherit (finalAttrs) pname version src;
    pnpm = pnpm_10;
    fetcherVersion = 3;
    hash = "sha256-AEP7UHs1WQ5BI/UKHZCMu0DGa5FzZRD/qPpQVXhV4ZE=";
  };

  nativeBuildInputs = [
    nodejs
    pnpm_10
    pnpmConfigHook
    makeWrapper
  ];

  buildPhase = ''
    runHook preBuild
    pnpm run build
    runHook postBuild
  '';

  doCheck = true;
  checkPhase = ''
    runHook preCheck
    pnpm test
    runHook postCheck
  '';

  # tsup leaves package.json dependencies external, so the bundle needs them
  # at runtime; drop the dev half before copying node_modules.
  installPhase = ''
    runHook preInstall

    CI=true pnpm prune --prod --ignore-scripts

    mkdir -p $out/lib/argocd-mcp $out/bin
    cp -r dist node_modules package.json $out/lib/argocd-mcp/
    makeWrapper ${lib.getExe nodejs} $out/bin/argocd-mcp \
      --add-flags $out/lib/argocd-mcp/dist/index.js

    runHook postInstall
  '';

  meta = {
    description = "Argo CD MCP server";
    homepage = "https://github.com/argoproj-labs/mcp-for-argocd";
    license = lib.licenses.asl20;
    maintainers = with lib.maintainers; [ antono ];
    mainProgram = "argocd-mcp";
  };
})
