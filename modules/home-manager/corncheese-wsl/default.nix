{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.corncheese.wsl;
  npiperelayPath = "/mnt/c/ProgramData/chocolatey/lib/npiperelay/tools/npiperelay.exe";
in
{
  options = {
    corncheese.wsl = {
      _1password.enable = lib.mkEnableOption "WSL 1Password integration";
    };
  };

  config = lib.mkMerge [
    (lib.mkIf cfg._1password.enable {
      home = {
        file.".1password/.keep".text = ""; # Create ~/.1password directory
        file.".agent-bridge.sh" = {
          executable = true;
          text = ''
            # Configure ssh forwarding
            export SSH_AUTH_SOCK=$HOME/.1password/agent.sock
            # need `ps -ww` to get non-truncated command for matching
            # use square brackets to generate a regex match for the process we want but that doesn't match the grep command running it!
            ALREADY_RUNNING=$(ps -auxww | grep -q "[n]piperelay.exe -ei -s //./pipe/openssh-ssh-agent"; echo $?)
            if [[ $ALREADY_RUNNING != "0" ]]; then
                if [[ -S $SSH_AUTH_SOCK ]]; then
                    # not expecting the socket to exist as the forwarding command isn't running (http://www.tldp.org/LDP/abs/html/fto.html)
                    echo "removing previous socket..."
                    rm $SSH_AUTH_SOCK
                fi
                echo "Starting SSH-Agent relay..."
                # setsid to force new session to keep running
                # set socat to listen on $SSH_AUTH_SOCK and forward to npiperelay which then forwards to openssh-ssh-agent on windows
                (setsid socat UNIX-LISTEN:$SSH_AUTH_SOCK,fork EXEC:"${npiperelayPath} -ei -s //./pipe/openssh-ssh-agent",nofork &) >/dev/null 2>&1
            fi
          '';
        };

        packages = [ pkgs.socat ];
      };

      programs.bash.initExtra = ''
        source ${config.home.homeDirectory}/.agent-bridge.sh
      '';
      programs.zsh.initExtra = ''
        source ${config.home.homeDirectory}/.agent-bridge.sh
      '';
    })
  ];
}
