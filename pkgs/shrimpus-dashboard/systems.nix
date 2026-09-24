{
  hostPlatform,
  lib,
  ...
}:

lib.elem hostPlatform.system [
  "aarch64-darwin"
  "aarch64-linux"
]
