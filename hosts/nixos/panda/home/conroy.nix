{
  inputs,
  ...
}:

{
  imports = [ inputs.stylix.homeModules.stylix ];

  home = {
    username = "conroy";
    homeDirectory = "/home/conroy";
    stateVersion = "24.05";
  };

  corncheese.shell = {
    enable = true;
    starship = true;
    p10k = false;
    direnv = true;
    zoxide = true;
    atuin = {
      enable = true;
      sync = false;
    };
    shells = [ "fish" ];
  };

  programs.home-manager.enable = true;
}
