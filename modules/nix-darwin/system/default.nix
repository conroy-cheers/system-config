{ inputs, ... }:
{
  lib,
  pkgs,
  config,
  ...
}:

with lib;
let
  cfg = config.corncheese.system;
in
{
  imports = [ ];

  options = {
    corncheese.system = {
      enable = mkEnableOption "corncheese MacOS system config";
    };
  };

  config = mkIf cfg.enable {
    # programs.nix-index.enable = true;

    environment.systemPackages = [
      pkgs.zsh
      pkgs.nushell
    ];
    environment.shells = [
      pkgs.zsh
      pkgs.nushell
    ];

    security.pam.services.sudo_local.touchIdAuth = true;

    system = {
      startup = {
        chime = false;
      };

      keyboard = {
        remapCapsLockToControl = false;
        # nonUS.remapTilde = true;
        enableKeyMapping = true; # Allows for skhd
        userKeyMapping = [
          # { HIDKeyboardModifierMappingSrc = 30064771172; HIDKeyboardModifierMappingDst = 30064771125; }
          # { HIDKeyboardModifierMappingSrc = 30064771125; HIDKeyboardModifierMappingDst = 30064771172; }
        ];
      };

      defaults = {
        NSGlobalDomain = {
          AppleInterfaceStyle = "Dark";
          AppleInterfaceStyleSwitchesAutomatically = true;
          # Enable full keyboard access for all controls (e.g. enable Tab in modal dialogs)
          AppleKeyboardUIMode = 3;
          # Automatically show and hide the menu bar
          _HIHideMenuBar = false;
          # Expand save panel by default
          NSNavPanelExpandedStateForSaveMode = true;
          # Expand print panel by default
          PMPrintingExpandedStateForPrint = true;
          # Replace press-and-hold with key repeat
          ApplePressAndHoldEnabled = false;
          # Set a fast key repeat rate
          KeyRepeat = 2;
          # Shorten delay before key repeat begins
          InitialKeyRepeat = 12;
          # Save to local disk by default, not iCloud
          NSDocumentSaveNewDocumentsToCloud = false;
          # Disable autocorrect capitalization
          NSAutomaticCapitalizationEnabled = false;
          # Disable autocorrect smart dashes
          NSAutomaticDashSubstitutionEnabled = false;
          # Disable autocorrect adding periods
          NSAutomaticPeriodSubstitutionEnabled = false;
          # Disable autocorrect smart quotation marks
          NSAutomaticQuoteSubstitutionEnabled = false;
          # Disable autocorrect spellcheck
          NSAutomaticSpellingCorrectionEnabled = false;
          # Set resize animation time
          NSWindowResizeTime = 0.1;
          # Disable scrollbar animations
          NSScrollAnimationEnabled = false;
          # Disable automatic window animations
          NSAutomaticWindowAnimationsEnabled = false;
          # Switch workspace on application activate
          AppleSpacesSwitchOnActivate = true;
        };

        dock = {
          autohide = false;
          # Add translucency in dock for hidden applications
          showhidden = true;
          # Enable spring loading on all dock items
          enable-spring-load-actions-on-all-items = true;
          # Highlight hover effect in dock stack grid view
          mouse-over-hilite-stack = true;
          mineffect = "genie";
          orientation = "bottom";
          show-recents = false;
          tilesize = 44;

          persistent-apps = [
            { app = "/Applications/Safari.app"; }
            { app = "/System/Applications/Messages.app"; }
            { app = "/System/Applications/Mail.app"; }
            {
              spacer = {
                small = true;
              };
            }
            { app = "/Applications/Ghostty.app"; }
            { app = "${pkgs.slack}/Applications/Slack.app"; }
            { app = "${pkgs.element-desktop}/Applications/Element.app"; }
            { app = "/System/Applications/System\ Settings.app"; }
          ];
          persistent-others = [ "/Users/${config.system.primaryUser}/Downloads" ];
        };

        finder = {
          # Default Finder window set to column view
          FXPreferredViewStyle = "clmv";
          # Finder search in current folder by default
          FXDefaultSearchScope = "SCcf";
          # Show all extensions
          AppleShowAllExtensions = true;
          # Disable warning when changing file extension
          FXEnableExtensionChangeWarning = false;
          # Show full paths
          ShowPathbar = true;
          # Show POSIX paths in title
          _FXShowPosixPathInTitle = true;
          # Allow quitting of Finder application
          QuitMenuItem = true;
        };

        # Disable "Are you sure you want to open" dialog
        LaunchServices.LSQuarantine = false;
        # Disable trackpad tap to click
        trackpad.Clicking = false;

        # universalaccess = {
        #   # Zoom in with Control + Scroll Wheel
        #   closeViewScrollWheelToggle = true;
        #   closeViewZoomFollowsFocus = true;
        # };

        # Where to save screenshots
        screencapture.location = "~/Desktop";
      };

      # Settings that don't have an option in nix-darwin
      activationScripts.postActivation.text = ''
        echo "Disable disk image verification"
        defaults write com.apple.frameworks.diskimages skip-verify -bool true
        defaults write com.apple.frameworks.diskimages skip-verify-locked -bool true
        defaults write com.apple.frameworks.diskimages skip-verify-remote -bool true

        echo "Avoid creating .DS_Store files on network volumes"
        defaults write com.apple.desktopservices DSDontWriteNetworkStores -bool true

        echo "Disable the warning before emptying the Trash"
        defaults write com.apple.finder WarnOnEmptyTrash -bool false

        echo "Require password immediately after sleep or screen saver begins"
        defaults write com.apple.screensaver askForPassword -int 1
        defaults write com.apple.screensaver askForPasswordDelay -int 0

        echo "Allow apps from anywhere"
        SPCTL="$(spctl --status)"
        if ! [ "''${SPCTL}" = "assessments disabled" ]; then
            sudo spctl --master-disable
        fi

        # echo "Set hostname"
        # sudo scutil --set HostName $hostname

        ${
          inputs.mac-app-util.packages.${pkgs.stdenv.system}.default
        }/bin/mac-app-util sync-trampolines "/Applications/Nix Apps" "/Applications/Nix Trampolines"
      '';

      # User-level settings
      # activationScripts.postUserActivation.text = ''
      #   echo "Show the ~/Library folder"
      #   chflags nohidden ~/Library

      #   echo "Enable dock magnification"
      #   defaults write com.apple.dock magnification -bool true

      #   echo "Set dock magnification size"
      #   defaults write com.apple.dock largesize -int 48

      #   echo "Set dock autohide delays (0)"
      #   defaults write com.apple.dock autohide-time-modifier -float 0
      #   defaults write com.apple.dock autohide-delay -float 0
      #   defaults write com.apple.dock expose-animation-duration -float 0
      #   defaults write com.apple.dock springboard-show-duration -float 0
      #   defaults write com.apple.dock springboard-hide-duration -float 0
      #   defaults write com.apple.dock springboard-page-duration -float 0

      #   echo "Disable Hot Corners"
      #   ## wvous-**-corner
      #   ## 0 - Nothing
      #   ## 1 - Disabled
      #   ## 2 - Mission Control
      #   ## 3 - Notifications
      #   ## 4 - Show the desktop
      #   ## 5 - Start screen saver
      #   ##
      #   ## wvous-**-modifier
      #   ## 0 - _
      #   ## 131072 - Shift+_
      #   ## 1048576 - Command+_
      #   ## 524288 - Option+_
      #   ## 262144 - Control+_
      #   ##
      #   # Top Left
      #   defaults write com.apple.dock wvous-tl-corner -int 0
      #   # Top Right
      #   defaults write com.apple.dock wvous-tr-corner -int 0
      #   # Bottom Left
      #   defaults write com.apple.dock wvous-bl-corner -int 0
      #   # Bottom Right
      #   defaults write com.apple.dock wvous-br-corner -int 0

      #   echo "Disable Finder animations"
      #   defaults write com.apple.finder DisableAllAnimations -bool true

      #   echo "Disable Mail animations"
      #   defaults write com.apple.Mail DisableSendAnimations -bool true
      #   defaults write com.apple.Mail DisableReplyAnimations -bool true

      #   # echo "Disable \"Save in Keychain\" for pinentry-mac"
      #   # defaults write org.gpgtools.common DisableKeychain -bool yes

      #   echo "Disable bezels (volume/brightness popups)"
      #   launchctl unload -wF /System/Library/LaunchAgents/com.apple.OSDUIHelper.plist

      #   echo "Define dock icon function"
      #   __dock_item() {
      #       echo "${
      #         lib.pipe
      #           ''
      #             <dict>
      #               <key>
      #                 tile-data
      #               </key>
      #               <dict>
      #                 <key>
      #                   file-data
      #                 </key>
      #                 <dict>
      #                   <key>
      #                     _CFURLString
      #                   </key>
      #                   <string>
      #                     ''${1}
      #                   </string>
      #                   <key>
      #                     _CFURLStringType
      #                   </key>
      #                   <integer>
      #                     0
      #                   </integer>
      #                 </dict>
      #               </dict>
      #             </dict>
      #           ''
      #           [
      #             (lib.splitString "\n")
      #             (map
      #               (lib.flip lib.pipe
      #                 [
      #                   (builtins.match "[[:space:]]*(.*)")
      #                   head
      #                 ]))
      #             lib.concatStrings
      #           ]
      #       }"
      #   }

      #   echo "Choose and order dock icons"
      #   defaults write com.apple.dock persistent-apps -array \
      #       "$(__dock_item "/System/Applications/System Settings.app")"
      # '';
      # defaults write com.apple.dock persistent-apps -array \
      #     "$(__dock_item /Applications/1Password.app)" \
      #     "$(__dock_item ${pkgs.slack}/Applications/Slack.app)" \
      #     "$(__dock_item /System/Applications/Calendar.app)" \
      #     "$(__dock_item ${pkgs.firefox-bin}/Applications/Firefox.app)" \
      #     "$(__dock_item /System/Applications/Messages.app)" \
      #     "$(__dock_item /System/Applications/Mail.app)" \
      #     "$(__dock_item /Applications/Mimestream.app)" \
      #     "$(__dock_item /Applications/zoom.us.app)" \
      #     "$(__dock_item ${pkgs.discord}/Applications/Discord.app)" \
      #     "$(__dock_item /Applications/Obsidian.app)" \
      #     "$(__dock_item /System/Applications/System\ Settings.app)"
    };
  };

  meta = {
    maintainers = with lib.maintainers; [ conroy-cheers ];
  };
}
