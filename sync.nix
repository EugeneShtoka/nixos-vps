{ config, pkgs, lib, ... }:
{
  # After first boot: re-share the send-only backup folders via the web UI.
  # UI at: https://syncthing.cloud-surf.com (VPN-only)
  services.syncthing = {
    enable           = true;
    user             = "syncthing";
    dataDir          = "/var/lib/syncthing";
    guiAddress       = "127.0.0.1:8384";
    openDefaultPorts = false;   # port 22000 opened explicitly in hardening.nix
  };
}
