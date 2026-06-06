{ config, pkgs, lib, ... }:
{
  # NixOS forgejo module doesn't auto-create the user when a custom name is given.
  users.groups.git = {};
  users.users.git = {
    isSystemUser = true;
    group        = "git";
    home         = "/var/lib/forgejo";
    createHome   = false;
  };

  # user = "git" preserves git@git.cloud-surf.com clone URLs.
  # Restore: copy ~/Backups/Server/forgejo/ to /var/lib/forgejo/
  #          then: chown -R git:git /var/lib/forgejo
  services.forgejo = {
    enable   = true;
    package  = pkgs.forgejo;
    user     = "git";
    group    = "git";
    stateDir = "/var/lib/forgejo";
    settings = {
      server = {
        DOMAIN                  = "git.cloud-surf.com";
        ROOT_URL                = "https://git.cloud-surf.com";
        HTTP_ADDR               = "127.0.0.1";
        HTTP_PORT               = 3000;
        SSH_DOMAIN              = "git.cloud-surf.com";
        SSH_PORT                = 2222;
        SSH_LISTEN_PORT         = 2222;
        START_SSH_SERVER        = true;
        BUILTIN_SSH_SERVER_USER = "git";
      };
      service.DISABLE_REGISTRATION = true;
    };
  };

  systemd.tmpfiles.rules = [
    "d /var/lib/forgejo        0750 git git -"
    "d /var/lib/forgejo/custom 0750 git git -"
  ];
}
