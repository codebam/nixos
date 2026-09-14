{
  lib,
  python3Packages,
  fetchPypi,
  opensandbox,
}:

python3Packages.buildPythonApplication rec {
  pname = "opensandbox-mcp";
  version = "0.1.1";
  pyproject = true;

  # PyPI's sdist filename uses the normalized distribution name; fetchPypi
  # builds the URL from its own pname, which is not the same as the CLI
  # derivation name.
  src = fetchPypi {
    pname = "opensandbox_mcp";
    inherit version;
    hash = "sha256-VAjE34BKzew7/UeSi1jNPoHBnNN4bXscObIrxLi6qr4=";
  };

  env.SETUPTOOLS_SCM_PRETEND_VERSION = version;

  build-system = [
    python3Packages.hatchling
    python3Packages.hatch-vcs
  ];

  # The PyPI release declares only `mcp[cli]`; nixpkgs' mcp does not carry
  # the optional CLI extras, and this server is MCP 1.x's FastMCP API.
  dependencies = with python3Packages; [
    mcp
    opensandbox
    python-dotenv
    rich
    typer
  ];

  doCheck = false;

  pythonImportsCheck = [ "opensandbox_mcp" ];

  meta = {
    description = "OpenSandbox MCP server for sandbox lifecycle, command, and file tools";
    homepage = "https://github.com/opensandbox-group/OpenSandbox";
    license = lib.licenses.asl20;
    mainProgram = "opensandbox-mcp";
    platforms = lib.platforms.linux;
  };
}
