{
  lib,
  python3Packages,
  fetchPypi,
}:

python3Packages.buildPythonPackage rec {
  pname = "opensandbox";
  version = "0.1.16";
  pyproject = true;

  src = fetchPypi {
    inherit pname version;
    hash = "sha256-uSU6WOufAb/1IvzPMXdGtGSAWJPFamrUR+DxzH83J2w=";
  };

  # The PyPI sdist carries no .git, and hatch-vcs derives the version from
  # tags; pretend the tag is present instead of patching pyproject.toml.
  env.SETUPTOOLS_SCM_PRETEND_VERSION = version;

  build-system = [
    python3Packages.hatchling
    python3Packages.hatch-vcs
  ];

  dependencies = with python3Packages; [
    attrs
    httpcore
    httpx
    httpx-sse
    pydantic
    python-dateutil
  ];

  pythonImportsCheck = [ "opensandbox" ];

  # Upstream's test suite talks to a live OpenSandbox server.
  doCheck = false;

  meta = {
    description = "OpenSandbox Python SDK for isolated execution environments";
    homepage = "https://github.com/opensandbox-group/OpenSandbox";
    license = lib.licenses.asl20;
    mainProgram = "opensandbox";
    platforms = lib.platforms.linux;
  };
}
