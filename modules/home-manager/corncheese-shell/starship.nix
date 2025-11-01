{ lib }:
{
  # Get editor completions based on the config schema
  "$schema" = "https://starship.rs/config-schema.json";

  format = lib.concatStrings [
    "[](orange)"
    "$os"
    "$username"
    "[](bg:yellow fg:orange)"
    "$directory"
    "[](fg:yellow bg:cyan)"
    "$git_branch"
    "$git_status"
    "[](fg:cyan bg:blue)"
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
    "[](fg:blue bg:base02)"
    "$docker_context"
    "$conda"
    "$pixi"
    "[](fg:base02 bg:base01)"
    "$time"
    "[ ](fg:base01)"
    "$line_break$character"
  ];

  os = {
    disabled = false;
    style = "bg:orange fg:base00";
  };

  os.symbols = {
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

  username = {
    show_always = true;
    style_user = "bg:orange fg:base01";
    style_root = "bg:orange fg:base01";
    format = "[ $user ]($style)";
  };

  directory = {
    style = "fg:base01 bg:yellow";
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
    style = "bg:cyan";
    format = "[[ $symbol $branch ](fg:base01 bg:cyan)]($style)";
  };

  git_status = {
    style = "bg:cyan";
    format = "[[($all_status$ahead_behind )](fg:base01 bg:cyan)]($style)";
  };

  nodejs = {
    symbol = "";
    style = "bg:blue";
    format = "[[ $symbol( $version) ](fg:base01 bg:blue)]($style)";
  };

  c = {
    symbol = " ";
    style = "bg:blue";
    format = "[[ $symbol( $version) ](fg:base01 bg:blue)]($style)";
  };

  cpp = {
    symbol = " ";
    style = "bg:blue";
    format = "[[ $symbol( $version) ](fg:base01 bg:blue)]($style)";
  };

  rust = {
    symbol = "";
    style = "bg:blue";
    format = "[[ $symbol( $version) ](fg:base01 bg:blue)]($style)";
  };

  golang = {
    symbol = "";
    style = "bg:blue";
    format = "[[ $symbol( $version) ](fg:base01 bg:blue)]($style)";
  };

  php = {
    symbol = "";
    style = "bg:blue";
    format = "[[ $symbol( $version) ](fg:base01 bg:blue)]($style)";
  };

  java = {
    symbol = "";
    style = "bg:blue";
    format = "[[ $symbol( $version) ](fg:base01 bg:blue)]($style)";
  };

  kotlin = {
    symbol = "";
    style = "bg:blue";
    format = "[[ $symbol( $version) ](fg:base01 bg:blue)]($style)";
  };

  haskell = {
    symbol = "";
    style = "bg:blue";
    format = "[[ $symbol( $version) ](fg:base01 bg:blue)]($style)";
  };

  python = {
    symbol = "";
    style = "bg:blue";
    format = "[[ $symbol( $version) ](fg:base01 bg:blue)]($style)";
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
    style = "bg:base01";
    format = "[[  $time ](fg:base05 bg:base01)]($style)";
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
    vimcmd_visual_symbol = "[](bold fg:yellow)";
  };
}
