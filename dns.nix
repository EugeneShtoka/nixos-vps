{ config, pkgs, lib, ... }:
{
  # ── Unbound — Pi-hole upstream resolver ──────────────────────────────────────
  # Listens on :5335 to avoid conflicting with Pi-hole on :53.
  # Custom VPN-only hostnames live here (not in Pi-hole — FTL v6 ignores dnsmasq.d
  # address= directives; FTLCONF_dns_hosts format is non-obvious for arrays).
  services.unbound = {
    enable = true;
    settings.server = {
      interface      = [ "127.0.0.1@5335" ];
      access-control = [
        "127.0.0.0/8 allow"
        "10.88.0.0/16 allow"    # podman default bridge
        "100.64.0.0/10 allow"   # VPN clients
      ];
      do-ip4                 = true;
      do-ip6                 = false;
      do-udp                 = true;
      do-tcp                 = true;
      hide-identity          = true;
      hide-version           = true;
      harden-glue            = true;
      harden-dnssec-stripped = true;
      edns-buffer-size       = 1232;
      prefetch               = true;
      private-address = [
        "192.168.0.0/16" "169.254.0.0/16"
        "172.16.0.0/12"  "10.0.0.0/8"
        "fd00::/8"        "fe80::/10"
      ];
      # VPN-only services — no public A records in Cloudflare
      local-data = [
        ''"vault.cloud-surf.com. A 100.64.0.1"''
        ''"git.cloud-surf.com. A 100.64.0.1"''
        ''"syncthing.cloud-surf.com. A 100.64.0.1"''
        ''"seer.cloud-surf.com. A 100.64.0.1"''
        ''"netdata.cloud-surf.com. A 100.64.0.1"''
        ''"immich.cloud-surf.com. A 100.64.0.1"''
        ''"matrix.cloud-surf.com. A 100.64.0.1"''
        ''"ntfy.cloud-surf.com. A 100.64.0.1"''
      ];
    };
    settings.forward-zone = [{
      name         = ".";
      forward-addr = [ "9.9.9.9" "149.112.112.112" ];
    }];
    settings.remote-control.control-enable = false;
  };

  # ── Pi-hole (rootful podman, host networking) ─────────────────────────────────
  # Restore: copy ~/Backups/Server/pihole/ to /var/lib/pihole/
  # Pi-hole listens on 100.64.0.1:53 (VPN interface).
  # The podman gateway 10.88.0.1 is Pi-hole's upstream → Unbound.
  virtualisation.podman.enable              = true;
  virtualisation.oci-containers.backend     = "podman";

  sops.templates."pihole.env".content =
    "FTLCONF_webserver_password=${config.sops.placeholder."pihole-webpassword"}";

  virtualisation.oci-containers.containers.pihole = {
    image   = "pihole/pihole:latest";
    volumes = [
      "/var/lib/pihole/etc:/etc/pihole"
      "/var/lib/pihole/dnsmasq.d:/etc/dnsmasq.d"
    ];
    environmentFiles = [ config.sops.templates."pihole.env".path ];
    environment = {
      TZ                        = "UTC";
      FTLCONF_dns_upstreams     = "127.0.0.1#5335";   # unbound on host loopback
      FTLCONF_dns_listeningMode = "ALL";
      FTLCONF_dns_use_ipv6      = "false";
      FTLCONF_webserver_port    = "8083";
    };
    extraOptions = [
      "--network=host"
      "--cap-add=NET_ADMIN"
    ];
  };

  systemd.services.podman-pihole.after = lib.mkAfter [ "unbound.service" ];
  systemd.services.podman-pihole.wants = [ "unbound.service" ];

  systemd.tmpfiles.rules = [
    "d /var/lib/pihole/etc       0750 root root -"
    "d /var/lib/pihole/dnsmasq.d 0750 root root -"
  ];
}
