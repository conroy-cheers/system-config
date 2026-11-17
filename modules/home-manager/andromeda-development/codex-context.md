# Nix builds
- The system has default remote Nix builders configured. These may sometimes be unavailable;
  if there is another machine (including the local machine) with the same arch/capabilities
  available, then this is not a problem.
- These default remote Nix builders are highly performant, so avoid overriding the config to
  use other builders, even if repo documentation suggests doing so.