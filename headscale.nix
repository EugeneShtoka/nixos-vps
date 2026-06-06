{ config, pkgs, lib, ... }:
{
  # After first boot: sudo tailscale up --login-server https://headscale.cloud-surf.com
  # Generate preauthkey: headscale preauthkeys create -u 1 --reusable --expiration 2h
  # v0.27 quirk: preauthkeys create requires numeric user ID, not name
  services.tailscale.enable = true;

  # Restore: copy ~/Backups/Server/headscale/{db.sqlite,noise_private.key}
  #          to /var/lib/headscale/ before starting the service.
  services.headscale = {
    enable  = true;
    package = pkgs.headscale;
    address = "127.0.0.1";
    port    = 8085;
    settings = {
      server_url          = "https://headscale.cloud-surf.com";
      metrics_listen_addr = "127.0.0.1:9090";
      database = {
        type        = "sqlite3";
        sqlite.path = "/var/lib/headscale/db.sqlite";
      };
      noise.private_key_path = "/var/lib/headscale/noise_private.key";
      prefixes = {
        v4 = "100.64.0.0/10";
        v6 = "fd7a:115c:a1e0::/48";
      };
      dns = {
        magic_dns           = true;
        base_domain         = "vpn.cloud-surf.com";
        nameservers.global  = [ "100.64.0.1" ];
      };
    };
  };
}
