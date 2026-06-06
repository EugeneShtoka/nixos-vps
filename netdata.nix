{ config, pkgs, lib, ... }:
{
  services.netdata = {
    enable = true;
    config.global."bind to" = "127.0.0.1:19999";
  };
}
