{
  config,
  lib,
  pkgs,
  ...
}:

let
  # xdg-open hands the handler a file:// URI with percent-escapes, not a path.
  # Decoding is `%XX` -> `\xXX` fed through printf %b; '+' is left alone, it is
  # only a space in query strings.
  #
  # The cd is not a stylistic choice: rio 0.5.10 accepts --working-dir and then
  # starts the shell in $HOME anyway. Inherited cwd it does honour.
  openFolder = pkgs.writeShellScript "term-open-folder" ''
    target=''${1:-$HOME}
    case "$target" in
      file://*)
        target=$(printf '%b' "$(printf '%s' "''${target#file://}" | sed 's/%/\\x/g')")
        ;;
    esac
    cd "$target" || cd "$HOME" || exit 1
    exec ${lib.getExe config.defaultTerminal}
  '';
in
{
  xdg = {
    enable = true;
    # gh replaces the symlink with a real file whenever it writes config.yml,
    # which otherwise aborts the next activation. See programs.gh in programs.nix.
    configFile."gh/config.yml".force = true;
    desktopEntries.term-folder = {
      name = "Open Folder in Terminal";
      genericName = "Terminal";
      exec = "${openFolder} %u";
      icon = "utilities-terminal";
      type = "Application";
      mimeType = [ "inode/directory" ];
      # A handler, not something to launch from a menu with no folder to open.
      noDisplay = true;
    };
    mimeApps = {
      enable = true;
      # The id is chromium-browser.desktop, NOT chromium.desktop: the nixpkgs
      # chromium/ungoogled-chromium package installs its entry from upstream as
      # chromium-browser.desktop. Naming a non-existent .desktop here fails
      # silently -- xdg-mime falls through to the generic handler list, where
      # Chrome (also installed, and claiming http/https/text/html) wins the
      # alphabetical tie. Symptom: links open in Chrome despite this config.
      defaultApplications = {
        "text/html" = "chromium-browser.desktop";
        "x-scheme-handler/http" = "chromium-browser.desktop";
        "x-scheme-handler/https" = "chromium-browser.desktop";
        "x-scheme-handler/about" = "chromium-browser.desktop";
        "inode/directory" = "term-folder.desktop";
      };
    };
  };
}
