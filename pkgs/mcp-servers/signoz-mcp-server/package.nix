{
  lib,
  buildGoModule,
  fetchFromGitHub,
}:

buildGoModule (finalAttrs: {
  pname = "signoz-mcp-server";
  version = "0.15.0";

  src = fetchFromGitHub {
    owner = "SigNoz";
    repo = "signoz-mcp-server";
    rev = "v${finalAttrs.version}";
    hash = "sha256-A4mh6RVcan/xQYnDEEeQ4yE534ZRuVn1lN5kw1NmVYo=";
  };

  vendorHash = "sha256-dJdijxxvMp84ZOMOoHlQrarn/sqsVmSh9fxQ8RAEzD8=";

  # The other cmd/ packages and test/ helpers are upstream's dev tooling.
  subPackages = [ "cmd/server" ];

  # As upstream's .goreleaser.yaml does; it ends up in the User-Agent and logs.
  ldflags = [
    "-s"
    "-w"
    "-X github.com/SigNoz/signoz-mcp-server/pkg/version.Version=v${finalAttrs.version}"
  ];

  # The guardrail walks every .go file under the repo root, which in this build
  # includes the vendor/ tree, so it flags the MCP SDK's own registration code.
  checkFlags = [ "-skip=^TestGuardrail_ProductionRegistrationsUseCheckedHelpers$" ];

  # Upstream's main package is `cmd/server`, so the binary lands as `server`.
  postInstall = ''
    mv $out/bin/server $out/bin/signoz-mcp-server
  '';

  meta = {
    description = "MCP server for the SigNoz observability platform";
    homepage = "https://github.com/SigNoz/signoz-mcp-server";
    license = lib.licenses.asl20;
    maintainers = with lib.maintainers; [ antono ];
    mainProgram = "signoz-mcp-server";
  };
})
