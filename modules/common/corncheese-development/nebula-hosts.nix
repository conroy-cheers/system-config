{
  # Keep these stable: they are embedded in the signed host certificates.
  # Each non-null SSH entry also drives the client alias and the user's authorized_keys.
  snow = {
    address = "10.42.42.1";
    lighthouse.endpoints = [
      "10.1.1.120:4242"
      "home.conroycheers.me:4242"
    ];
    ssh = {
      user = "conroy";
      identity = "conroy-home";
    };
  };
  hail = {
    address = "10.42.42.10";
    lighthouse.endpoints = [
      "10.1.1.121:4242"
      "home.conroycheers.me:4243"
    ];
    ssh = {
      user = "conroy";
      identity = "conroy-home";
    };
  };
  sleet = {
    address = "10.42.42.2";
    ssh = {
      user = "conroy";
      identity = "conroy-home";
    };
  };
  brick = {
    address = "10.42.42.3";
    ssh = {
      user = "conroy";
      identity = "conroy-home";
    };
  };
  kombu = {
    address = "10.42.42.4";
    ssh = {
      user = "conroy";
      identity = "conroy-work";
    };
  };
  labtop = {
    address = "10.42.42.5";
    ssh = {
      user = "conroy";
      identity = "conroy-work";
    };
  };
  panda = {
    address = "10.42.42.6";
    ssh = {
      user = "conroy";
      identity = "conroy-home";
    };
  };
  shrimpus = {
    address = "10.42.42.7";
    ssh = null;
  };
  wsl-brick = {
    address = "10.42.42.8";
    ssh = {
      user = "conroy";
      identity = "conroy-work";
    };
  };
  kiki = {
    address = "10.42.42.9";
    ssh = {
      user = "conroy";
      identity = "conroy-work";
    };
  };
}
