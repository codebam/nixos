{
  lib,
  python3Packages,
  fetchPypi,
  opensandbox,
}:

let
  # Upstream pins rich <14 and nixpkgs tracks 15. The CLI only uses the
  # stable Console/Table/Panel/Status/Text API, but keep the declared range
  # rather than bypassing the runtime dependency check.
  rich = python3Packages.rich.overridePythonAttrs (_: rec {
    version = "13.9.4";
    src = fetchPypi {
      pname = "rich";
      inherit version;
      hash = "sha256-Q5WUl4pJoJUwz/frxLXHED71e69I1eoxhPIdmivvoJg=";
    };
    # The sdist's pyproject declares testpaths that are not shipped.
    doCheck = false;
  });
in
python3Packages.buildPythonApplication rec {
  pname = "opensandbox-cli";
  version = "0.1.1";
  pyproject = true;

  # PyPI's sdist filename uses the normalized distribution name; fetchPypi
  # builds the URL from its own pname, which is not the same as the CLI
  # derivation name.
  src = fetchPypi {
    pname = "opensandbox_cli";
    inherit version;
    hash = "sha256-7CqiAO5wWeM/P4dokPn9VCergYb4eYl0Jnxgc3+Ish8=";
  };

  env.SETUPTOOLS_SCM_PRETEND_VERSION = version;

  build-system = [
    python3Packages.hatchling
    python3Packages.hatch-vcs
  ];

  dependencies = [
    python3Packages.click
    python3Packages.pyyaml
    opensandbox
    rich
  ];

  # The CLI is exercised by the wrapper smoke test in the host build; the
  # upstream suite needs a live server.
  doCheck = false;

  pythonImportsCheck = [ "opensandbox_cli" ];

  meta = {
    description = "OpenSandbox CLI for managing sandbox lifecycles";
    homepage = "https://github.com/opensandbox-group/OpenSandbox";
    license = lib.licenses.asl20;
    mainProgram = "osb";
    platforms = lib.platforms.linux;
  };
}
