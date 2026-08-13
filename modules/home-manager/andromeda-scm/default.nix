{
  config,
  lib,
  ...
}:

let
  cfg = config.andromeda.scm;
  githubRemotePatterns = [
    "git@github.com:andromeda-robotic/**"
    "ssh://git@github.com/andromeda-robotic/**"
    "https://github.com/andromeda-robotic/**"
  ];
in
{
  options.andromeda.scm = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Whether to enable Andromeda source control configuration";
    };

    email = lib.mkOption {
      type = lib.types.str;
      default = "conroy@dromeda.com.au";
      description = "Email address used to author commits in Andromeda repositories";
    };
  };

  config = lib.mkIf (cfg.enable && config.programs.git.enable) {
    programs.git.includes = map (remotePattern: {
      condition = "hasconfig:remote.*.url:${remotePattern}";
      contents.user.email = cfg.email;
      contentSuffix = "andromeda-gitconfig";
    }) githubRemotePatterns;
  };
}
