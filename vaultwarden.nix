{ config, pkgs, lib, ... }:
{
  # Restore: copy ~/Backups/Vaultwarden/{db.sqlite3,rsa_key.pem,rsa_key.pub.pem,attachments/}
  #          to /var/lib/vaultwarden/ then: chown -R vaultwarden:vaultwarden /var/lib/vaultwarden
  services.vaultwarden = {
    enable = true;
    config = {
      DOMAIN            = "https://vault.cloud-surf.com";
      ROCKET_ADDRESS    = "127.0.0.1";
      ROCKET_PORT       = 8080;
      SIGNUPS_ALLOWED   = false;
      WEBSOCKET_ENABLED = true;
      DATA_FOLDER       = "/var/lib/vaultwarden";
    };
  };
}
