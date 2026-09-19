# Nixpkgs' playwright-mcp wraps the all-browser Playwright link farm, and its
# `playwright-test` dependency bakes that farm into a wrapper. This host drives
# Chromium; the nixpkgs checkout this was tested against also cannot build its
# WebKit bundle (`playwright-webkit` fails autoPatchelf on a missing
# libmanette-0.2.so.0). Rebuild the package against a Chromium +
# chromium-headless-shell farm instead - `--headless` in home/agents.nix is
# the runtime half of that choice.
{
  base,
  playwright-driver,
  playwright-test,
}:
let
  fullBrowsers = playwright-driver.browsers;
  browsers = playwright-driver.selectBrowsers {
    withWebkit = false;
    withFirefox = false;
  };
  oldInstallPhase = playwright-test.installPhase;
  # `replaceStrings` alone would keep the old farm's string context, and so
  # its derivation input, attached to the new value. Rebuild the context
  # instead: keep the nodejs/Playwright references, drop the all-browser farm,
  # and attach the Chromium farm.
  newInstallPhase =
    builtins.appendContext
      (builtins.replaceStrings
        [ (builtins.unsafeDiscardStringContext "${fullBrowsers}") ]
        [ (builtins.unsafeDiscardStringContext "${browsers}") ]
        (builtins.unsafeDiscardStringContext oldInstallPhase)
      )
      (
        (builtins.removeAttrs (builtins.getContext oldInstallPhase) [
          (builtins.unsafeDiscardStringContext fullBrowsers.drvPath)
        ])
        // (builtins.getContext "${browsers}")
      );
  playwright-test-chromium = playwright-test.overrideAttrs (_old: {
    installPhase = newInstallPhase;
  });
in
base.override {
  playwright-test = playwright-test-chromium;
  playwright-driver = playwright-driver // {
    inherit browsers;
  };
}
