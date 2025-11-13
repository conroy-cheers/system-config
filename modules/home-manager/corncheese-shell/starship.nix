{ lib }:
{
  # Get editor completions based on the config schema
  "$schema" = "https://starship.rs/config-schema.json";

  format = lib.concatStrings [
    "[ ](base03)"
    "$os"
    "$username"
    "[](bg:base13 fg:base09)"
    "$directory"
    "[](fg:base13 bg:base14)"
    "$git_branch"
    "$git_status"
    "[](fg:base14 bg:base15)"
    "$c"
    "$cpp"
    "$rust"
    "$golang"
    "$nodejs"
    "$php"
    "$java"
    "$kotlin"
    "$haskell"
    "$python"
    "[](fg:base15 bg:base02)"
    "$docker_context"
    "$conda"
    "$pixi"
    "[](fg:base02)"
    " "
    "[](fg:base02)"
    "$nix_shell"
    "$time"
    "[ ](fg:base02)"
    "$line_break$character"
  ];

  nix_shell = {
    disabled = false;
    format = ''[$symbol$state(\($name\))]($style)'';
    style = "bold blue bg:base02";
  };

  fill = {
    disabled = false;
    symbol = " ";
  };

  os = {
    disabled = false;
    style = "bg:base03 fg:base05";
    symbols = {
      Windows = "󰍲";
      Ubuntu = "󰕈";
      SUSE = "";
      Raspbian = "󰐿";
      Mint = "󰣭";
      Macos = "󰀵";
      Manjaro = "";
      Linux = "󰌽";
      Gentoo = "󰣨";
      Fedora = "󰣛";
      Alpine = "";
      Amazon = "";
      Android = "";
      AOSC = "";
      Arch = "󰣇";
      Artix = "󰣇";
      EndeavourOS = "";
      CentOS = "";
      Debian = "󰣚";
      Redhat = "󱄛";
      RedHatEnterprise = "󱄛";
      Pop = "";
    };
  };

  username = {
    show_always = true;
    style_user = "bg:base09 fg:base01";
    style_root = "bg:base09 fg:base01";
    format = "[ $user ]($style)";
  };

  directory = {
    style = "fg:base01 bg:base13";
    format = "[ $path ]($style)";
    truncation_length = 3;
    truncation_symbol = "…/";
  };

  directory.substitutions = {
    "Documents" = "󰈙 ";
    "Downloads" = " ";
    "Music" = "󰝚 ";
    "Pictures" = " ";
    "Developer" = "󰲋 ";
  };

  git_branch = {
    symbol = "";
    style = "bg:base14";
    format = "[[ $symbol $branch ](fg:base01 bg:base14)]($style)";
  };

  git_status = {
    style = "bg:base14";
    format = "[[($all_status$ahead_behind )](fg:base01 bg:base14)]($style)";
  };

  nodejs = {
    symbol = "";
    style = "bg:base15";
    format = "[[ $symbol( $version) ](fg:base01 bg:base15)]($style)";
  };

  c = {
    symbol = " ";
    style = "bg:base15";
    format = "[[ $symbol( $version) ](fg:base01 bg:base15)]($style)";
  };

  cpp = {
    symbol = " ";
    style = "bg:base15";
    format = "[[ $symbol( $version) ](fg:base01 bg:base15)]($style)";
  };

  rust = {
    symbol = "";
    style = "bg:base15";
    format = "[[ $symbol( $version) ](fg:base01 bg:base15)]($style)";
  };

  golang = {
    symbol = "";
    style = "bg:base15";
    format = "[[ $symbol( $version) ](fg:base01 bg:base15)]($style)";
  };

  php = {
    symbol = "";
    style = "bg:base15";
    format = "[[ $symbol( $version) ](fg:base01 bg:base15)]($style)";
  };

  java = {
    symbol = "";
    style = "bg:base15";
    format = "[[ $symbol( $version) ](fg:base01 bg:base15)]($style)";
  };

  kotlin = {
    symbol = "";
    style = "bg:base15";
    format = "[[ $symbol( $version) ](fg:base01 bg:base15)]($style)";
  };

  haskell = {
    symbol = "";
    style = "bg:base15";
    format = "[[ $symbol( $version) ](fg:base01 bg:base15)]($style)";
  };

  python = {
    symbol = "";
    style = "bg:base15";
    format = "[[ $symbol( $version) ](fg:base01 bg:base15)]($style)";
  };

  docker_context = {
    symbol = "";
    style = "bg:base02";
    format = "[[ $symbol( $context) ](fg:#83a598 bg:base02)]($style)";
  };

  conda = {
    style = "bg:base02";
    format = "[[ $symbol( $environment) ](fg:#83a598 bg:base02)]($style)";
  };

  pixi = {
    style = "bg:base02";
    format = "[[ $symbol( $version)( $environment) ](fg:base01 bg:base02)]($style)";
  };

  time = {
    disabled = false;
    time_format = "%R";
    style = "bg:base02";
    format = "[[  $time ](fg:base05 bg:base02)]($style)";
  };

  line_break = {
    disabled = false;
  };

  character = {
    disabled = false;
    success_symbol = "[](bold fg:green)";
    error_symbol = "[](bold fg:red)";
    vimcmd_symbol = "[](bold fg:green)";
    vimcmd_replace_one_symbol = "[](bold fg:purple)";
    vimcmd_replace_symbol = "[](bold fg:purple)";
    vimcmd_visual_symbol = "[](bold fg:base13)";
  };
}
