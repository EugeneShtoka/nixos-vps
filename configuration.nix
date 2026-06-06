{ config, pkgs, lib, pkgs-unstable, sops-nix, ... }:
{
  imports = [
    ./base.nix
    ./secrets.nix
    ./hardening.nix
    ./headscale.nix
    ./pihole.nix
    ./vaultwarden.nix
    ./forgejo.nix
    ./searxng.nix
    ./syncthing.nix
    ./netdata.nix
    ./tinyproxy.nix
    ./ntfy.nix
    ./nginx.nix
    ./backup.nix
    ./vortex.nix
    ./matrix.nix
  ];
}
