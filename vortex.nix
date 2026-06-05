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

  systemd.services.vortexd = {
    description = "vortexd workflow daemon";
    after       = [ "network.target" ];
    wantedBy    = [ "multi-user.target" ];
    serviceConfig = {
      User                 = "vortex";
      Group                = "vortex";
      # Copy config from git repo (root-readable) into the service's own state dir,
      # so workflow changes only need `git pull && systemctl restart vortexd`.
      ExecStartPre         = "+${pkgs.coreutils}/bin/cp /home/eugene/nixos-vps/vortex.toml /var/lib/vortex/vortex.toml";
      ExecStart            = "${vortexd}/bin/vortexd /var/lib/vortex/vortex.toml";
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
