{ config, pkgs, lib, ... }:
let
  jx-match = pkgs.buildGoModule {
    pname   = "jx-match";
    version = "0.1.0";
    src = pkgs.fetchFromGitHub {
      owner = "EugeneShtoka";
      repo  = "jx-match";
      rev   = "15424a70faa8fec49789e4dc83f1868f0da5ef1f";
      hash  = "sha256-xjc9uXYIQdYdE+JZrNWOq2xSRKkzq4T1VltjbASv+jg=";
    };
    vendorHash = "sha256-hzG7gFveP7vex+C52vsKqVguL3Quqtdh6HgSkT2dQaQ=";
  };

  clipkit = pkgs.buildGoModule {
    pname   = "clipkit";
    version = "0.1.0";
    src = pkgs.fetchFromGitHub {
      owner = "EugeneShtoka";
      repo  = "clipkit";
      rev   = "d533770d29eae21812f4508ebf164d7890fb36a2";
      hash  = "sha256-geMO+miqq7NHIXXIrxpC9Gxfm7v27P3F1AoGxqOe08s=";
    };
    vendorHash = null;
  };

  vortexd = pkgs.rustPlatform.buildRustPackage {
    pname   = "vortexd";
    version = "0.1.0";
    src = pkgs.fetchFromGitHub {
      owner  = "EugeneShtoka";
      repo   = "vortex";
      rev    = "cd259c34011d8afbb88c2d78b33bf633cf62007a";
      hash   = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";
    };
    cargoLock.lockFile = ./vortex-Cargo.lock;
    cargoBuildFlags    = [ "-p" "vortexd" ];
    doCheck            = false;
  };
in {
  users.groups.orchestrator = {};
  users.users.orchestrator = {
    isSystemUser = true;
    group        = "orchestrator";
  };

  systemd.services.vortexd = {
    description = "vortexd workflow daemon";
    after       = [ "network.target" ];
    wantedBy    = [ "multi-user.target" ];
    path        = [ jx-match clipkit ];
    serviceConfig = {
      User                 = "orchestrator";
      Group                = "orchestrator";
      # Copy config from git repo (root-readable) into the service's own state dir,
      # so workflow changes only need `git pull && systemctl restart vortexd`.
      ExecStartPre         = [
        "+${pkgs.coreutils}/bin/install -m 0640 -o orchestrator -g orchestrator /home/eugene/nixos-vps/vortex.toml /var/lib/vortex/vortex.toml"
        "+${pkgs.coreutils}/bin/install -m 0640 -o orchestrator -g orchestrator /home/eugene/nixos-vps/vortex-env  /var/lib/vortex/vortex-env"
      ];
      EnvironmentFile      = "/var/lib/vortex/vortex-env";
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
