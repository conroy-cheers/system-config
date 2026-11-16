{ config, ... }:
let
  endpoint = config.corncheese-server._meta.services.nightingale.endpoint;
in
{
  virtualisation.oci-containers.containers.nightingale = {
    # Upstream 1.4.1 CPU image, pinned to its multi-architecture manifest.
    # The P100 needs separate validation before enabling upstream's CUDA image.
    image = "docker.io/razzaru/nightingale@sha256:673db380fe322a4f2415a7720e967bc8509c987faead0a89c69b2fd834f0fd18";
    autoStart = true;
    environment = {
      NIGHTINGALE_BIND = "${endpoint.bindAddress}:${toString endpoint.port}";
      NIGHTINGALE_DATA_PATH = "/data";
      NIGHTINGALE_LIBRARY_PATH = "/songs";
      NIGHTINGALE_REMOTE_URL = "https://nightingale.corncheese.org";
      HOME = "/data";
    };
    volumes = [
      # A named volume preserves the image's non-root /data ownership. Sleet
      # persists all of /var/lib, including the OCI backend's volume storage.
      "nightingale-data:/data"
      "/mnt/media/Downloads/torrent/complete/ops:/songs/ops:ro"
      "/mnt/media/Downloads/torrent/complete/red:/songs/red:ro"
    ];
    # Use host networking so the topology's source-restricted host firewall
    # applies. Published container ports can otherwise bypass that firewall.
    extraOptions = [
      "--network=host"
      "--cap-drop=ALL"
      "--security-opt=no-new-privileges"
    ];
  };

  systemd.services."${config.virtualisation.oci-containers.backend}-nightingale".unitConfig.RequiresMountsFor =
    [
      "/var/lib"
      "/mnt/media/Downloads/torrent/complete/ops"
      "/mnt/media/Downloads/torrent/complete/red"
    ];
}
