{ config, pkgs, lib, ... }:
{
  users.users.eugene = {
    isNormalUser = true;
    extraGroups  = [ "wheel" ];
    openssh.authorizedKeys.keyFiles = [ ./keys/eugene.pub ];
  };
  security.sudo.wheelNeedsPassword = false;
}
