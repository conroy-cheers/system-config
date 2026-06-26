{
  buildGoModule,
  fetchFromGitHub,
  lib,
}:

buildGoModule rec {
  pname = "slack-mcp-server";
  version = "1.3.0";

  src = fetchFromGitHub {
    owner = "korotovsky";
    repo = "slack-mcp-server";
    rev = "v${version}";
    hash = "sha256-I4f6yKV0BXtaxnqi/XNID+Pwl2mWjSqxIHhb07U7sc4=";
  };

  vendorHash = "sha256-+uQRODO9oL8mGKBmdghTxE6R9Fz+3GJFVTi17306gT8=";

  subPackages = [ "cmd/slack-mcp-server" ];

  env.CGO_ENABLED = "0";

  ldflags = [
    "-s"
    "-w"
    "-X github.com/korotovsky/slack-mcp-server/pkg/version.Version=v${version}"
    "-X github.com/korotovsky/slack-mcp-server/pkg/version.BinaryName=slack-mcp-server"
  ];

  doCheck = false;

  meta = {
    description = "Model Context Protocol server for Slack workspaces";
    homepage = "https://github.com/korotovsky/slack-mcp-server";
    license = lib.licenses.mit;
    mainProgram = "slack-mcp-server";
    platforms = lib.platforms.linux ++ lib.platforms.darwin;
  };
}
