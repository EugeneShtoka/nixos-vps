{ config, pkgs, lib, sops-nix, ... }:
{
  sops = {
    defaultSopsFile = ./secrets.yaml;
    age.sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];
    # sops-install-secrets needs Go 1.25; use sops-nix's own build
    package = sops-nix.packages.${pkgs.system}.sops-install-secrets;
    secrets = {
      cloudflare-acme-env = { owner = "acme"; group = "acme"; };
      pihole-webpassword  = {};
      searxng-secret-key  = {};
      doublepuppet-token  = {};
      mx-proxy-config     = {
        sopsFile = ./mx-proxy-secrets.yaml;
        key      = "config";
        owner    = "matrix";
        group    = "matrix";
        mode     = "0640";
      };
    };
  };
}
