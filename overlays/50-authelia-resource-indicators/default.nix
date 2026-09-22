# Authelia 4.39.23 fixes OAuth resource-indicator grants used by MCP clients.
# Remove this overlay once the pinned nixpkgs includes that release.
_: prev:
let
  version = "4.39.23";
  src = prev.fetchFromGitHub {
    owner = "authelia";
    repo = "authelia";
    rev = "v${version}";
    hash = "sha256-K8DIJFhHJO09sR1uHT+uXodp0HGdUER7UCsAdOyvZrY=";
  };
  web = (prev.callPackage (prev.path + "/pkgs/by-name/au/authelia/web.nix") { }).overrideAttrs (old: {
    inherit version src;
    nativeBuildInputs = [
      prev.nodejs
      prev.pnpmConfigHook
      prev.pnpm_12
    ];
    pnpmDeps = prev.fetchPnpmDeps {
      inherit version src;
      inherit (old) pname sourceRoot;
      pnpm = prev.pnpm_12;
      fetcherVersion = 4;
      hash = "sha256-PI3qPquE/EzPireczTubUJwnhrX8r5HweHFzN+zZn4E=";
    };
  });
in
{
  authelia = (prev.authelia.override { authelia-web = web; }).overrideAttrs (_: {
    inherit version src;
    vendorHash = "sha256-J7/7t4Ae2MGR6ys+FFkOFltMkemldTvT6jOI7Tv7/0w=";
  });
}
