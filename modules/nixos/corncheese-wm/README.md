# Window manager

## LibrePods

NixOS desktops enable `programs.librepods` and grant normal users access through
the `librepods` group. A systemd user service starts LibrePods hidden with the
graphical session and stops it when the session ends. It uses the NixOS
capability wrapper for Bluetooth access.

After first enabling LibrePods, log out and back in to pick up the new group
membership. No manual app launch is required. Use `systemctl --user status
librepods` to check the background service; launch LibrePods from the application
menu to open its settings.

## Sunshine

Enable desktop streaming in a NixOS host configuration:

```nix
corncheese.wm = {
  enable = true;
  sunshine = {
    enable = true;
    users = [ "conroy" ];
  };
};
```

Sunshine is part of `corncheese-wm`. Both `corncheese.wm.enable` and
`corncheese.wm.sunshine.enable` must be enabled for its configuration to apply.

Sunshine starts with the graphical session and exposes a `Desktop` application.
The listed users receive `uinput` access for remote input. A running graphical
session is required; capture and encoder selection use Sunshine's automatic
defaults. The tray and UPnP are disabled by default.

Use the upstream `services.sunshine` options for the package, capture settings,
applications, autostart, and firewall access. For example, a LAN host can set
`services.sunshine.openFirewall = true;`. Host-specific GPU environment variables
belong in `systemd.user.services.sunshine.environment`.

For access through an existing Nebula network:

```nix
corncheese.wm.sunshine = {
  enable = true;
  users = [ "conroy" ];
  nebula = {
    network = "corncheese";
    allowedHosts = [ "kombu" ];
  };
};

services.sunshine.settings.bind_address =
  config.corncheese.development.nebula.address;
```

This adds Sunshine's TCP and UDP rules for the listed certificate host names,
including the pairing/admin web interface. Rules follow
`services.sunshine.settings.port` when its base port changes. Nebula must already
be enabled, and the listening address is configured separately as shown above.
