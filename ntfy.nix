{ config, pkgs, lib, ... }:
{
  services.ntfy-sh = {
    enable   = true;
    settings.base-url = "https://ntfy.cloud-surf.com";
  };
}
