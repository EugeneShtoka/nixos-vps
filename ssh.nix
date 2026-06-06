{ config, pkgs, lib, ... }:
{
  services.openssh = {
    enable = true;
    ports  = [ 47293 ];
    settings = {
      PermitRootLogin        = "no";
      PasswordAuthentication = false;
      AllowTcpForwarding     = "yes";   # needed for tinyproxy SSH tunnel
      AllowAgentForwarding   = "no";
      MaxAuthTries           = 3;
      MaxSessions            = 2;
      ClientAliveCountMax    = 2;
      TCPKeepAlive           = "no";
      LogLevel               = "VERBOSE";
    };
  };
}
