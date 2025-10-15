{
  lib,
  config,
  ...
}:
let
  cfg = config.corncheese.wm.audio;
in
{
  config = lib.mkIf cfg.enable {
    security.rtkit.enable = true;
    services.pipewire = lib.mkMerge [
      {
        enable = true;
        alsa = {
          enable = true;
          support32Bit = true;
        };
        pulse = {
          enable = true;
        };
        jack = {
          enable = true;
        };
        extraConfig = {
          pipewire."92-low-latency" = {
            "context.properties" = {
              "default.clock.rate" = 48000;
              "default.clock.quantum" = 256;
              "default.clock.min-quantum" = 32;
              "default.clock.max-quantum" = 4096;
            };
          };
        };
      }
      (lib.mkIf cfg.equalizer.enable {
        wireplumber.extraConfig = {
          "motu-autoeq" = {
            "node.software-dsp.rules" = [
              {
                matches = [
                  { "node.name" = "alsa_output.usb-MOTU_M2_M20000055223-00.HiFi__Line1__sink"; }
                ];
                actions = {
                  create-filter = {
                    filter-graph = {
                      "node.description" = "MOTU M2";
                      "media.name" = "MOTU M2";
                      "filter.graph" = {
                        "nodes" = [
                          {
                            type = "builtin";
                            name = "eq";
                            label = "param_eq";
                            config = {
                              "filename" = ./HIFIMAN-Ananda-Stealth-ParametricEq.txt;
                            };
                          }
                        ];
                      };
                      "audio.channels" = 2;
                      "audio.position" = [
                        "FL"
                        "FR"
                      ];
                      "capture.props" = {
                        "node.name" = "effect_input.eq";
                        "media.class" = "Audio/Sink";
                      };
                      "playback.props" = {
                        "node.name" = "effect_output.eq";
                        "node.passive" = true;
                      };
                    };
                    hide-parent = true;
                  };
                };
              }
            ];
            "wireplumber.profiles" = {
              main = {
                "node.software-dsp" = "required";
              };
            };
          };
        };
      })
    ];
  };
}
