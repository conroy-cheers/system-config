{ inputs, ... }:

final: prev: {
  lib = prev.lib // {
    maintainers = prev.lib.maintainers // {
      conroy-cheers = {
        name = "Conroy Cheers";
        email = "conroy@corncheese.org";
        github = "conroy-cheers";
        githubId = "9310662";
        keys = [
          {
            # fingerprint = "8A29 0250 C775 7813 1DD1  DC57 7275 0ABE E181 26D0";
          }
        ];
      };
    };
  };

  nix = inputs.determinate.inputs.nix.packages.${prev.stdenv.hostPlatform.system}.default;

  nix-monitored = inputs.nix-monitored.packages.${prev.stdenv.hostPlatform.system}.default.override {
    nix = final.nix;
    nix-output-monitor = final.nix-output-monitor;
  };

  klipper-firmware = prev.klipper-firmware.overrideAttrs (oldAttrs: {
    postPatch = (oldAttrs.postPatch or "") + ''
      echo "${oldAttrs.version}-NixOS" > klippy/.version
      python3 - <<'PY'
      from pathlib import Path

      path = Path("scripts/buildcommands.py")
      text = path.read_text()
      old = """    if not version:
              cleanbuild = False
              version = file_version()
              if not version:
                  version = "?"
      """
      new = """    if not version:
              version = file_version()
              if not version:
                  version = "?"
                  cleanbuild = False
      """
      if old not in text:
          raise RuntimeError("Klipper buildcommands.py version fallback changed")
      path.write_text(text.replace(old, new))
      PY
    '';
  });

  nixVersions = prev.nixVersions // {
    monitored = final.lib.concatMapAttrs (
      version: package:
      let
        eval = builtins.tryEval package;
      in
      final.lib.optionalAttrs
        (
          eval.success
          && final.lib.and (final.lib.all (prefix: !final.lib.hasPrefix prefix version)
            # TODO: smarter filtering of deprecated and non-packages
            [
              "nix_2_4"
              "nix_2_5"
              "nix_2_6"
              "nix_2_7"
              "nix_2_8"
              "nix_2_9"
              "nix_2_10"
              "nix_2_11"
              "nix_2_12"
              "nix_2_13"
              "nix_2_14"
              "nix_2_15"
              "nix_2_16"
              "nix_2_17"
              "nix_2_18"
              "nix_2_19"
              "nix_2_20"
              "nix_2_21"
              "nix_2_22"
              "nix_2_23"
              "unstable"
            ]
          ) (final.lib.isDerivation eval.value)
        )
        {
          # NOTE: `lib.getBin` is needed, otherwise the `-dev` output is chosen
          "${version}" = final.lib.getBin (
            inputs.nix-monitored.packages.${final.stdenv.hostPlatform.system}.default.override {
              nix = eval.value;
              nix-output-monitor = prev.nix-output-monitor;
            }
          );
        }
    ) prev.nixVersions;
  };

  river = prev.river.overrideAttrs (oldAttrs: rec {
    xwaylandSupport = true;
  });

  discord = prev.discord.override {
    withOpenASAR = true;
    withVencord = true;
  };

  prismlauncher = prev.prismlauncher.overrideAttrs (oldAttrs: {
    patches = (oldAttrs.patches or [ ]) ++ [ ./offline-mode-prism-launcher.diff ];
  });

  git-spice = prev.git-spice.overrideAttrs (oldAttrs: {
    # Route PR base-branch updates through the REST API; GitHub's GraphQL
    # updatePullRequest mutation intermittently 502s when changing the base.
    patches = (oldAttrs.patches or [ ]) ++ [ ./git-spice-rest-base.diff ];
  });

  openrgb = prev.openrgb.overrideAttrs (oldAttrs: {
    version = "1.0rc2-unstable-2026-05-23";

    src = final.fetchFromGitHub {
      owner = "CalcProgrammer1";
      repo = "OpenRGB";
      rev = "f67030fcc7b9bf0688a955821a4ad9ac7b3b238e";
      hash = "sha256-RQw3tdIZFOZVK3YMCa99b+8nwMBIfYTvQKaCvq24Hi0=";
    };

    patches = final.lib.filter (
      patch: !(final.lib.hasInfix "Install-systemd-service-under-PREFIX.patch" (toString patch))
    ) (oldAttrs.patches or [ ]);
  });
}
