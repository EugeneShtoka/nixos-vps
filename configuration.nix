{ config, pkgs, lib, pkgs-unstable, sops-nix, ... }:
{
  imports = [
    ./boot.nix
    ./network.nix
    ./nix.nix
    ./users.nix
    ./ssh.nix
    ./secrets.nix
    ./hardening.nix
    ./vpn.nix
    ./dns.nix
    ./password-manager.nix
    ./vcs.nix
    ./search.nix
    ./sync.nix
    ./monitoring.nix
    ./http-proxy.nix
    ./notifications.nix
    ./proxy.nix
    ./backup.nix
    ./messaging.nix
    ./orchestrator.nix
  ];

  environment.systemPackages = with pkgs; [
    git
    htop
    vim
    curl
    wget
    jq
    podman-compose
    crowdsec   # includes crowdsec-firewall-bouncer binary
  ];
}
