{
  pkgs,
  lib,
  ...
}:

{
  home = {
    username = "codebam";
    homeDirectory = "/home/codebam";

    packages = with pkgs; [
      (writeShellScriptBin "spaste" ''
        ${curl}/bin/curl -X POST --data-binary @- https://p.seanbehan.ca
      '')
      (writeShellScriptBin "nvimdiff" ''
        nvim -d $@
      '')
      (pass.withExtensions (
        subpkgs: with subpkgs; [
          pass-otp
          pass-genphrase
        ]
      ))
      bat
      eza
      grim
      rcm
      ripgrep
      slurp
      weechat
      nixfmt-rfc-style
    ];

    shellAliases = {
      vi = "nvim";
      ls = "eza";
      sudo = "run0";
    };

    stateVersion = "23.11";
  };
  wayland.windowManager.sway =
    let
      wallpaper = builtins.fetchurl {
        url = "https://images.hdqwalls.com/download/1/beach-seaside-digital-painting-4k-05.jpg";
        sha256 = "2877925e7dab66e7723ef79c3bf436ef9f0f2c8968923bb0fff990229144a3fe";
      };
      modifier = "Mod4";
    in
    {
      extraConfigEarly = ''
        set $rosewater #f5e0dc
        set $flamingo #f2cdcd
        set $pink #f5c2e7
        set $mauve #cba6f7
        set $red #f38ba8
        set $maroon #eba0ac
        set $peach #fab387
        set $yellow #f9e2af
        set $green #a6e3a1
        set $teal #94e2d5
        set $sky #89dceb
        set $sapphire #74c7ec
        set $blue #89b4fa
        set $lavender #b4befe
        set $text #cdd6f4
        set $subtext1 #bac2de
        set $subtext0 #a6adc8
        set $overlay2 #9399b2
        set $overlay1 #7f849c
        set $overlay0 #6c7086
        set $surface2 #585b70
        set $surface1 #45475a
        set $surface0 #313244
        set $base #1e1e2e
        set $mantle #181825
        set $crust #11111b
      '';
      enable = true;
      systemd.enable = true;
      config = rec {
        inherit modifier;
        terminal = "wezterm";
        menu = "${pkgs.wmenu}/bin/wmenu-run -i -N 1e1e2e -n 89b4fa -M 1e1e2e -m 89b4fa -S 89b4fa -s cdd6f4";
        fonts = {
          names = [
            "Noto Sans"
            "FontAwesome"
          ];
          style = "Bold Semi-Condensed";
          size = 11.0;
        };
        colors = {
          focused = {
            background = "$lavender";
            border = "$base";
            childBorder = "$lavender";
            indicator = "$rosewater";
            text = "$text";
          };
          focusedInactive = {
            background = "$overlay0";
            border = "$base";
            childBorder = "$overlay0";
            indicator = "$rosewater";
            text = "$text";
          };
          unfocused = {
            background = "$overlay0";
            border = "$base";
            childBorder = "$overlay0";
            indicator = "$rosewater";
            text = "$text";
          };
          urgent = {
            background = "$peach";
            border = "$base";
            childBorder = "$peach";
            indicator = "$overlay0";
            text = "$peach";
          };
          placeholder = {
            background = "$overlay0";
            border = "$base";
            childBorder = "$overlay0";
            indicator = "$overlay0";
            text = "$text";
          };
          background = "$base";
        };
        output = {
          "*" = {
            bg = "${wallpaper} fill";
          };
          "Dell Inc. Dell AW3821DW #GTIYMxgwABhF" = {
            mode = "3840x1600@143.998Hz";
            adaptive_sync = "on";
            subpixel = "none";
            render_bit_depth = "10";
          };
          "eDP-1" = {
            scale = "1.5";
          };
        };
        input = {
          "1739:0:Synaptics_TM3289-021" = {
            events = "enabled";
            dwt = "enabled";
            tap = "enabled";
            natural_scroll = "enabled";
            middle_emulation = "enabled";
            pointer_accel = "0.2";
            accel_profile = "adaptive";
          };
          "2:10:TPPS/2_Elan_TrackPoint" = {
            events = "enabled";
            pointer_accel = "0.7";
            accel_profile = "adaptive";
          };
        };
        bars = [
          {
            position = "top";
            statusCommand = "${pkgs.i3status-rust}/bin/i3status-rs ~/.config/i3status-rust/config-default.toml";
            # statusCommand = "{pkgs.i3status}/bin/i3status";
            hiddenState = "hide";
            trayOutput = "none";
            fonts = {
              names = [
                "Fira Code"
                "FontAwesome"
              ];
              style = "Bold Semi-Condensed";
              size = 11.0;
            };
            colors = {
              background = "$base";
              statusline = "$text";
              focusedStatusline = "$text";
              focusedSeparator = "$base";
              focusedWorkspace = {
                background = "$base";
                border = "$base";
                text = "$green";
              };
              activeWorkspace = {
                background = "$base";
                border = "$base";
                text = "$blue";
              };
              inactiveWorkspace = {
                background = "$base";
                border = "$base";
                text = "$surface1";
              };
              urgentWorkspace = {
                background = "$base";
                border = "$base";
                text = "$surface1";
              };
              bindingMode = {
                background = "$base";
                border = "$base";
                text = "$surface1";
              };
            };
          }
        ];
        window = {
          titlebar = false;
          border = 1;
          hideEdgeBorders = "smart";
        };
        floating = {
          titlebar = false;
          border = 1;
        };
        gaps = {
          inner = 15;
          smartGaps = true;
        };
        focus.followMouse = false;
        workspaceAutoBackAndForth = true;
        keybindings =
          let
            inherit modifier;
          in
          lib.mkOptionDefault {
            "${modifier}+p" = "exec ${pkgs.swaylock}/bin/swaylock";
            "${modifier}+shift+p" = "exec ${pkgs.swaylock}/bin/swaylock & systemctl suspend";
            "${modifier}+shift+u" = "exec ${pkgs.playerctl}/bin/playerctl play-pause";
            "${modifier}+shift+y" = "exec ${pkgs.playerctl}/bin/playerctl previous";
            "${modifier}+shift+i" = "exec ${pkgs.playerctl}/bin/playerctl next";
            "Control+space" = "exec ${pkgs.mako}/bin/makoctl dismiss";
            "${modifier}+Control+space" = "exec ${pkgs.mako}/bin/makoctl restore";
            "${modifier}+shift+x" = "exec ${(pkgs.writeShellScript "screenshot" ''
              ${pkgs.grim}/bin/grim /tmp/screenshot.png && \
              spaste < /tmp/screenshot.png | tr -d '\n' | ${pkgs.wl-clipboard}/bin/wl-copy
            '')}";
            "${modifier}+x" = "exec ${(pkgs.writeShellScript "screenshot-select" ''
              ${pkgs.grim}/bin/grim -g "$(${pkgs.slurp}/bin/slurp)" /tmp/screenshot.png && \
              spaste < /tmp/screenshot.png | tr -d '\n' | ${pkgs.wl-clipboard}/bin/wl-copy
            '')}";
            "${modifier}+n" = "exec '${pkgs.sway}/bin/swaymsg \"bar mode toggle\"'";
            "XF86AudioRaiseVolume" = "exec ${pkgs.wireplumber}/bin/wpctl set-volume @DEFAULT_AUDIO_SINK@ 1%+";
            "XF86AudioLowerVolume" = "exec ${pkgs.wireplumber}/bin/wpctl set-volume @DEFAULT_AUDIO_SINK@ 1%-";
            "XF86AudioMute" = "exec ${pkgs.wireplumber}/bin/wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle";
            "XF86AudioMicMute" = "exec ${pkgs.wireplumber}/bin/wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle";
            "XF86MonBrightnessUp" = "exec ${pkgs.brightnessctl}/bin/brightnessctl set +1%";
            "XF86MonBrightnessDown" = "exec ${pkgs.brightnessctl}/bin/brightnessctl set 1%-";
          };
      };
      extraConfig =
        let
          inherit modifier;
        in
        ''
          bindsym --whole-window {
            ${modifier}+Shift+button4 exec "${pkgs.brightnessctl}/bin/brightnessctl set +1%"
            ${modifier}+Shift+button5 exec "${pkgs.brightnessctl}/bin/brightnessctl set 1%-"
            ${modifier}+button4 exec "${pkgs.wireplumber}/bin/wpctl set-volume @DEFAULT_SINK@ 1%+"
            ${modifier}+button5 exec "${pkgs.wireplumber}/bin/wpctl set-volume @DEFAULT_SINK@ 1%-"
          }
        '';
    };

  programs.plasma = {
    enable = true;
    shortcuts = {
      "ActivityManager"."switch-to-activity-59e4c893-6fbd-4725-91df-50a7f3c4589c" = "none";
      "KDE Keyboard Layout Switcher"."Switch to Last-Used Keyboard Layout" = "Meta+Alt+L";
      "KDE Keyboard Layout Switcher"."Switch to Next Keyboard Layout" = "Meta+Alt+K";
      "kaccess"."Toggle Screen Reader On and Off" = "Meta+Alt+S";
      "kcm_touchpad"."Disable Touchpad" = "Touchpad Off";
      "kcm_touchpad"."Enable Touchpad" = "Touchpad On";
      "kcm_touchpad"."Toggle Touchpad" = [
        "Meta+Ctrl+Zenkaku Hankaku"
        "Meta+Ctrl+Touchpad Toggle"
        "Touchpad Toggle\\\\, Touchpad Toggle"
        ""
        ""
        "\\,Touchpad Toggle"
        "Touchpad Toggle"
        "Meta+Ctrl+Touchpad Toggle"
        "Meta+Ctrl+Zenkaku Hankaku"
      ];
      "kmix"."decrease_microphone_volume" = "Microphone Volume Down";
      "kmix"."decrease_volume" = "Volume Down";
      "kmix"."decrease_volume_small" = "Shift+Volume Down";
      "kmix"."increase_microphone_volume" = "Microphone Volume Up";
      "kmix"."increase_volume" = "Volume Up";
      "kmix"."increase_volume_small" = "Shift+Volume Up";
      "kmix"."mic_mute" = [
        "Microphone Mute"
        ""
        "Meta+Volume Mute\\\\, \\,Microphone Mute"
        "Meta+Volume Mute\\,Mute Microphone"
      ];
      "kmix"."mute" = "Volume Mute";
      "ksmserver"."Halt Without Confirmation" = "none";
      "ksmserver"."Lock Session" = [
        "Meta+L"
        ""
        "Screensaver\\\\, \\,Meta+L"
        "Screensaver\\,Lock Session"
      ];
      "ksmserver"."Log Out" = "Ctrl+Alt+Del";
      "ksmserver"."Log Out Without Confirmation" = "none";
      "ksmserver"."LogOut" = "none";
      "ksmserver"."Reboot" = "none";
      "ksmserver"."Reboot Without Confirmation" = "none";
      "ksmserver"."Shut Down" = "none";
      "kwin"."Activate Window Demanding Attention" = "Meta+Ctrl+A";
      "kwin"."Cube" = "none";
      "kwin"."Cycle Overview" = "none";
      "kwin"."Cycle Overview Opposite" = "none";
      "kwin"."Decrease Opacity" = "\\\\, \\,\\,Decrease Opacity of Active Window by 5%";
      "kwin"."Edit Tiles" = "Meta+T";
      "kwin"."Expose" = "Ctrl+F9";
      "kwin"."ExposeAll" = [
        "Ctrl+F10"
        ""
        "Launch (C)\\\\, \\,Ctrl+F10"
        "Launch (C)\\,Toggle Present Windows (All desktops)"
      ];
      "kwin"."ExposeClass" = "Ctrl+F7";
      "kwin"."ExposeClassCurrentDesktop" = "none";
      "kwin"."Grid View" = "Meta+G";
      "kwin"."Increase Opacity" = "none";
      "kwin"."Kill Window" = "Meta+Ctrl+Esc";
      "kwin"."Move Tablet to Next Output" = "none";
      "kwin"."MoveMouseToCenter" = "Meta+F6";
      "kwin"."MoveMouseToFocus" = "Meta+F5";
      "kwin"."MoveZoomDown" = "none";
      "kwin"."MoveZoomLeft" = "none";
      "kwin"."MoveZoomRight" = "none";
      "kwin"."MoveZoomUp" = "none";
      "kwin"."Overview" = "Meta+W";
      "kwin"."Setup Window Shortcut" = "none";
      "kwin"."Show Desktop" = "Meta+D";
      "kwin"."Switch One Desktop Down" = "Meta+Ctrl+Down";
      "kwin"."Switch One Desktop Up" = "Meta+Ctrl+Up";
      "kwin"."Switch One Desktop to the Left" = "Meta+Ctrl+Left";
      "kwin"."Switch One Desktop to the Right" = "Meta+Ctrl+Right";
      "kwin"."Switch Window Down" = "Meta+Alt+Down";
      "kwin"."Switch Window Left" = "Meta+Alt+Left";
      "kwin"."Switch Window Right" = "Meta+Alt+Right";
      "kwin"."Switch Window Up" = "Meta+Alt+Up";
      "kwin"."Switch to Desktop 1" = "Ctrl+F1";
      "kwin"."Switch to Desktop 10" = "none";
      "kwin"."Switch to Desktop 11" = "none";
      "kwin"."Switch to Desktop 12" = "none";
      "kwin"."Switch to Desktop 13" = "none";
      "kwin"."Switch to Desktop 14" = "none";
      "kwin"."Switch to Desktop 15" = "none";
      "kwin"."Switch to Desktop 16" = "none";
      "kwin"."Switch to Desktop 17" = "none";
      "kwin"."Switch to Desktop 18" = "none";
      "kwin"."Switch to Desktop 19" = "none";
      "kwin"."Switch to Desktop 2" = "Ctrl+F2";
      "kwin"."Switch to Desktop 20" = "none";
      "kwin"."Switch to Desktop 3" = "Ctrl+F3";
      "kwin"."Switch to Desktop 4" = "Ctrl+F4";
      "kwin"."Switch to Desktop 5" = "none";
      "kwin"."Switch to Desktop 6" = "none";
      "kwin"."Switch to Desktop 7" = "none";
      "kwin"."Switch to Desktop 8" = "none";
      "kwin"."Switch to Desktop 9" = "none";
      "kwin"."Switch to Next Desktop" = "none";
      "kwin"."Switch to Next Screen" = "none";
      "kwin"."Switch to Previous Desktop" = "none";
      "kwin"."Switch to Previous Screen" = "none";
      "kwin"."Switch to Screen 0" = "none";
      "kwin"."Switch to Screen 1" = "none";
      "kwin"."Switch to Screen 2" = "none";
      "kwin"."Switch to Screen 3" = "none";
      "kwin"."Switch to Screen 4" = "none";
      "kwin"."Switch to Screen 5" = "none";
      "kwin"."Switch to Screen 6" = "none";
      "kwin"."Switch to Screen 7" = "none";
      "kwin"."Switch to Screen Above" = "none";
      "kwin"."Switch to Screen Below" = "none";
      "kwin"."Switch to Screen to the Left" = "none";
      "kwin"."Switch to Screen to the Right" = "none";
      "kwin"."Toggle Night Color" = "none";
      "kwin"."Toggle Window Raise/Lower" = "none";
      "kwin"."Walk Through Windows" = "Alt+Tab";
      "kwin"."Walk Through Windows (Reverse)" = "Alt+Shift+Tab";
      "kwin"."Walk Through Windows Alternative" = "none";
      "kwin"."Walk Through Windows Alternative (Reverse)" = "none";
      "kwin"."Walk Through Windows of Current Application" = "Alt+`";
      "kwin"."Walk Through Windows of Current Application (Reverse)" = "Alt+~";
      "kwin"."Walk Through Windows of Current Application Alternative" = "none";
      "kwin"."Walk Through Windows of Current Application Alternative (Reverse)" = "none";
      "kwin"."Window Above Other Windows" = "none";
      "kwin"."Window Below Other Windows" = "none";
      "kwin"."Window Close" = "Alt+F4";
      "kwin"."Window Custom Quick Tile Bottom" = "none";
      "kwin"."Window Custom Quick Tile Left" = "none";
      "kwin"."Window Custom Quick Tile Right" = "none";
      "kwin"."Window Custom Quick Tile Top" = "none";
      "kwin"."Window Fullscreen" = "none";
      "kwin"."Window Grow Horizontal" = "none";
      "kwin"."Window Grow Vertical" = "none";
      "kwin"."Window Lower" = "none";
      "kwin"."Window Maximize" = "Meta+PgUp";
      "kwin"."Window Maximize Horizontal" = "none";
      "kwin"."Window Maximize Vertical" = "none";
      "kwin"."Window Minimize" = "Meta+PgDown";
      "kwin"."Window Move" = "none";
      "kwin"."Window Move Center" = "none";
      "kwin"."Window No Border" = "none";
      "kwin"."Window On All Desktops" = "none";
      "kwin"."Window One Desktop Down" = "Meta+Ctrl+Shift+Down";
      "kwin"."Window One Desktop Up" = "Meta+Ctrl+Shift+Up";
      "kwin"."Window One Desktop to the Left" = "Meta+Ctrl+Shift+Left";
      "kwin"."Window One Desktop to the Right" = "Meta+Ctrl+Shift+Right";
      "kwin"."Window One Screen Down" = "none";
      "kwin"."Window One Screen Up" = "none";
      "kwin"."Window One Screen to the Left" = "none";
      "kwin"."Window One Screen to the Right" = "none";
      "kwin"."Window Operations Menu" = "Alt+F3";
      "kwin"."Window Pack Down" = "none";
      "kwin"."Window Pack Left" = "none";
      "kwin"."Window Pack Right" = "none";
      "kwin"."Window Pack Up" = "none";
      "kwin"."Window Quick Tile Bottom" = "Meta+Down";
      "kwin"."Window Quick Tile Bottom Left" = "none";
      "kwin"."Window Quick Tile Bottom Right" = "none";
      "kwin"."Window Quick Tile Left" = "Meta+Left";
      "kwin"."Window Quick Tile Right" = "Meta+Right";
      "kwin"."Window Quick Tile Top" = "Meta+Up";
      "kwin"."Window Quick Tile Top Left" = "none";
      "kwin"."Window Quick Tile Top Right" = "none";
      "kwin"."Window Raise" = "none";
      "kwin"."Window Resize" = "none";
      "kwin"."Window Shade" = "none";
      "kwin"."Window Shrink Horizontal" = "none";
      "kwin"."Window Shrink Vertical" = "none";
      "kwin"."Window to Desktop 1" = "none";
      "kwin"."Window to Desktop 10" = "none";
      "kwin"."Window to Desktop 11" = "none";
      "kwin"."Window to Desktop 12" = "none";
      "kwin"."Window to Desktop 13" = "none";
      "kwin"."Window to Desktop 14" = "none";
      "kwin"."Window to Desktop 15" = "none";
      "kwin"."Window to Desktop 16" = "none";
      "kwin"."Window to Desktop 17" = "none";
      "kwin"."Window to Desktop 18" = "none";
      "kwin"."Window to Desktop 19" = "none";
      "kwin"."Window to Desktop 2" = "none";
      "kwin"."Window to Desktop 20" = "none";
      "kwin"."Window to Desktop 3" = "none";
      "kwin"."Window to Desktop 4" = "none";
      "kwin"."Window to Desktop 5" = "none";
      "kwin"."Window to Desktop 6" = "none";
      "kwin"."Window to Desktop 7" = "none";
      "kwin"."Window to Desktop 8" = "none";
      "kwin"."Window to Desktop 9" = "none";
      "kwin"."Window to Next Desktop" = "none";
      "kwin"."Window to Next Screen" = "Meta+Shift+Right";
      "kwin"."Window to Previous Desktop" = "none";
      "kwin"."Window to Previous Screen" = "Meta+Shift+Left";
      "kwin"."Window to Screen 0" = "none";
      "kwin"."Window to Screen 1" = "none";
      "kwin"."Window to Screen 2" = "none";
      "kwin"."Window to Screen 3" = "none";
      "kwin"."Window to Screen 4" = "none";
      "kwin"."Window to Screen 5" = "none";
      "kwin"."Window to Screen 6" = "none";
      "kwin"."Window to Screen 7" = "none";
      "kwin"."disableInputCapture" = "Meta+Shift+Esc";
      "kwin"."view_actual_size" = "Meta+0";
      "kwin"."view_zoom_in" = [
        "Meta++"
        "Meta+x3d\\,Meta++"
        "Meta+x3d\\,Zoom In"
      ];
      "kwin"."view_zoom_out" = "Meta+-";
      "mediacontrol"."mediavolumedown" = "none";
      "mediacontrol"."mediavolumeup" = "none";
      "mediacontrol"."nextmedia" = "Media Next";
      "mediacontrol"."pausemedia" = "Media Pause";
      "mediacontrol"."playmedia" = "none";
      "mediacontrol"."playpausemedia" = [
        "Media Play"
        "Meta+Shift+U\\,Media Play\\,Play/Pause media playback"
      ];
      "mediacontrol"."previousmedia" = "Media Previous";
      "mediacontrol"."stopmedia" = "Media Stop";
      "org_kde_powerdevil"."Decrease Keyboard Brightness" = "Keyboard Brightness Down";
      "org_kde_powerdevil"."Decrease Screen Brightness" = "Monitor Brightness Down";
      "org_kde_powerdevil"."Decrease Screen Brightness Small" = "Shift+Monitor Brightness Down";
      "org_kde_powerdevil"."Hibernate" = "Hibernate";
      "org_kde_powerdevil"."Increase Keyboard Brightness" = "Keyboard Brightness Up";
      "org_kde_powerdevil"."Increase Screen Brightness" = "Monitor Brightness Up";
      "org_kde_powerdevil"."Increase Screen Brightness Small" = "Shift+Monitor Brightness Up";
      "org_kde_powerdevil"."PowerDown" = "Power Down";
      "org_kde_powerdevil"."PowerOff" = "Power Off";
      "org_kde_powerdevil"."Sleep" = "Sleep";
      "org_kde_powerdevil"."Toggle Keyboard Backlight" = "Keyboard Light On/Off";
      "org_kde_powerdevil"."Turn Off Screen" = "none";
      "org_kde_powerdevil"."powerProfile" = [
        "Battery"
        ""
        "Meta+B\\\\, \\,Battery"
        "Meta+B\\,Switch Power Profile"
      ];
      "plasmashell"."activate application launcher" = [
        "Meta"
        "Alt+F1\\,Meta"
        "Alt+F1\\,Activate Application Launcher"
      ];
      "plasmashell"."activate task manager entry 1" = "Meta+1";
      "plasmashell"."activate task manager entry 10" = "none";
      "plasmashell"."activate task manager entry 2" = "Meta+2";
      "plasmashell"."activate task manager entry 3" = "Meta+3";
      "plasmashell"."activate task manager entry 4" = "Meta+4";
      "plasmashell"."activate task manager entry 5" = "Meta+5";
      "plasmashell"."activate task manager entry 6" = "Meta+6";
      "plasmashell"."activate task manager entry 7" = "Meta+7";
      "plasmashell"."activate task manager entry 8" = "Meta+8";
      "plasmashell"."activate task manager entry 9" = "Meta+9";
      "plasmashell"."clear-history" = "none";
      "plasmashell"."clipboard_action" = "Meta+Ctrl+X";
      "plasmashell"."cycle-panels" = "Meta+Alt+P";
      "plasmashell"."cycleNextAction" = "none";
      "plasmashell"."cyclePrevAction" = "none";
      "plasmashell"."manage activities" = "Meta+Q";
      "plasmashell"."next activity" = "none";
      "plasmashell"."previous activity" = "none";
      "plasmashell"."repeat_action" = "none";
      "plasmashell"."show dashboard" = "Ctrl+F12";
      "plasmashell"."show-barcode" = "none";
      "plasmashell"."show-on-mouse-pos" = "Meta+V";
      "plasmashell"."stop current activity" = "Meta+S";
      "plasmashell"."switch to next activity" = "none";
      "plasmashell"."switch to previous activity" = "none";
      "plasmashell"."toggle do not disturb" = "none";
    };
    configFile = {
      "baloofilerc"."General"."dbVersion" = 2;
      "baloofilerc"."General"."exclude filters" =
        "*~,*.part,*.o,*.la,*.lo,*.loT,*.moc,moc_*.cpp,qrc_*.cpp,ui_*.h,cmake_install.cmake,CMakeCache.txt,CTestTestfile.cmake,libtool,config.status,confdefs.h,autom4te,conftest,confstat,Makefile.am,*.gcode,.ninja_deps,.ninja_log,build.ninja,*.csproj,*.m4,*.rej,*.gmo,*.pc,*.omf,*.aux,*.tmp,*.po,*.vm*,*.nvram,*.rcore,*.swp,*.swap,lzo,litmain.sh,*.orig,.histfile.*,.xsession-errors*,*.map,*.so,*.a,*.db,*.qrc,*.ini,*.init,*.img,*.vdi,*.vbox*,vbox.log,*.qcow2,*.vmdk,*.vhd,*.vhdx,*.sql,*.sql.gz,*.ytdl,*.tfstate*,*.class,*.pyc,*.pyo,*.elc,*.qmlc,*.jsc,*.fastq,*.fq,*.gb,*.fasta,*.fna,*.gbff,*.faa,po,CVS,.svn,.git,_darcs,.bzr,.hg,CMakeFiles,CMakeTmp,CMakeTmpQmake,.moc,.obj,.pch,.uic,.npm,.yarn,.yarn-cache,__pycache__,node_modules,node_packages,nbproject,.terraform,.venv,venv,core-dumps,lost+found";
      "baloofilerc"."General"."exclude filters version" = 9;
      "baloofilerc"."General"."exclude folders[$e]" = "$HOME/";
      "baloofilerc"."General"."exclude foldersx5b$ex5d" = "$HOME/";
      "baloofilerc"."General"."folders[$e]" = "$HOME/Documents/,$HOME/Downloads/,$HOME/Pictures/";
      "baloofilerc"."General"."foldersx5b$ex5d" = "$HOME/Documents/,$HOME/Downloads/,$HOME/Pictures/";
      "dolphinrc"."General"."ViewPropsTimestamp" = "2024,9,7,22,54,15.519";
      "dolphinrc"."KFileDialog Settings"."Places Icons Auto-resize" = false;
      "dolphinrc"."KFileDialog Settings"."Places Icons Static Size" = 22;
      "kactivitymanagerdrc"."activities"."59e4c893-6fbd-4725-91df-50a7f3c4589c" = "Default";
      "kactivitymanagerdrc"."main"."currentActivity" = "59e4c893-6fbd-4725-91df-50a7f3c4589c";
      "katerc"."General"."Days Meta Infos" = 30;
      "katerc"."General"."Save Meta Infos" = true;
      "katerc"."General"."Show Full Path in Title" = false;
      "katerc"."General"."Show Menu Bar" = true;
      "katerc"."General"."Show Status Bar" = true;
      "katerc"."General"."Show Tab Bar" = true;
      "katerc"."General"."Show Url Nav Bar" = true;
      "katerc"."filetree"."editShade" = "72,82,101";
      "katerc"."filetree"."listMode" = false;
      "katerc"."filetree"."middleClickToClose" = false;
      "katerc"."filetree"."shadingEnabled" = true;
      "katerc"."filetree"."showCloseButton" = false;
      "katerc"."filetree"."showFullPathOnRoots" = false;
      "katerc"."filetree"."showToolbar" = true;
      "katerc"."filetree"."sortRole" = 0;
      "katerc"."filetree"."viewShade" = "72,102,140";
      "kcminputrc"."Libinput/1133/49291/Logitech G502 HERO Gaming Mouse"."PointerAccelerationProfile" = 1;
      "kcminputrc"."Mouse"."cursorSize" = 36;
      "kcminputrc"."Mouse"."cursorTheme" = "WhiteSur-cursors";
      "kded5rc"."Module-device_automounter"."autoload" = false;
      "kdeglobals"."DirSelect Dialog"."DirSelectDialog Size" = "820,584";
      "kdeglobals"."General"."TerminalApplication" = "wezterm start --cwd .";
      "kdeglobals"."General"."TerminalService" = "org.wezfurlong.wezterm.desktop";
      "kdeglobals"."KFileDialog Settings"."Allow Expansion" = false;
      "kdeglobals"."KFileDialog Settings"."Automatically select filename extension" = true;
      "kdeglobals"."KFileDialog Settings"."Breadcrumb Navigation" = false;
      "kdeglobals"."KFileDialog Settings"."Decoration position" = 2;
      "kdeglobals"."KFileDialog Settings"."LocationCombo Completionmode" = 5;
      "kdeglobals"."KFileDialog Settings"."PathCombo Completionmode" = 5;
      "kdeglobals"."KFileDialog Settings"."Show Bookmarks" = false;
      "kdeglobals"."KFileDialog Settings"."Show Full Path" = false;
      "kdeglobals"."KFileDialog Settings"."Show Inline Previews" = true;
      "kdeglobals"."KFileDialog Settings"."Show Preview" = false;
      "kdeglobals"."KFileDialog Settings"."Show Speedbar" = true;
      "kdeglobals"."KFileDialog Settings"."Show hidden files" = false;
      "kdeglobals"."KFileDialog Settings"."Sort by" = "Date";
      "kdeglobals"."KFileDialog Settings"."Sort directories first" = true;
      "kdeglobals"."KFileDialog Settings"."Sort hidden files last" = false;
      "kdeglobals"."KFileDialog Settings"."Sort reversed" = true;
      "kdeglobals"."KFileDialog Settings"."Speedbar Width" = 140;
      "kdeglobals"."KFileDialog Settings"."View Style" = "DetailTree";
      "kdeglobals"."WM"."activeBackground" = "51,51,51";
      "kdeglobals"."WM"."activeBlend" = "171,171,171";
      "kdeglobals"."WM"."activeForeground" = "252,252,252";
      "kdeglobals"."WM"."inactiveBackground" = "66,66,66";
      "kdeglobals"."WM"."inactiveBlend" = "85,85,85";
      "kdeglobals"."WM"."inactiveForeground" = "170,170,170";
      "kiorc"."Confirmations"."ConfirmEmptyTrash" = true;
      "klaunchrc"."BusyCursorSettings"."Bouncing" = false;
      "klaunchrc"."FeedbackStyle"."BusyCursor" = false;
      "krunnerrc"."Plugins"."baloosearchEnabled" = true;
      "kscreenlockerrc"."Greeter/Wallpaper/org.kde.image/General"."Image" =
        "/home/codebam/Downloads/MacProTips Wallpaper Collection (2024)/MPT Wallpaper Collection (2024)/Space/blue galaxy.jpeg";
      "kscreenlockerrc"."Greeter/Wallpaper/org.kde.image/General"."PreviewImage" =
        "/home/codebam/Downloads/MacProTips Wallpaper Collection (2024)/MPT Wallpaper Collection (2024)/Space/blue galaxy.jpeg";
      "ksmserverrc"."General"."loginMode" = "emptySession";
      "ksplashrc"."KSplash"."Engine" = "none";
      "ksplashrc"."KSplash"."Theme" = "None";
      "kwalletrc"."Wallet"."First Use" = false;
      "kwinrc"."Activities/LastVirtualDesktop"."59e4c893-6fbd-4725-91df-50a7f3c4589c" =
        "0192ec0d-daef-4e6a-b935-d9e28bcbcc36";
      "kwinrc"."Desktops"."Id_1" = "0192ec0d-daef-4e6a-b935-d9e28bcbcc36";
      "kwinrc"."Desktops"."Id_2" = "614281b8-5ac6-4238-9ede-7d56896ca27b";
      "kwinrc"."Desktops"."Id_3" = "682fa65e-07d9-467d-a0c3-20bb1d5210f8";
      "kwinrc"."Desktops"."Name_1" = "Desktop 1";
      "kwinrc"."Desktops"."Number" = 3;
      "kwinrc"."Desktops"."Rows" = 1;
      "kwinrc"."Plugins"."kwin6_effect_glitchEnabled" = true;
      "kwinrc"."Plugins"."magiclampEnabled" = true;
      "kwinrc"."Plugins"."scaleEnabled" = false;
      "kwinrc"."Plugins"."squash2Enabled" = false;
      "kwinrc"."Plugins"."squashEnabled" = false;
      "kwinrc"."Tiling"."padding" = 4;
      "kwinrc"."Tiling/b2559065-88e5-5b53-86c7-cab85d2c57e6"."tiles" =
        ''{"layoutDirection":"horizontal","tiles":x5b{"width":0.25},{"width":0.5},{"width":0.25}x5d}'';
      "kwinrc"."Windows"."ElectricBorderTiling" = false;
      "kwinrc"."Windows"."ElectricBorders" = 1;
      "kwinrc"."Xwayland"."Scale" = 1.15;
      "kwinrc"."org.kde.kdecoration2"."BorderSize" = "None";
      "kwinrc"."org.kde.kdecoration2"."BorderSizeAuto" = false;
      "kwinrc"."org.kde.kdecoration2"."ButtonsOnLeft" = "XAIMS";
      "kwinrc"."org.kde.kdecoration2"."ButtonsOnRight" = "H";
      "kwinrc"."org.kde.kdecoration2"."theme" = "__aurorae__svg__WhiteSur-Sharp-dark";
      "plasma-localerc"."Formats"."LANG" = "en_US.UTF-8";
      "plasmanotifyrc"."Applications/com.discordapp.Discord"."Seen" = true;
      "plasmanotifyrc"."Applications/com.discordapp.DiscordCanary"."Seen" = true;
      "plasmanotifyrc"."Applications/com.google.Chrome"."Seen" = true;
      "plasmanotifyrc"."Applications/com.obsproject.Studio"."Seen" = true;
      "plasmanotifyrc"."Applications/com.valvesoftware.Steam"."Seen" = true;
      "plasmanotifyrc"."Applications/dev.vencord.Vesktop"."Seen" = true;
      "plasmanotifyrc"."Applications/im.riot.Riot"."Seen" = true;
      "plasmanotifyrc"."Applications/net.runelite.RuneLite"."Seen" = true;
      "plasmanotifyrc"."Applications/org.kde.kdenlive"."Seen" = true;
      "plasmanotifyrc"."Applications/org.mozilla.Thunderbird"."Seen" = true;
      "plasmanotifyrc"."Applications/org.mozilla.firefox"."Seen" = true;
      "plasmanotifyrc"."Applications/org.qbittorrent.qBittorrent"."Seen" = true;
      "plasmanotifyrc"."Applications/org.signal.Signal"."Seen" = true;
      "plasmanotifyrc"."Applications/org.telegram.desktop"."Seen" = true;
      "plasmanotifyrc"."Notifications"."NormalAlwaysOnTop" = true;
      "plasmarc"."Wallpapers"."usersWallpapers" =
        "/nix/store/7hy3dkbscarakjdnwdsjzx8s26gngpvr-beach-seaside-digital-painting-4k-05.jpg,/home/codebam/Downloads/MacProTips Wallpaper Collection (2024)/MPT Wallpaper Collection (2024)/Geometry/twisting helix.png,/home/codebam/Downloads/MacProTips Wallpaper Collection (2024)/MPT Wallpaper Collection (2024)/Space/blue galaxy.jpeg";
      "spectaclerc"."Annotations"."annotationToolType" = 6;
      "spectaclerc"."Annotations"."rectangleFillColor" = "0,0,0";
      "spectaclerc"."GuiConfig"."captureMode" = 0;
      "spectaclerc"."GuiConfig"."quitAfterSaveCopyExport" = true;
      "spectaclerc"."ImageSave"."lastImageSaveAsLocation" =
        "file:///home/codebam/Pictures/Screenshots/Screenshot_20250228_113524.png";
      "spectaclerc"."ImageSave"."lastImageSaveLocation" =
        "file:///home/codebam/Pictures/Screenshots/Screenshot_20250228_113524.png";
      "spectaclerc"."ImageSave"."translatedScreenshotsFolder" = "Screenshots";
      "spectaclerc"."VideoSave"."translatedScreencastsFolder" = "Screencasts";
    };
    dataFile = {
      "kate/anonymous.katesession"."Document 0"."URL" =
        "file:///run/media/codebam/7d57a643-ac36-4e54-b873-0e19bd8a8645/SteamLibrary/steamapps/compatdata/232090/pfx/drive_c/users/steamuser/Documents/My Games/KillingFloor2/KFGame/Config/GFXSettings.KFGame.xml";
      "kate/anonymous.katesession"."Kate Plugins"."cmaketoolsplugin" = false;
      "kate/anonymous.katesession"."Kate Plugins"."compilerexplorer" = false;
      "kate/anonymous.katesession"."Kate Plugins"."eslintplugin" = false;
      "kate/anonymous.katesession"."Kate Plugins"."externaltoolsplugin" = true;
      "kate/anonymous.katesession"."Kate Plugins"."formatplugin" = false;
      "kate/anonymous.katesession"."Kate Plugins"."katebacktracebrowserplugin" = false;
      "kate/anonymous.katesession"."Kate Plugins"."katebuildplugin" = false;
      "kate/anonymous.katesession"."Kate Plugins"."katecloseexceptplugin" = false;
      "kate/anonymous.katesession"."Kate Plugins"."katecolorpickerplugin" = false;
      "kate/anonymous.katesession"."Kate Plugins"."katectagsplugin" = false;
      "kate/anonymous.katesession"."Kate Plugins"."katefilebrowserplugin" = false;
      "kate/anonymous.katesession"."Kate Plugins"."katefiletreeplugin" = true;
      "kate/anonymous.katesession"."Kate Plugins"."kategdbplugin" = false;
      "kate/anonymous.katesession"."Kate Plugins"."kategitblameplugin" = false;
      "kate/anonymous.katesession"."Kate Plugins"."katekonsoleplugin" = true;
      "kate/anonymous.katesession"."Kate Plugins"."kateprojectplugin" = true;
      "kate/anonymous.katesession"."Kate Plugins"."katereplicodeplugin" = false;
      "kate/anonymous.katesession"."Kate Plugins"."katesearchplugin" = true;
      "kate/anonymous.katesession"."Kate Plugins"."katesnippetsplugin" = false;
      "kate/anonymous.katesession"."Kate Plugins"."katesqlplugin" = false;
      "kate/anonymous.katesession"."Kate Plugins"."katesymbolviewerplugin" = false;
      "kate/anonymous.katesession"."Kate Plugins"."katexmlcheckplugin" = false;
      "kate/anonymous.katesession"."Kate Plugins"."katexmltoolsplugin" = false;
      "kate/anonymous.katesession"."Kate Plugins"."keyboardmacrosplugin" = false;
      "kate/anonymous.katesession"."Kate Plugins"."ktexteditorpreviewplugin" = false;
      "kate/anonymous.katesession"."Kate Plugins"."latexcompletionplugin" = false;
      "kate/anonymous.katesession"."Kate Plugins"."lspclientplugin" = true;
      "kate/anonymous.katesession"."Kate Plugins"."openlinkplugin" = false;
      "kate/anonymous.katesession"."Kate Plugins"."rainbowparens" = false;
      "kate/anonymous.katesession"."Kate Plugins"."rbqlplugin" = false;
      "kate/anonymous.katesession"."Kate Plugins"."tabswitcherplugin" = true;
      "kate/anonymous.katesession"."Kate Plugins"."textfilterplugin" = true;
      "kate/anonymous.katesession"."MainWindow0"."Active ViewSpace" = 0;
      "kate/anonymous.katesession"."MainWindow0"."Kate-MDI-H-Splitter" = "0,1202,0";
      "kate/anonymous.katesession"."MainWindow0"."Kate-MDI-Sidebar-0-Bar-0-TvList" =
        "kate_private_plugin_katefiletreeplugin,kateproject,kateprojectgit,lspclient_symbol_outline";
      "kate/anonymous.katesession"."MainWindow0"."Kate-MDI-Sidebar-0-LastSize" = 200;
      "kate/anonymous.katesession"."MainWindow0"."Kate-MDI-Sidebar-0-SectSizes" = 0;
      "kate/anonymous.katesession"."MainWindow0"."Kate-MDI-Sidebar-0-Splitter" = 790;
      "kate/anonymous.katesession"."MainWindow0"."Kate-MDI-Sidebar-1-Bar-0-TvList" = "";
      "kate/anonymous.katesession"."MainWindow0"."Kate-MDI-Sidebar-1-LastSize" = 200;
      "kate/anonymous.katesession"."MainWindow0"."Kate-MDI-Sidebar-1-SectSizes" = 0;
      "kate/anonymous.katesession"."MainWindow0"."Kate-MDI-Sidebar-1-Splitter" = 586;
      "kate/anonymous.katesession"."MainWindow0"."Kate-MDI-Sidebar-2-Bar-0-TvList" = "";
      "kate/anonymous.katesession"."MainWindow0"."Kate-MDI-Sidebar-2-LastSize" = 200;
      "kate/anonymous.katesession"."MainWindow0"."Kate-MDI-Sidebar-2-SectSizes" = 0;
      "kate/anonymous.katesession"."MainWindow0"."Kate-MDI-Sidebar-2-Splitter" = 895;
      "kate/anonymous.katesession"."MainWindow0"."Kate-MDI-Sidebar-3-Bar-0-TvList" =
        "output,diagnostics,kate_plugin_katesearch,kateprojectinfo,kate_private_plugin_katekonsoleplugin";
      "kate/anonymous.katesession"."MainWindow0"."Kate-MDI-Sidebar-3-LastSize" = 200;
      "kate/anonymous.katesession"."MainWindow0"."Kate-MDI-Sidebar-3-SectSizes" = 0;
      "kate/anonymous.katesession"."MainWindow0"."Kate-MDI-Sidebar-3-Splitter" = 952;
      "kate/anonymous.katesession"."MainWindow0"."Kate-MDI-Sidebar-Style" = 2;
      "kate/anonymous.katesession"."MainWindow0"."Kate-MDI-Sidebar-Visible" = true;
      "kate/anonymous.katesession"."MainWindow0"."Kate-MDI-ToolView-diagnostics-Position" = 3;
      "kate/anonymous.katesession"."MainWindow0"."Kate-MDI-ToolView-diagnostics-Show-Button-In-Sidebar" =
        true;
      "kate/anonymous.katesession"."MainWindow0"."Kate-MDI-ToolView-diagnostics-Visible" = false;
      "kate/anonymous.katesession"."MainWindow0"."Kate-MDI-ToolView-kate_plugin_katesearch-Position" = 3;
      "kate/anonymous.katesession"."MainWindow0"."Kate-MDI-ToolView-kate_plugin_katesearch-Show-Button-In-Sidebar" =
        true;
      "kate/anonymous.katesession"."MainWindow0"."Kate-MDI-ToolView-kate_plugin_katesearch-Visible" =
        false;
      "kate/anonymous.katesession"."MainWindow0"."Kate-MDI-ToolView-kate_private_plugin_katefiletreeplugin-Position" =
        0;
      "kate/anonymous.katesession"."MainWindow0"."Kate-MDI-ToolView-kate_private_plugin_katefiletreeplugin-Show-Button-In-Sidebar" =
        true;
      "kate/anonymous.katesession"."MainWindow0"."Kate-MDI-ToolView-kate_private_plugin_katefiletreeplugin-Visible" =
        false;
      "kate/anonymous.katesession"."MainWindow0"."Kate-MDI-ToolView-kate_private_plugin_katekonsoleplugin-Position" =
        3;
      "kate/anonymous.katesession"."MainWindow0"."Kate-MDI-ToolView-kate_private_plugin_katekonsoleplugin-Show-Button-In-Sidebar" =
        true;
      "kate/anonymous.katesession"."MainWindow0"."Kate-MDI-ToolView-kate_private_plugin_katekonsoleplugin-Visible" =
        false;
      "kate/anonymous.katesession"."MainWindow0"."Kate-MDI-ToolView-kateproject-Position" = 0;
      "kate/anonymous.katesession"."MainWindow0"."Kate-MDI-ToolView-kateproject-Show-Button-In-Sidebar" =
        true;
      "kate/anonymous.katesession"."MainWindow0"."Kate-MDI-ToolView-kateproject-Visible" = false;
      "kate/anonymous.katesession"."MainWindow0"."Kate-MDI-ToolView-kateprojectgit-Position" = 0;
      "kate/anonymous.katesession"."MainWindow0"."Kate-MDI-ToolView-kateprojectgit-Show-Button-In-Sidebar" =
        true;
      "kate/anonymous.katesession"."MainWindow0"."Kate-MDI-ToolView-kateprojectgit-Visible" = false;
      "kate/anonymous.katesession"."MainWindow0"."Kate-MDI-ToolView-kateprojectinfo-Position" = 3;
      "kate/anonymous.katesession"."MainWindow0"."Kate-MDI-ToolView-kateprojectinfo-Show-Button-In-Sidebar" =
        true;
      "kate/anonymous.katesession"."MainWindow0"."Kate-MDI-ToolView-kateprojectinfo-Visible" = false;
      "kate/anonymous.katesession"."MainWindow0"."Kate-MDI-ToolView-lspclient_symbol_outline-Position" =
        0;
      "kate/anonymous.katesession"."MainWindow0"."Kate-MDI-ToolView-lspclient_symbol_outline-Show-Button-In-Sidebar" =
        true;
      "kate/anonymous.katesession"."MainWindow0"."Kate-MDI-ToolView-lspclient_symbol_outline-Visible" =
        false;
      "kate/anonymous.katesession"."MainWindow0"."Kate-MDI-ToolView-output-Position" = 3;
      "kate/anonymous.katesession"."MainWindow0"."Kate-MDI-ToolView-output-Show-Button-In-Sidebar" = true;
      "kate/anonymous.katesession"."MainWindow0"."Kate-MDI-ToolView-output-Visible" = false;
      "kate/anonymous.katesession"."MainWindow0"."Kate-MDI-V-Splitter" = "0,790,0";
      "kate/anonymous.katesession"."MainWindow0"."ToolBarsMovable" = "Disabled";
      "kate/anonymous.katesession"."MainWindow0 Settings"."ToolBarsMovable" = "Disabled";
      "kate/anonymous.katesession"."MainWindow0 Settings"."WindowState" = 8;
      "kate/anonymous.katesession"."MainWindow0-Splitter 0"."Children" = "MainWindow0-ViewSpace 0";
      "kate/anonymous.katesession"."MainWindow0-Splitter 0"."Orientation" = 1;
      "kate/anonymous.katesession"."MainWindow0-Splitter 0"."Sizes" = 1202;
      "kate/anonymous.katesession"."MainWindow0-ViewSpace 0"."Active View" = 0;
      "kate/anonymous.katesession"."MainWindow0-ViewSpace 0"."Count" = 1;
      "kate/anonymous.katesession"."MainWindow0-ViewSpace 0"."Documents" = 0;
      "kate/anonymous.katesession"."MainWindow0-ViewSpace 0"."View 0" = 0;
      "kate/anonymous.katesession"."MainWindow0-ViewSpace 0 0"."CursorColumn" = 108;
      "kate/anonymous.katesession"."MainWindow0-ViewSpace 0 0"."CursorLine" = 51;
      "kate/anonymous.katesession"."MainWindow0-ViewSpace 0 0"."ScrollLine" = 17;
      "kate/anonymous.katesession"."Open Documents"."Count" = 1;
      "kate/anonymous.katesession"."Open MainWindows"."Count" = 1;
      "kate/anonymous.katesession"."Plugin:kateprojectplugin:"."projects" = "";
      "kate/anonymous.katesession"."Plugin:katesearchplugin:MainWindow:0"."BinaryFiles" = false;
      "kate/anonymous.katesession"."Plugin:katesearchplugin:MainWindow:0"."CurrentExcludeFilter" = "-1";
      "kate/anonymous.katesession"."Plugin:katesearchplugin:MainWindow:0"."CurrentFilter" = "-1";
      "kate/anonymous.katesession"."Plugin:katesearchplugin:MainWindow:0"."ExcludeFilters" = "";
      "kate/anonymous.katesession"."Plugin:katesearchplugin:MainWindow:0"."ExpandSearchResults" = false;
      "kate/anonymous.katesession"."Plugin:katesearchplugin:MainWindow:0"."Filters" = "";
      "kate/anonymous.katesession"."Plugin:katesearchplugin:MainWindow:0"."FollowSymLink" = false;
      "kate/anonymous.katesession"."Plugin:katesearchplugin:MainWindow:0"."HiddenFiles" = false;
      "kate/anonymous.katesession"."Plugin:katesearchplugin:MainWindow:0"."MatchCase" = false;
      "kate/anonymous.katesession"."Plugin:katesearchplugin:MainWindow:0"."Place" = 1;
      "kate/anonymous.katesession"."Plugin:katesearchplugin:MainWindow:0"."Recursive" = true;
      "kate/anonymous.katesession"."Plugin:katesearchplugin:MainWindow:0"."Replaces" = "";
      "kate/anonymous.katesession"."Plugin:katesearchplugin:MainWindow:0"."Search" = "";
      "kate/anonymous.katesession"."Plugin:katesearchplugin:MainWindow:0"."SearchAsYouTypeAllProjects" =
        true;
      "kate/anonymous.katesession"."Plugin:katesearchplugin:MainWindow:0"."SearchAsYouTypeCurrentFile" =
        true;
      "kate/anonymous.katesession"."Plugin:katesearchplugin:MainWindow:0"."SearchAsYouTypeFolder" = true;
      "kate/anonymous.katesession"."Plugin:katesearchplugin:MainWindow:0"."SearchAsYouTypeOpenFiles" =
        true;
      "kate/anonymous.katesession"."Plugin:katesearchplugin:MainWindow:0"."SearchAsYouTypeProject" = true;
      "kate/anonymous.katesession"."Plugin:katesearchplugin:MainWindow:0"."SearchDiskFiles" = "";
      "kate/anonymous.katesession"."Plugin:katesearchplugin:MainWindow:0"."SearchDiskFiless" = "";
      "kate/anonymous.katesession"."Plugin:katesearchplugin:MainWindow:0"."SizeLimit" = 128;
      "kate/anonymous.katesession"."Plugin:katesearchplugin:MainWindow:0"."UseRegExp" = false;
    };
  };

  programs = {
    wezterm = {
      enable = true;
      extraConfig = ''
        return {
          font = wezterm.font("Monocraft NerdFont"),
          font_size = 13.0,
          color_scheme = "catppuccin-mocha",
          hide_tab_bar_if_only_one_tab = true,
          window_padding = {
            left = 0,
            right = 0,
            top = 0,
            bottom = 0,
          }
        }
      '';
    };
    gh = {
      enable = true;
      settings = {
        git_protocol = "ssh";
      };
    };
    gh-dash = {
      enable = true;
    };
    zoxide = {
      enable = true;
      enableBashIntegration = true;
      enableFishIntegration = true;
    };
    # i3status-rust = {
    #   enable = true;
    # };
    swaylock = {
      enable = true;
    };
    fish = {
      enable = true;
      interactiveShellInit = ''
        set fish_greeting
        function fish_command_not_found
          ${pkgs.nodejs}/bin/node ~/git/cloudflare-ai-cli/src/client.mjs "$argv"
        end
      '';
      plugins = [
        {
          name = "autopair.fish";
          src = pkgs.fetchFromGitHub {
            owner = "jorgebucaran";
            repo = "autopair.fish";
            rev = "4d1752ff5b39819ab58d7337c69220342e9de0e2";
            sha256 = "sha256-qt3t1iKRRNuiLWiVoiAYOu+9E7jsyECyIqZJ/oRIT1A=";
          };
        }
        {
          name = "puffer-fish";
          src = pkgs.fetchFromGitHub {
            owner = "nickeb96";
            repo = "puffer-fish";
            rev = "12d062eae0ad24f4ec20593be845ac30cd4b5923";
            sha256 = "sha256-2niYj0NLfmVIQguuGTA7RrPIcorJEPkxhH6Dhcy+6Bk=";
          };
        }
      ];
    };
    bash = {
      enable = true;
      initExtra = ''
        command_not_found_handle() {
          ${pkgs.nodejs}/bin/node ~/git/cloudflare-ai-cli/src/client.mjs "$@"
        }
      '';
      sessionVariables = {
        OBS_VKCAPTURE = "1";
        FLATPAK_GL_DRIVERS = "mesa-git";
        WLR_RENDERER = "vulkan";
        MANGOHUD = "1";
        MANGOHUD_CONFIGFILE = "/home/codebam/.config/MangoHud/MangoHud.conf";
        PROTON_ENABLE_WAYLAND = "1";
        DXVK_HDR = "1";
        # ENABLE_HDR_WSI = "1";
        # PROTON_USE_NTSYNC = "1";
        # WINE_NTSYNC = "1";
        # WINEFSYNC = 0;
        # WINEESYNC = 0;
        # WINEFSYNC_FUTEX2 = 0;
        # WINESYNC = 1;
      };
    };
    neovim = {
      enable = true;
      defaultEditor = true;
      extraLuaPackages = ps: [ ps.jsregexp ];
      extraLuaConfig = ''

        require('gen').setup({
            model = "qwen2.5-coder:32b", -- The default model to use.
            quit_map = "q", -- set keymap to close the response window
            retry_map = "<c-r>", -- set keymap to re-send the current prompt
            accept_map = "<c-cr>", -- set keymap to replace the previous selection with the last result
            host = "localhost", -- The host running the Ollama service.
            port = "11434", -- The port on which the Ollama service is listening.
            display_mode = "split", -- The display mode. Can be "float" or "split" or "horizontal-split".
            show_prompt = true, -- Shows the prompt submitted to Ollama. Can be true (3 lines) or "full".
            show_model = true, -- Displays which model you are using at the beginning of your chat session.
            no_auto_close = true, -- Never closes the window automatically.
            file = false, -- Write the payload to a temporary file to keep the command short.
            hidden = false, -- Hide the generation window (if true, will implicitly set `prompt.replace = true`), requires Neovim >= 0.10
            init = function(options) pcall(io.popen, "ollama serve > /dev/null 2>&1 &") end,
            -- Function to initialize Ollama
            command = function(options)
                local body = {model = options.model, stream = true}
                return "curl --silent --no-buffer -X POST http://" .. options.host .. ":" .. options.port .. "/api/chat -d $body"
            end,
            -- The command for the Ollama service. You can use placeholders $prompt, $model and $body (shellescaped).
            -- This can also be a command string.
            -- The executed command must return a JSON object with { response, context }
            -- (context property is optional).
            -- list_models = '<omitted lua function>', -- Retrieves a list of model names
            result_filetype = "markdown", -- Configure filetype of the result buffer
            debug = false -- Prints errors and the command which is run.
        })
        require('nvim-treesitter.configs').setup {
          auto_install = false,
          ignore_install = {},
          highlight = {
            enable = true,
            additional_vim_regex_highlighting = false,
          },
          indent = {
            enable = true
          },
        }

        local on_attach = function(client, bufnr)
          require("lsp-format").on_attach(client, bufnr)
        end

        require("lsp-format").setup{}
        require('lspconfig').ts_ls.setup { on_attach = on_attach }
        require('lspconfig').eslint.setup { on_attach = on_attach }
        require('lspconfig').jdtls.setup { on_attach = on_attach }
        require('lspconfig').kotlin_language_server.setup { on_attach = on_attach }
        require('lspconfig').svelte.setup { on_attach = on_attach }
        require('lspconfig').bashls.setup { on_attach = on_attach }
        require('lspconfig').pyright.setup { on_attach = on_attach }
        require('lspconfig').nil_ls.setup { on_attach = on_attach }
        require('lspconfig').clangd.setup { on_attach = on_attach }
        require('lspconfig').html.setup { on_attach = on_attach }
        require('lspconfig').rust_analyzer.setup { on_attach = on_attach }
        require('lspconfig').csharp_ls.setup { on_attach = on_attach }
        require('lspconfig').sqls.setup {}

        local prettier = {
          formatCommand = [[prettier --stdin-filepath ''${INPUT} ''${--tab-width:tab_width}]],
          formatStdin = true,
        }
        require("lspconfig").efm.setup {
          on_attach = on_attach,
          init_options = { documentFormatting = true },
          settings = {
            languages = {
              typescript = { prettier },
              html = { prettier },
              javascript = { prettier },
              json = { prettier },
            },
          },
        }

        local capabilities = require("cmp_nvim_lsp").default_capabilities()

        local luasnip = require('luasnip')
        require("luasnip.loaders.from_vscode").lazy_load()

        local cmp = require('cmp')
        cmp.setup {
          snippet = {
            expand = function(args)
              luasnip.lsp_expand(args.body)
            end,
          },
          mapping = cmp.mapping.preset.insert({
            ['<C-u>'] = cmp.mapping.scroll_docs(-4), -- Up
            ['<C-d>'] = cmp.mapping.scroll_docs(4), -- Down
            -- C-b (back) C-f (forward) for snippet placeholder navigation.
            ['<C-Space>'] = cmp.mapping.complete(),
            ['<CR>'] = cmp.mapping.confirm {
              behavior = cmp.ConfirmBehavior.Replace,
              select = true,
            },
            ['<Tab>'] = cmp.mapping(function(fallback)
              if cmp.visible() then
                cmp.select_next_item()
              elseif luasnip.expand_or_jumpable() then
                luasnip.expand_or_jump()
              else
                fallback()
              end
            end, { 'i', 's' }),
            ['<S-Tab>'] = cmp.mapping(function(fallback)
              if cmp.visible() then
                cmp.select_prev_item()
              elseif luasnip.jumpable(-1) then
                luasnip.jump(-1)
              else
                fallback()
              end
            end, { 'i', 's' }),
          }),
          sources = {
            { name = 'nvim_lsp' },
            { name = 'luasnip' },
          },
        }
      '';
      extraConfig = ''
        set guicursor=n-v-c-i:block
        set nowrap
        colorscheme catppuccin_mocha
        let g:lightline = {
              \ 'colorscheme': 'catppuccin_mocha',
              \ }
        map <leader>ac :lua vim.lsp.buf.code_action()<CR>
        map <leader><space> :nohl<CR>
        nnoremap <leader>ff <cmd>Telescope find_files<cr>
        nnoremap <leader>fd <cmd>Telescope diagnostics<cr>
        nnoremap <leader>fg <cmd>Telescope live_grep<cr>
        nnoremap <leader>fb <cmd>Telescope buffers<cr>
        nnoremap <leader>fh <cmd>Telescope help_tags<cr>
        set ts=2
        set undofile
        set undodir=$HOME/.vim/undodir
        let g:augment_workspace_folders = ['~/git/seanbehan.ca', '~/git/cf-workers-telegram-bot']
      '';
      plugins = [
        pkgs.vimPlugins.catppuccin-vim
        pkgs.vimPlugins.cmp_luasnip
        pkgs.vimPlugins.cmp-nvim-lsp
        pkgs.vimPlugins.codi-vim
        pkgs.vimPlugins.commentary
        pkgs.vimPlugins.friendly-snippets
        pkgs.vimPlugins.fugitive
        pkgs.vimPlugins.gitgutter
        pkgs.vimPlugins.telescope-nvim
        pkgs.vimPlugins.lightline-vim
        pkgs.vimPlugins.lsp-format-nvim
        pkgs.vimPlugins.luasnip
        pkgs.vimPlugins.nvim-cmp
        pkgs.vimPlugins.nvim-lspconfig
        pkgs.vimPlugins.nvim-web-devicons
        pkgs.vimPlugins.plenary-nvim
        pkgs.vimPlugins.sensible
        pkgs.vimPlugins.sleuth
        pkgs.vimPlugins.surround
        pkgs.vimPlugins.todo-comments-nvim
        pkgs.vimPlugins.nvim-treesitter.withAllGrammars
        pkgs.vimPlugins.augment-vim
        pkgs.vimPlugins.gen-nvim
      ];
    };
    # vim = {
    #   enable = true;
    #   settings = {
    #     background = "dark";
    #     expandtab = true;
    #     ignorecase = true;
    #     shiftwidth = 4;
    #     smartcase = true;
    #     tabstop = 8;
    #     undodir = [ "$HOME/.vim/undodir" ];
    #   };
    #   extraConfig = ''
    #     colorscheme catppuccin_mocha
    #     let g:lightline = {
    #           \ 'colorscheme': 'catppuccin_mocha',
    #           \ }
    #     let g:coc_disable_startup_warning = 1
    #     map <leader>ac <Plug>(coc-codeaction-cursor)
    #   '';
    #   plugins = [
    #     pkgs.vimPlugins.sensible
    #     pkgs.vimPlugins.coc-nvim
    #     pkgs.vimPlugins.coc-pyright
    #     pkgs.vimPlugins.coc-prettier
    #     pkgs.vimPlugins.coc-eslint
    #     pkgs.vimPlugins.coc-snippets
    #     pkgs.vimPlugins.coc-json
    #     pkgs.vimPlugins.coc-svelte
    #     pkgs.vimPlugins.commentary
    #     pkgs.vimPlugins.sleuth
    #     pkgs.vimPlugins.surround
    #     pkgs.vimPlugins.fugitive
    #     pkgs.vimPlugins.gitgutter
    #     pkgs.vimPlugins.vim-javascript
    #     pkgs.vimPlugins.lightline-vim
    #     pkgs.vimPlugins.todo-comments-nvim
    #     pkgs.vimPlugins.vim-snippets
    #     pkgs.vimPlugins.catppuccin-vim
    #   ];
    # };
    git = {
      enable = true;
      userEmail = "codebam@riseup.net";
      userName = "Sean Behan";
      extraConfig = {
        merge = {
          tool = "nvimdiff";
        };
      };
    };
    tmux = {
      enable = true;
      terminal = "tmux-256color";
      prefix = "C-a";
      mouse = true;
      keyMode = "vi";
      clock24 = true;
      # plugins = with pkgs; [
      #   pkgs.tmuxPlugins.resurrect
      # ];
      extraConfig = ''
        set -ga terminal-overrides ",*256col*:Tc"
        bind-key C-a last-window
        bind-key a send-prefix
        bind-key b set status
        bind s split-window -v
        bind v split-window -h
        bind h select-pane -L
        bind j select-pane -D
        bind k select-pane -U
        bind l select-pane -R
        set -sg escape-time 300
      '';
    };

    # kitty = {
    #   enable = true;
    #   font = {
    #     name = "Fira Code Nerdfont";
    #     size = 12.0;
    #   };
    #   shellIntegration.mode = "no-cursor";
    #   settings = {
    #     cursor_shape = "block";
    #     cursor_blink_interval = 0;
    #   };
    # };

    foot = {
      enable = true;
      settings = {
        main = {
          term = "xterm-256color";
          font = "Fira Code Nerdfont:size=8";
          dpi-aware = "yes";
        };
        mouse = {
          hide-when-typing = "yes";
        };
        bell = {
          urgent = "yes";
          command = "${pkgs.pipewire}/bin/pw-play /run/current-system/sw/share/sounds/freedesktop/stereo/bell.oga";
          command-focused = "yes";
        };
        colors = {
          alpha = 1.0;
        };
      };
    };
    wofi = {
      enable = true;
      settings = {
        show = "drun";
        dmenu = true;
        insensitive = true;
        prompt = "";
        width = "25%";
        lines = 5;
        location = "center";
        hide_scroll = true;
        allow_images = true;
      };
    };
    direnv = {
      enable = true;
      enableBashIntegration = true;
      nix-direnv.enable = true;
    };
    fzf = {
      enable = true;
      enableBashIntegration = true;
      enableFishIntegration = true;
      defaultOptions = [
        "--no-height"
        "--no-reverse"
      ];
      tmux = {
        enableShellIntegration = true;
      };
    };

    starship = {
      enable = true;
      enableBashIntegration = true;
      enableFishIntegration = true;
    };

    tiny = {
      enable = true;
    };

    senpai = {
      enable = true;
      config = {
        address = "chat.sr.ht:6697";
        nickname = "codebam";
        password-cmd = [
          "pass"
          "show"
          "chat.sr.ht"
        ];
      };
    };

    ncmpcpp = {
      enable = true;
      bindings = [
        {
          key = "j";
          command = "scroll_down";
        }
        {
          key = "k";
          command = "scroll_up";
        }
        {
          key = "J";
          command = [
            "select_item"
            "scroll_down"
          ];
        }
        {
          key = "K";
          command = [
            "select_item"
            "scroll_up"
          ];
        }
      ];
      settings = {
        song_list_format = " $0%n $1• $8%t $R$0%a ";
        song_columns_list_format = "(3)[]{}(85)[white]{t} (1)[blue]{a}";
        song_status_format = " $3%t $0 $1%a ";
        playlist_display_mode = "columns";
        now_playing_prefix = "$3>";
        now_playing_suffix = "$8$/b";
        browser_playlist_prefix = "$2 ♥ $0 ";
        playlist_disable_highlight_delay = "1";
        message_delay_time = "1";
        progressbar_look = "━━─";
        progressbar_color = "black";
        progressbar_elapsed_color = "green";
        colors_enabled = "yes";
        empty_tag_color = "red";
        statusbar_color = "black";
        state_line_color = "black";
        state_flags_color = "green";
        main_window_color = "green";
        header_window_color = "black";
        display_bitrate = "yes";
        autocenter_mode = "yes";
        centered_cursor = "yes";
        titles_visibility = "no";
        statusbar_visibility = "yes";
        empty_tag_marker = " -- ‼ -- ";
        mouse_support = "no";
        header_visibility = "no";
        display_remaining_time = "no";
        ask_before_clearing_playlists = "no";
        discard_colors_if_item_is_selected = "yes";
      };
    };
    home-manager.enable = true;
  };

  services = {
    mako = {
      enable = true;
      layer = "overlay";
      font = "Noto Sans";
      defaultTimeout = 5000;
    };
    mopidy = {
      enable = true;
      extensionPackages = with pkgs; [
        mopidy-mpd
        mopidy-ytmusic
      ];
      settings = {
        ytmusic = {
          oauth_json = "/home/codebam/Downloads/oauth.json";
        };
      };
    };
  };

  gtk = {
    # enable = true;
  };

  xdg = {
    enable = true;
  };

  catppuccin = {
    enable = true;
    flavor = "mocha";
    accent = "blue";
  };
}
