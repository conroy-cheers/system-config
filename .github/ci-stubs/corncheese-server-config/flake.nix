{
  description = "CI stub for corncheese-server-config";

  outputs =
    { ... }:
    {
      nixosModules.corncheese-server =
        { lib, ... }:
        {
          options.corncheese-server = lib.mkOption {
            type = lib.types.attrs;
            default = { };
          };
        };
    };
}
