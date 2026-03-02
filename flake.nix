{
  description = "corncheese's NixOS, nix-on-droid and nix-darwin configs";

  outputs =
    inputs:
    inputs.flake-parts.lib.mkFlake { inherit inputs; } (
      { withSystem, flake-parts-lib, ... }:
      {
        systems = [
          "aarch64-linux"
          "i686-linux"
          "x86_64-linux"
          "aarch64-darwin"
          "x86_64-darwin"
        ];

        # BUG: infinite recursion
        # imports = [
        #   ./modules/flake/modules
        # ] ++ inputs.self.flakeModules;

        imports = [
          ./modules/flake/lib
          ./modules/flake/lib-custom
          ./modules/flake/pkgs
          ./modules/flake/modules
          ./modules/flake/configurations
          ./modules/flake/agenix
          ./modules/flake/topology
          ./modules/flake/packages
          ./modules/flake/overlays
          ./modules/flake/shells
        ];

        auto = {
          # Automatic modules, see `./modules/flake/modules/default.nix`
          modules.enableAll = true;

          # Automatic configurations, see `./modules/flake/configurations/default.nix`
          configurations.enableAll = true;

          # Automatic packages, see `./modules/flake/packages/default/default.nix`
          packages.enable = true;

          # Automatic overlays, see `./modules/flake/overlays/default/default.nix`
          overlays.enable = true;

          # Automatic devShells, see `./modules/flake/shells/default/default.nix`
          devShells.enable = true;
        };

        perSystem =
          {
            lib,
            pkgs,
            system,
            ...
          }:
          {
            # Apps (`nix run`)
            apps = import ./apps { inherit pkgs; };

            # Formatter (`nix fmt`)
            formatter = pkgs.nixfmt-tree;
          };

        flake = {
          inherit (inputs) self;

          # Templates
          templates = import ./templates {
            inherit inputs;
          };
        };
      }
    );

  inputs = {
    # Nixpkgs
    nixpkgs = {
      url = "github:nixos/nixpkgs/nixos-unstable";
    };

    determinate = {
      url = "https://flakehub.com/f/DeterminateSystems/determinate/*";
    };

    nixos-generators = {
      url = "github:nix-community/nixos-generators";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    flake-parts = {
      url = "github:hercules-ci/flake-parts";
      inputs.nixpkgs-lib.follows = "nixpkgs";
    };

    dream2nix = {
      url = "github:nix-community/dream2nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Nix on Droid
    nix-on-droid = {
      url = "github:t184256/nix-on-droid";
      # url = "github:t184256/nix-on-droid/master";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.home-manager.follows = "home-manager";
    };

    # Nix Darwin
    nix-darwin = {
      url = "github:nix-darwin/nix-darwin";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # NixOS-WSL
    nixos-wsl = {
      url = "github:nix-community/NixOS-WSL/main";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    mac-app-util = {
      url = "github:hraban/mac-app-util";
      inputs.cl-nix-lite.url = "github:r4v3n6101/cl-nix-lite/url-fix";
    };

    # Home Manager
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    flake-compat = {
      url = "github:inclyc/flake-compat";
      flake = false;
    };

    impermanence = {
      url = "github:nix-community/impermanence";
    };

    nix-topology = {
      url = "github:oddlama/nix-topology";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nix-lib-net = {
      url = "github:reo101/nix-lib-net";
    };

    yants = {
      url = "git+https://code.tvl.fyi/depot.git:/nix/yants.git";
      flake = false;
    };

    infuse = {
      url = "git+https://codeberg.org/amjoseph/infuse.nix";
      flake = false;
    };

    nix-monitored = {
      url = "github:ners/nix-monitored";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    jovian-nixos = {
      url = "github:Jovian-Experiments/Jovian-NixOS";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    deploy-rs = {
      # url = "github:serokell/deploy-rs";
      url = "github:szlend/deploy-rs/fix-show-derivation-parsing";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    agenix = {
      url = "github:ryantm/agenix";
      inputs = {
        nixpkgs.follows = "nixpkgs";
        darwin.follows = "nix-darwin";
        home-manager.follows = "home-manager";
      };
    };

    ragenix = {
      url = "github:yaxitech/ragenix";
      inputs.agenix.follows = "agenix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    agenix-rekey = {
      url = "github:oddlama/agenix-rekey";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    agenix-template.url = "github:jhillyerd/agenix-template/1.0.0";

    nix-jetbrains-plugins = {
      url = "github:theCapypara/nix-jetbrains-plugins";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Nix User Repository
    nur = {
      url = "github:nix-community/NUR";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    spicetify-nix = {
      url = "github:the-argus/spicetify-nix";
    };

    hardware = {
      url = "github:nixos/nixos-hardware";
    };

    nix-colors = {
      url = "github:misterio77/nix-colors";
    };

    neovim-nightly-overlay = {
      url = "github:nix-community/neovim-nightly-overlay";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    zig-overlay = {
      url = "github:mitchellh/zig-overlay";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    zls-overlay = {
      url = "github:zigtools/zls";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.zig-overlay.follows = "zig-overlay";
    };

    wired = {
      url = "github:Toqozz/wired-notify";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    ags.url = "github:Aylur/ags/v1";
    aagl.url = "github:ezKEa/aagl-gtk-on-nix";
    aagl.inputs.nixpkgs.follows = "nixpkgs";
    superfile.url = "github:yorukot/superfile";
    stylix.url = "github:danth/stylix";
    swww.url = "github:LGFae/swww";
    nixvim = {
      url = "github:nix-community/nixvim";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    hyprland = {
      url = "github:hyprwm/Hyprland";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    hyprland-plugins = {
      url = "github:hyprwm/hyprland-plugins";
      inputs.hyprland.follows = "hyprland";
      inputs.nixpkgs.follows = "hyprland";
    };

    pkl-flake = {
      url = "github:capslock/pkl-flake";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    vscode-server = {
      url = "github:nix-community/nixos-vscode-server";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nix-vscode-extensions = {
      url = "github:nix-community/nix-vscode-extensions";
      # inputs.nixpkgs.follows = "nixpkgs";  # appears to be broken as of 24/10/25
    };

    waveforms = {
      url = "github:liff/waveforms-flake";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    j-link = {
      url = "github:liff/j-link-flake";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    affinity = {
      url = "github:mrshmllow/affinity-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    direnv-instant = {
      url = "github:Mic92/direnv-instant";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    llm-agents = {
      url = "github:numtide/llm-agents.nix";
      # inputs.nixpkgs.follows = "nixpkgs";
    };

    nvf = {
      url = "github:notashelf/nvf";
      # inputs.nixpkgs.follows = "nixpkgs";
    };

    nix-homebrew = {
      url = "github:zhaofengli/nix-homebrew";
    };
    homebrew-core = {
      url = "github:homebrew/homebrew-core";
      flake = false;
    };
    homebrew-cask = {
      url = "github:homebrew/homebrew-cask";
      flake = false;
    };

    colorshell = {
      url = "github:conroy-cheers/colorshell/ryo";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    corncheese-server = {
      url = "git+https://github.com/conroy-cheers/corncheese-server-config";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.ragenix.follows = "ragenix";
    };
  };

  nixConfig = {
    extra-substituters = [ "https://cache.numtide.com" ];
    extra-trusted-public-keys = [ "niks3.numtide.com-1:DTx8wZduET09hRmMtKdQDxNNthLQETkc/yaX7M4qK0g=" ];
  };
}
