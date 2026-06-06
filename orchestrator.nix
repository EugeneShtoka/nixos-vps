{ config, pkgs, lib, ... }:
let
  vortexd = pkgs.rustPlatform.buildRustPackage {
    pname   = "vortexd";
    version = "0.1.0";
    src = pkgs.fetchFromGitHub {
      owner  = "EugeneShtoka";
      repo   = "vortex";
      rev    = "bf0f474349ff2347d4d912dd751f03627a6b076d";
      hash   = "sha256-qV28iSbkPJxHWviNPx9XfYtr2ucSMKe8hht9tlwnmTc=";
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
    path        = [ pkgs.jq ];
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
