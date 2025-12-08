{
  fetchFromGitHub,
  rustPlatform,
}:
rustPlatform.buildRustPackage rec {
  pname = "sketchybar-system-stats";
  version = "0.8.0";

  src = fetchFromGitHub {
    owner = "joncrangle";
    repo = "sketchybar-system-stats";
    tag = "${version}";
    hash = "sha256-AZuZ4jgv/OWQ+e7TD9y8spzHf0hxuC3kCupv/J+oEFg=";
  };

  cargoHash = "sha256-0sOjrYNUYw4YBwSxUM+Y2K9bB0rW6+oooqrZ9rgMrWM=";
}
