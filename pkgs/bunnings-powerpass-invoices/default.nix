{
  chromium,
  lib,
  playwright-driver,
  python3,
  writeShellApplication,
}:

let
  python = python3.withPackages (ps: [
    (import ../oauth-mcp-gateway/fastmcp.nix { python3Packages = ps; })
    ps.playwright
  ]);
in
writeShellApplication {
  name = "bunnings-powerpass-invoices";

  text = ''
    export PLAYWRIGHT_BROWSERS_PATH=${playwright-driver.browsers-chromium}
    export POWERPASS_CHROMIUM=${lib.getExe chromium}
    export POWERPASS_SELF_COMMAND="$0"
    exec ${python}/bin/python ${./bunnings-powerpass-invoices.py} "$@"
  '';

  meta = {
    description = "Download Bunnings PowerPass tax invoices with an authenticated Playwright session";
    license = lib.licenses.mit;
    mainProgram = "bunnings-powerpass-invoices";
    # Playwright's Chromium downloads are only available for 64-bit Linux.
    platforms = [
      "x86_64-linux"
      "aarch64-linux"
    ];
  };
}
