# mcp (Model Context Protocol Python SDK) 1.x, kept only so mcp-proxy has a
# dependency it can import.
#
# mcp-proxy 0.13.0 -- the latest release, and still the latest upstream commit
# -- declares `mcp>=1.27.1,<2` and uses the 1.x API throughout: the
# `Server.request_handlers[<RequestType>]` registry, `types.ServerResult`,
# `request_ctx`, `streamablehttp_client`, `McpError` and
# `mcp.shared.memory.create_connected_server_and_client_session`. mcp 2.x
# removed or renamed every one of those, so the pin is real, not conservatism:
# relaxing the dependency check builds a package that fails on import.
#
# This is the newest 1.x (1.30.0, the last before v2). nixpkgs solved the same
# breakage upstream by adding a separate mcp_1 and building mcp-proxy against
# it (NixOS/nixpkgs#578877); the nixpkgs pin in flake.lock predates that, so
# the package lives here until the pin catches up -- at which point this file
# and the override in pkgs/default.nix both go away.
#
# Do not collapse this into python3Packages.mcp: nixpkgs' own mcp consumers
# expect the 2.x API.
{
  lib,
  stdenv,
  buildPythonPackage,
  fetchFromGitHub,

  # build-system
  hatchling,
  uv-dynamic-versioning,

  # dependencies
  anyio,
  httpx,
  httpx-sse,
  jsonschema,
  pydantic,
  pydantic-settings,
  pyjwt,
  python-multipart,
  sse-starlette,
  starlette,
  typing-extensions,
  typing-inspection,
  uvicorn,

  # optional-dependencies
  # cli
  python-dotenv,
  typer,
  # rich
  rich,
  # ws
  websockets,

  # tests
  dirty-equals,
  inline-snapshot,
  pytest-asyncio,
  pytest-examples,
  pytest-xdist,
  pytestCheckHook,
  requests,
}:

buildPythonPackage (finalAttrs: {
  pname = "mcp";
  version = "1.30.0";
  pyproject = true;
  __structuredAttrs = true;

  src = fetchFromGitHub {
    owner = "modelcontextprotocol";
    repo = "python-sdk";
    tag = "v${finalAttrs.version}";
    hash = "sha256-EkmTqsK+vBJcURuwFkhtNJMFgtzgw/7Cd+Fpav4P/ko=";
  };

  # time.sleep(0.1) feels a bit optimistic and it has been flaky whilst
  # testing this on macOS under load.
  postPatch = lib.optionalString stdenv.buildPlatform.isDarwin ''
    substituteInPlace tests/client/test_stdio.py \
      --replace-fail "time.sleep(0.1)" "time.sleep(1)"
  '';

  build-system = [
    hatchling
    uv-dynamic-versioning
  ];

  dependencies = [
    anyio
    httpx
    httpx-sse
    jsonschema
    pydantic
    pydantic-settings
    pyjwt
    python-multipart
    sse-starlette
    starlette
    typing-extensions
    typing-inspection
    uvicorn
  ];

  optional-dependencies = {
    cli = [
      python-dotenv
      typer
    ];
    rich = [
      rich
    ];
    ws = [
      websockets
    ];
  };

  pythonImportsCheck = [ "mcp" ];

  nativeCheckInputs = [
    dirty-equals
    inline-snapshot
    pytest-asyncio
    pytest-examples
    pytest-xdist
    pytestCheckHook
    requests
  ]
  ++ lib.flatten (builtins.attrValues finalAttrs.passthru.optional-dependencies);

  pytestFlags = [
    "-Wignore::pytest.PytestRemovedIn10Warning"
  ];

  disabledTests = [
    # attempts to run the package manager uv
    "test_command_execution"

    # ExceptionGroup: unhandled errors in a TaskGroup (1 sub-exception)
    "test_lifespan_cleanup_executed"

    # AssertionError: Child process should be writing
    "test_basic_child_process_cleanup"

    # AssertionError: parent process should be writing
    "test_nested_process_tree"

    # AssertionError: Child should be writing
    "test_early_parent_exit"

    # pytest.PytestUnraisableExceptionWarning: Exception ignored in: <_io.FileIO ...
    "test_list_tools_returns_all_tools"

    # AssertionError: Server startup marker not created
    "test_stdin_close_triggers_cleanup"

    # pytest.PytestUnraisableExceptionWarning: Exception ignored in: <function St..
    "test_resource_template_client_interaction"

    # Flaky: https://github.com/modelcontextprotocol/python-sdk/pull/1171
    "test_notification_validation_error"

    # Flaky: httpx.ConnectError: All connection attempts failed
    "test_sse_security_"
    "test_streamable_http_"
    "test_streamablehttp_"

    # This just feels a bit optimistic...
    #    	AssertionError: assert 0.0733884589999434 < (3 * 0.01)
    "test_messages_are_executed_concurrently"

    # ExceptionGroup: unhandled errors in a TaskGroup (1 sub-exception)
    "test_tool_progress"
  ];

  __darwinAllowLocalNetworking = true;

  meta = {
    changelog = "https://github.com/modelcontextprotocol/python-sdk/releases/tag/${finalAttrs.src.tag}";
    description = "Official Python SDK for Model Context Protocol servers and clients";
    homepage = "https://github.com/modelcontextprotocol/python-sdk";
    license = lib.licenses.mit;
    maintainers = with lib.maintainers; [ bryanhonof ];
  };
})
