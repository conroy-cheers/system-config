{
  lib,
  python3Packages,
  writers,
}:

writers.writePython3Bin "oauth-mcp-gateway"
  {
    libraries = [ python3Packages.fastmcp ];
    flakeIgnore = [ "E501" ];
  }
  ''
    import argparse

    from fastmcp.client.transports import StdioTransport
    from fastmcp.server import create_proxy
    from fastmcp.server.auth import RemoteAuthProvider
    from fastmcp.server.auth.providers.jwt import JWTVerifier
    from fastmcp.server.providers.proxy import ProxyClient
    from pydantic import AnyHttpUrl


    def parse_args():
        parser = argparse.ArgumentParser(
            description="Expose a stdio MCP server over authenticated Streamable HTTP."
        )
        parser.add_argument("--backend-command", required=True)
        parser.add_argument("--resource-name", required=True)
        parser.add_argument("--listen-address", default="127.0.0.1")
        parser.add_argument("--port", type=int, required=True)
        parser.add_argument("--path", default="/mcp")
        parser.add_argument("--public-url", required=True)
        parser.add_argument("--issuer", required=True)
        parser.add_argument("--jwks-uri", required=True)
        parser.add_argument("--audience", required=True)
        parser.add_argument("--required-scope", action="append", required=True)
        return parser.parse_args()


    def main():
        args = parse_args()
        verifier = JWTVerifier(
            jwks_uri=args.jwks_uri,
            issuer=args.issuer,
            audience=args.audience,
            algorithm="RS256",
            required_scopes=args.required_scope,
            ssrf_safe=True,
        )
        auth = RemoteAuthProvider(
            token_verifier=verifier,
            authorization_servers=[AnyHttpUrl(args.issuer)],
            base_url=args.public_url,
            resource_base_url=args.public_url,
            scopes_supported=args.required_scope,
            resource_name=args.resource_name,
        )
        backend = ProxyClient(
            StdioTransport(command=args.backend_command, args=[]),
            roots=None,
            sampling_handler=None,
            elicitation_handler=None,
        )
        server = create_proxy(backend, name=args.resource_name, auth=auth)
        server.run(
            transport="streamable-http",
            host=args.listen_address,
            port=args.port,
            path=args.path,
            show_banner=False,
        )


    if __name__ == "__main__":
        main()
  ''
// {
  meta = {
    description = "OAuth-protected Streamable HTTP gateway for stdio MCP servers";
    license = lib.licenses.mit;
    mainProgram = "oauth-mcp-gateway";
  };
}
