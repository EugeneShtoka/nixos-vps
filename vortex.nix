{ config, pkgs, lib, ... }:
let
  vortexd = pkgs.rustPlatform.buildRustPackage {
    pname   = "vortexd";
    version = "0.1.0";
    src = pkgs.fetchFromGitHub {
      owner  = "EugeneShtoka";
      repo   = "vortex";
      rev    = "aea7db4adc78a021186147fd832c648434c2a22c";
      hash   = "sha256-teLoSOxf9yuXB+kyM8DVXgjLiNaf4Isg6aIB2uD8NKo=";
    };
    cargoLock.lockFile = ./vortex-Cargo.lock;
    cargoBuildFlags    = [ "-p" "vortexd" ];
    doCheck            = false;
  };
in {
  users.groups.vortex = {};
  users.users.vortex = {
    isSystemUser = true;
    group        = "vortex";
  };

  environment.etc."vortex/vortex.toml" = {
    mode  = "0640";
    user  = "vortex";
    group = "vortex";
    text  = ''
      [server]
      unix_socket = "/run/vortex/vortex.sock"
      db_path     = "/var/lib/vortex/state.db"

      [workflows.mx-message]
      tasks = [
        { id = "passthrough", exec = "printf '{\"text\":\"%s\",\"destination\":\"%s\"}' '{{trigger.text}}' '{{trigger.room}}'" },
      ]
    '';
  };

  systemd.services.vortexd = {
    description = "vortexd workflow daemon";
    after       = [ "network.target" ];
    wantedBy    = [ "multi-user.target" ];
    serviceConfig = {
      User                 = "vortex";
      Group                = "vortex";
      ExecStart            = "${vortexd}/bin/vortexd /etc/vortex/vortex.toml";
      RuntimeDirectory     = "vortex";
      RuntimeDirectoryMode = "0770";
      StateDirectory       = "vortex";
      UMask                = "0007";
      Restart              = "on-failure";
      RestartSec           = "5s";
      StandardOutput       = "journal";
      StandardError        = "journal";
      SyslogIdentifier     = "vortexd";
    };
  };
}
