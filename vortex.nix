{ config, pkgs, lib, ... }:
let
  vortexd = pkgs.rustPlatform.buildRustPackage {
    pname   = "vortexd";
    version = "0.1.0";
    src = pkgs.fetchFromGitHub {
      owner  = "EugeneShtoka";
      repo   = "vortex";
      rev    = "a809bf98f49c6f1f3a0ecdc8d3d726c543e697d2";
      hash   = "sha256-5Hw6PSGNkZRzkj9ONHmIw6B7B57k6xyCBPRIHfq5myQ=";
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
      ExecStartPre         = "+${pkgs.coreutils}/bin/install -m 0640 -o vortex -g vortex /home/eugene/nixos-vps/vortex.toml /var/lib/vortex/vortex.toml";
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
