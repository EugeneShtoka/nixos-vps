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
      hash   = "sha256-YVJgJmF78xuc06hoqrknvWJSE0bzJAXN8Ck/1W0g0nY=";
    };
    cargoLock.lockFile = ./vortex-Cargo.lock;
    cargoBuildFlags    = [ "-p" "vortexd" ];
    doCheck            = false;
  };
  # Extracts as_token from the already-decrypted mx-proxy-config sops secret
  # and writes it as MATRIX_ACCESS_TOKEN=<value> into the vortexd state dir.
  extractMatrixToken = pkgs.writeShellScript "extract-matrix-token" ''
    TOKEN=$(${pkgs.gnugrep}/bin/grep 'as_token' ${config.sops.secrets.mx-proxy-config.path} \
      | ${pkgs.gnused}/bin/sed 's/.*= "\(.*\)"/\1/')
    printf 'MATRIX_ACCESS_TOKEN=%s\n' "$TOKEN" > /var/lib/vortex/matrix-token.env
    chown orchestrator:orchestrator /var/lib/vortex/matrix-token.env
    chmod 0400 /var/lib/vortex/matrix-token.env
  '';
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
    path        = [ jx-match clipkit pkgs.jq pkgs.curl ];
    serviceConfig = {
      User                 = "orchestrator";
      Group                = "orchestrator";
      # Copy config + scripts, then extract the Matrix AS token from the
      # already-decrypted mx-proxy sops secret into matrix-token.env.
      ExecStartPre         = [
        "+${pkgs.coreutils}/bin/install -m 0640 -o orchestrator -g orchestrator /home/eugene/nixos-vps/vortex.toml /var/lib/vortex/vortex.toml"
        "+${pkgs.coreutils}/bin/install -m 0750 -o orchestrator -g orchestrator /home/eugene/nixos-vps/scripts/check-space.sh /var/lib/vortex/check-space.sh"
        "+${extractMatrixToken}"
      ];
      # matrix-token.env is written by ExecStartPre above; optional on first start.
      EnvironmentFile      = [
        "/home/eugene/nixos-vps/matrix-env"
        "-/var/lib/vortex/matrix-token.env"
      ];
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
