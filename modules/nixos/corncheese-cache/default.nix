{
  nix = {
    settings = {
      substituters = [ "https://cache.corncheese.org/nix-cache" ];
      trusted-public-keys = [
        "nix-cache:kWK431WqAGFMswlTp4Y6XEC3eNTE0awBqtI/PWylnTg="
        # Accept native narinfos cached before the unified Attic endpoint cutover.
        "hydra-cache.corncheese.org-1:GQu59r26GAfW2L3iabuolY3SL6OPJviuC8j9UJWcTnw="
      ];
    };
  };
}
