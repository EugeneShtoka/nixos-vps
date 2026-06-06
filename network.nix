{ config, pkgs, lib, ... }:
{
  networking = {
    hostName   = "vps";
    useDHCP    = true;       # Hetzner Cloud pushes IP via DHCP
    nameservers = [ "127.0.0.1" ];   # Pi-hole on localhost → unbound → 9.9.9.9
  };

  time.timeZone      = "UTC";
  i18n.defaultLocale = "en_US.UTF-8";
}
