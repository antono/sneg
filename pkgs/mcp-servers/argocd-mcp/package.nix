{
  lib,
  fetchFromGitHub,
  buildNpmPackage,
}:

buildNpmPackage (finalAttrs: {
  pname = "argocd-mcp";
  version = "0.6.0";

  src = fetchFromGitHub {
    owner = "argoproj-labs";
    repo = "mcp-for-argocd";
    rev = "v${finalAttrs.version}";
    hash = "sha256-EZE62Ed6AvMLMEwDH0mAd1ocJAg7MTxbIiP39GxMY64=";
  };

  npmDepsHash = "sha256-QAE4FA9Aqib4YjZ4Y4nNbxeAmfQRAWwaEzdmCbNUelU=";

  meta = {
    description = "Argo CD MCP server";
    homepage = "https://github.com/argoproj-labs/mcp-for-argocd";
    license = lib.licenses.asl20;
    maintainers = with lib.maintainers; [ antono ];
    mainProgram = "argocd-mcp";
  };
})
