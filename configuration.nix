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
    ./headscale.nix
    ./dns.nix
    ./password-manager.nix
    ./vcs.nix
    ./searxng.nix
    ./syncthing.nix
    ./netdata.nix
    ./tinyproxy.nix
    ./ntfy.nix
    ./nginx.nix
    ./backup.nix
    ./orchestrator.nix
    ./messaging.nix
  ];
}
