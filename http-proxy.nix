{ config, pkgs, lib, ... }:
{
  # Access via SSH tunnel: ssh -L 8888:localhost:8888 vps
  services.tinyproxy = {
    enable   = true;
    settings = {
      Port             = 8888;
      Listen           = "127.0.0.1";
      Timeout          = 600;
      Allow            = "127.0.0.1";
      DisableViaHeader = true;
    };
  };
}
