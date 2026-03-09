{
  nix = {
    settings = {
      substituters = [ "https://cache.corncheese.org/nix-cache" ];
      trusted-public-keys = [
        "nix-cache:kWK431WqAGFMswlTp4Y6XEC3eNTE0awBqtI/PWylnTg="
      ];
    };
  };
}
