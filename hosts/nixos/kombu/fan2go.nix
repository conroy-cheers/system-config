{
  pkgs,
  ...
}:
let
  fan2go' = pkgs.fan2go.override { enableNVML = pkgs.config.cudaSupport; };
in
{
  environment.systemPackages = [
    fan2go'
  ];

  services.fan2go = {
    enable = true;
    package = fan2go';
    settings = {
      fans = [
        {
          id = "exhaust_top";
          hwmon = {
            platform = "it8613-isa-*";
            rpmChannel = 2;
          };
          curve = "exhaust_top_curve";
        }
        {
          id = "intake_cpu";
          hwmon = {
            platform = "it8613-isa-*";
            rpmChannel = 3;
          };
          curve = "intake_cpu_curve";
        }
      ];
      sensors = [
        {
          id = "cpu_package_temp";
          hwmon = {
            platform = "k10temp-pci-*";
            index = 1;
          };
        }
      ];
      curves = [
        {
          id = "intake_cpu_curve";
          linear = {
            sensor = "cpu_package_temp";
            steps = [
              { "30" = 0; }
              { "40" = 50; }
              { "85" = 255; }
            ];
          };
        }
        {
          id = "exhaust_top_curve";
          function = {
            type = "sum";
            curves = [
              "intake_cpu_curve"
            ];
          };
        }
      ];
    };
  };
}
