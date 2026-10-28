# pm's installed-state rows for the tools nix itself provides.
#
# `hermes` ships its own package manager (pm): a tool store under
# $HERMES_HOME/tools plus `facts.json`, the record of what is installed there.
# `pm.check()` runs at every launch and compares each required package in
# pm/lock.json against those facts, printing
#
#   install out of sync (ffmpeg: not installed or outdated; node: ...;
#   npm: ...; ripgrep: ...) — this <steward>-managed install must rebuild
#   the artifact to fix
#
# for anything it cannot find.
#
# A nix install never uses that store for those four tools: node (with the
# pinned npm), ripgrep and ffmpeg come from the wrapper's PATH
# (nix/hermes-agent.nix `runtimeDeps` upstream). pm only stays quiet because
# `drift()` returns early when facts.json does not exist ("pm only vouches for
# what it installed") -- and the first lazily-installed package creates it.
# Chromium for the browser tool lands in that store, so from then on every
# launch reports the four nix-provided tools as missing and tells you to
# rebuild an artifact that already contains them.
#
# The answer pm expects is data, not a patch: one store entry per tool (a
# symlink to the exact nix store path the wrapper already puts on PATH, so the
# closure does not grow) plus its facts row keyed to the identity pm/lock.json
# pins -- target plus the artifact sha256 list, which is what `installed()`
# compares. Merged into facts.json at activation, beside whatever pm installed
# lazily, because the file is shared and pm read-modify-writes it itself.
#
# Versions and hashes come from the lockfile passed in, so a hermes bump moves
# these rows with it; entry names follow pm's own `${name}-${version}-${target}`
# convention. `tools` below is the complete set of required (non-optional,
# non-internal) lockfile packages with an artifact for this system — if a bump
# adds one, add it here or the warning comes back for that name.
{
  pkgs,
  lib,
  # pm/lock.json from the hermes-agent input: the one pin authority.
  lockfile,
  # HERMES_HOME: pm's store is $HERMES_HOME/tools.
  hermesHome,
  # The pinned node with the pinned npm wrapped onto it (hermesNpmLib.nodejs),
  # and the pm artifacts the wrapper puts on PATH.
  node,
  ripgrep,
  ffmpeg,
}:

let
  lock = builtins.fromJSON (builtins.readFile lockfile);

  # Same spelling pm uses for its store entries (pm/store.py current_target):
  # <os>-<arch>, with musl and bionic variants only where nix-ld is absent.
  os =
    if pkgs.stdenv.hostPlatform.isDarwin then
      "darwin"
    else if pkgs.stdenv.hostPlatform.isWindows then
      "win32"
    else
      "linux";
  arch = if pkgs.stdenv.hostPlatform.isAarch64 then "arm64" else "x64";
  target = "${os}-${arch}";

  # A pin is one artifact per target, or a single `any` row (npm).
  artifactsOf =
    name:
    let
      pins = lock.packages.${name}.artifacts or { };
      found = pins.${target} or pins.any or null;
      listed = if builtins.isList found then found else [ found ];
    in
    if found == null then null else map (a: a.sha256) listed;

  # name -> where its binary lives. `sub` is the binary's directory relative to
  # the store entry, because ripgrep's artifact carries `rg` at the root while
  # the others use bin/ — pm records exactly that as the package's PATH.
  tools = {
    node = {
      store = node;
      sub = "bin";
    };
    npm = {
      store = node;
      sub = "bin";
    };
    ripgrep = {
      store = ripgrep;
      sub = "";
    };
    ffmpeg = {
      store = ffmpeg;
      sub = "bin";
    };
  };

  entryName = name: "${name}-${lock.packages.${name}.version}-${target}";

  factFor = name: tool: {
    entry = entryName name;
    version = lock.packages.${name}.version;
    inherit target;
    artifacts = artifactsOf name;
    env.PATH = [
      ("{{store}}/${entryName name}" + lib.optionalString (tool.sub != "") "/${tool.sub}")
    ];
  };

  unpinned = lib.filter (name: artifactsOf name == null) (builtins.attrNames tools);

  facts =
    if unpinned != [ ] then
      throw ''
        hermes-pm-facts: pm/lock.json pins no ${target} artifact for ${lib.concatStringsSep ", " unpinned}.
        pm cannot be told these are installed on this system; drop them from `tools` in
        home/hermes-pm-facts.nix or pin a system the lockfile covers.''
    else
      {
        schema = 1;
        packages = lib.mapAttrs factFor tools;
      };

  factsFile = pkgs.writeText "hermes-pm-facts.json" (builtins.toJSON facts);
  # The seeder itself. A derivation, not an inline activation snippet, for two
  # reasons: `runtimeInputs` gives it jq/find/coreutils without the activation
  # text carrying their store paths, and the script is checked at build time.
  seeder = pkgs.writeShellApplication {
    name = "hermes-pm-facts";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.findutils
      pkgs.jq
    ];
    text = ''
      store="''${1:?usage: hermes-pm-facts <pm-store>}"

      if [ -n "''${DRY_RUN_CMD:-}" ]; then
        echo "would record pm facts for node, npm, ripgrep and ffmpeg in $store"
        exit 0
      fi

      mkdir -p "$store"

      # Symlinks a previous generation left behind (a version bump renames the
      # entry). Real pm installs are directories and are never touched.
      for pkg in node npm ripgrep ffmpeg; do
        find "$store" -maxdepth 1 -type l -name "$pkg-*" -delete
      done

      link() {
        if [ -e "$store/$2" ] && [ ! -L "$store/$2" ]; then
          echo "pm-facts: $store/$2 is not a symlink, leaving it alone" >&2
          return 0
        fi
        ln -sfn "$1" "$store/$2"
      }

      link ${node} ${entryName "node"}
      link ${node} ${entryName "npm"}
      link ${ripgrep} ${entryName "ripgrep"}
      link ${ffmpeg} ${entryName "ffmpeg"}

      facts="$store/facts.json"
      tmp="$facts.new.$$"
      if [ -f "$facts" ] && jq empty "$facts" >/dev/null 2>&1; then
        # pm's own rows (a lazily-installed chromium, a venv stamp) stay; ours
        # replace whatever a previous generation wrote for these four names.
        jq -s '
          .[0] as $cur | .[1] as $new
          | { schema: 1,
              packages: ((($cur | objects | .packages) // {}) + $new.packages) }
        ' "$facts" ${factsFile} > "$tmp"
      else
        if [ -f "$facts" ]; then
          # Never lose a row, even an unreadable one: keep it, write the seed.
          echo "pm-facts: $facts is not valid JSON; keeping it as $facts.corrupt" >&2
          mv -f "$facts" "$facts.corrupt"
        fi
        cp ${factsFile} "$tmp"
      fi
      chmod 600 "$tmp"
      mv -f "$tmp" "$facts"
    '';
  };
in
{
  inherit target factsFile seeder;

  # Activation half. Writes $HERMES_HOME/tools, which home-manager activation
  # owns for this user; pm's own writes to the same file are read-modify-write
  # merges, so seeding rows (and leaving every other row alone) is safe.
  # The store path carries `/bin/` -- writeShellApplication's output is a
  # directory, so `${seeder}` alone would be run as a directory (status 126).
  script = "${lib.getExe' seeder "hermes-pm-facts"} ${lib.escapeShellArg "${hermesHome}/tools"}";
}
