{ config, pkgs, lib, pkgs-vaultwarden, ... }:
{
  # Restore: copy ~/Backups/Vaultwarden/{db.sqlite3,rsa_key.pem,rsa_key.pub.pem,attachments/}
  #          to /var/lib/vaultwarden/ then: chown -R vaultwarden:vaultwarden /var/lib/vaultwarden
  services.vaultwarden = {
    enable = true;
    # Pinned ahead of stable nixpkgs: Bitwarden clients >= 2026.7.0 require
    # server >= 1.37.0 (25.11 stable still ships 1.36.0). See flake input.
    package = pkgs-vaultwarden.vaultwarden;
    config = {
      DOMAIN            = "https://vault.cloud-surf.com";
      ROCKET_ADDRESS    = "127.0.0.1";
      ROCKET_PORT       = 8080;
      SIGNUPS_ALLOWED   = true;
      WEBSOCKET_ENABLED = true;
      DATA_FOLDER       = "/var/lib/vaultwarden";
    };
  };
}
