{
  fetchFromGitHub,
  direnv,
}:
direnv.overrideAttrs {
  version = "unstable-2026-01-08";
  src = fetchFromGitHub {
    owner = "direnv";
    repo = "direnv";
    rev = "02040c767ba64b32a9b5ef2d8d2e00983d6bc958";
    hash = "sha256-F2n1DpJsQK1A1KY9sURBqE/8i9JaJlKy3MjVwTnwWUI=";
  };
  vendorHash = "sha256-5YhPscoEetSOSPv3F9e24oqPoekNKWBic/G+BCnfRhg=";
}
