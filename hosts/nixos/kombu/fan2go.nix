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
          id = "intake_gpu";
          hwmon = {
            platform = "it8613-isa-*";
            rpmChannel = 3;
          };
          curve = "intake_gpu_curve";
        }
        {
          id = "intake_cpu";
          hwmon = {
            platform = "it8613-isa-*";
            rpmChannel = 2;
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
        {
          id = "gpu_temp";
          nvidia = {
            device = "nvidia-10DE25B8-0100";
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
              { "95" = 255; }
            ];
          };
        }
        {
          id = "intake_gpu_curve";
          linear = {
            sensor = "gpu_temp";
            steps = [
              { "30" = 0; }
              { "40" = 50; }
              { "90" = 255; }
            ];
          };
        }
      ];
    };
  };
}
