{ hostPlatform, ... }:

builtins.elem hostPlatform.system [
  "x86_64-linux"
  "aarch64-darwin"
]
