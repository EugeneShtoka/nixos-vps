{ config, pkgs, lib, sops-nix, ... }:
{
  sops = {
    defaultSopsFile = ./secrets.yaml;
    age.sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];
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
      telegram-api-id         = { owner = "matrix"; group = "matrix"; };
      telegram-api-hash       = { owner = "matrix"; group = "matrix"; };
      matrix-access-token-env = { owner = "orchestrator"; group = "orchestrator"; mode = "0400"; };
    };
  };
}
