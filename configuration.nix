{ config, pkgs, lib, pkgs-unstable, sops-nix, ... }:
{
  imports = [ ./vortex.nix ./matrix.nix ];

  # ── Boot ─────────────────────────────────────────────────────────────────────
  # BIOS boot — VM uses SeaBIOS (confirmed by console). Ubuntu had /boot/efi but
  # actually booted via BIOS (grub + EF02 partition). UEFI mode left no bootloader.
  boot.loader.grub.enable = true;  # device set automatically by disko via EF02 partition

  # Hetzner Cloud KVM/QEMU virtio drivers — required in initrd to find the disk
  boot.initrd.availableKernelModules = [ "virtio_pci" "virtio_blk" "virtio_scsi" "ata_piix" "uhci_hcd" "sd_mod" ];

  # ── Network ──────────────────────────────────────────────────────────────────
  networking = {
    hostName = "vps";
    useDHCP = true;        # Hetzner Cloud pushes IP via DHCP — no static config needed
    nameservers = [ "127.0.0.1" ];   # Pi-hole on localhost; Pi-hole → unbound → 9.9.9.9
    firewall = {
      enable = true;
      allowedTCPPorts = [
        80 443              # nginx
        47293               # SSH
        2222                # Forgejo built-in SSH (git clone)
        22000               # Syncthing sync protocol
      ];
      allowedUDPPorts = [
        41641               # WireGuard — headscale client connections
        22000               # Syncthing sync protocol
      ];
      trustedInterfaces = [ "tailscale0" ];  # VPN traffic bypasses firewall rules
    };
  };

  # ── Time / locale ─────────────────────────────────────────────────────────────
  time.timeZone = "UTC";
  i18n.defaultLocale = "en_US.UTF-8";

  # ── Nix ──────────────────────────────────────────────────────────────────────
  nix.settings.experimental-features = [ "nix-command" "flakes" ];
  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 30d";
  };

  # ── Secrets (sops-nix) ───────────────────────────────────────────────────────
  sops = {
    defaultSopsFile = ./secrets.yaml;
    age.sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];
    # sops-install-secrets needs Go 1.25; use sops-nix's own build, not our nixpkgs 24.11
    package = sops-nix.packages.${pkgs.system}.sops-install-secrets;
    secrets = {
      cloudflare-acme-env = { owner = "acme"; group = "acme"; };   # CF_DNS_API_TOKEN=<token>
      pihole-webpassword  = {};
      searxng-secret-key  = {};   # SEARXNG_SECRET_KEY=<token>
    };
  };

  # ── Users ─────────────────────────────────────────────────────────────────────
  # Copy your public key: cat ~/.ssh/id_ed25519.pub > ~/nixos-vps/keys/eugene.pub
  users.users.eugene = {
    isNormalUser = true;
    extraGroups = [ "wheel" ];
    openssh.authorizedKeys.keyFiles = [ ./keys/eugene.pub ];
  };
  security.sudo.wheelNeedsPassword = false;

  # ── SSH ──────────────────────────────────────────────────────────────────────
  services.openssh = {
    enable = true;
    ports = [ 47293 ];
    settings = {
      PermitRootLogin          = "no";
      PasswordAuthentication   = false;
      AllowTcpForwarding       = "yes";   # needed for tinyproxy SSH tunnel
      AllowAgentForwarding     = "no";
      MaxAuthTries             = 3;
      MaxSessions              = 2;
      ClientAliveCountMax      = 2;
      TCPKeepAlive             = "no";
      LogLevel                 = "VERBOSE";
    };
  };

  # ── Tailscale (VPN client — node in own headscale network) ───────────────────
  # After first boot run: sudo tailscale up --login-server https://headscale.cloud-surf.com
  # Use the preauthkey you generate: headscale preauthkeys create -u 2 --reusable --expiration 2h
  services.tailscale.enable = true;

  # ── Headscale ────────────────────────────────────────────────────────────────
  # NOTE: Check nixpkgs headscale version vs your backup DB version before deploy.
  # Run: nix search nixpkgs#headscale  (current nixpkgs 24.11 has ~v0.23)
  # If your backup DB is v0.28 format and nixpkgs has v0.23, restore will fail.
  # Fix: pin headscale via an overlay or use nixpkgs-unstable input for this package.
  #
  # Restore: copy ~/Backups/Server/headscale/{db.sqlite,noise_private.key}
  #          to /var/lib/headscale/ before starting the service.
  services.headscale = {
    enable   = true;
    package  = pkgs.headscale;
    address  = "127.0.0.1";
    port     = 8085;
    settings = {
      server_url            = "https://headscale.cloud-surf.com";
      metrics_listen_addr   = "127.0.0.1:9090";
      database = {
        type   = "sqlite3";
        sqlite.path = "/var/lib/headscale/db.sqlite";
      };
      noise.private_key_path = "/var/lib/headscale/noise_private.key";
      prefixes = {
        v4 = "100.64.0.0/10";
        v6 = "fd7a:115c:a1e0::/48";
      };
      dns = {
        magic_dns  = true;
        base_domain = "vpn.cloud-surf.com";
        nameservers.global = [ "100.64.0.1" "9.9.9.9" ];
        # Split DNS: route cloud-surf.com explicitly to Pi-hole so Tailscale's
        # rebinding protection doesn't drop the 100.64.x response
        nameservers.split."cloud-surf.com" = [ "100.64.0.1" ];
      };
    };
  };

  # ── Vaultwarden ──────────────────────────────────────────────────────────────
  # Restore: copy ~/Backups/Vaultwarden/{db.sqlite3,rsa_key.pem,rsa_key.pub.pem,attachments/}
  #          to /var/lib/vaultwarden/ then: chown -R vaultwarden:vaultwarden /var/lib/vaultwarden
  services.vaultwarden = {
    enable = true;
    config = {
      DOMAIN              = "https://vault.cloud-surf.com";
      ROCKET_ADDRESS      = "127.0.0.1";
      ROCKET_PORT         = 8080;
      SIGNUPS_ALLOWED     = false;
      WEBSOCKET_ENABLED   = true;
      DATA_FOLDER         = "/var/lib/vaultwarden";
    };
  };

  # ── Forgejo ──────────────────────────────────────────────────────────────────
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
    enable    = true;
    package   = pkgs.forgejo;
    user      = "git";
    group     = "git";
    stateDir  = "/var/lib/forgejo";
    settings  = {
      server = {
        DOMAIN            = "git.cloud-surf.com";
        ROOT_URL          = "https://git.cloud-surf.com";
        HTTP_ADDR         = "127.0.0.1";
        HTTP_PORT         = 3000;
        SSH_DOMAIN        = "git.cloud-surf.com";
        SSH_PORT          = 2222;
        SSH_LISTEN_PORT   = 2222;
        START_SSH_SERVER  = true;
        BUILTIN_SSH_SERVER_USER = "git";
      };
      service.DISABLE_REGISTRATION = true;
    };
  };

  # ── SearXNG ──────────────────────────────────────────────────────────────────
  # environmentFile must contain: SEARXNG_SECRET_KEY=<random string>
  # Generate one: python3 -c "import secrets; print(secrets.token_hex(32))"
  services.searx = {
    enable          = true;
    package         = pkgs.searxng;
    environmentFile = config.sops.secrets.searxng-secret-key.path;
    settings = {
      server = {
        port          = 8081;
        bind_address  = "127.0.0.1";
        base_url      = "https://seer.cloud-surf.com/";
        secret_key    = "@SEARXNG_SECRET_KEY@";
      };
      ui.default_theme  = "simple";
      search.safe_search = 0;
      outgoing = {
        request_timeout     = 6.0;
        max_request_timeout = 15.0;
        enable_http2        = true;
        pool_connections    = 100;
        pool_maxsize        = 20;
      };
      engines = [
        { name = "startpage"; engine = "startpage"; shortcut = "sp"; }
        # Google: mobile UI is less aggressively rate-limited from datacenter IPs
        { name = "google"; engine = "google"; shortcut = "g"; use_mobile_ui = true; }
      ];
    };
  };

  # ── Unbound ──────────────────────────────────────────────────────────────────
  # Pi-hole's upstream resolver. Listens on :5335 to avoid conflicting with
  # Pi-hole on :53. Forwards everything to 9.9.9.9 (Quad9).
  # Custom VPN-only hostnames live here (not in Pi-hole — FTL v6 ignores dnsmasq.d
  # address= directives and FTLCONF_dns_hosts format is non-obvious for arrays).
  services.unbound = {
    enable = true;
    settings.server = {
      interface = [ "127.0.0.1@5335" ];
      access-control = [
        "127.0.0.0/8 allow"
        "10.88.0.0/16 allow"   # podman default bridge
        "100.64.0.0/10 allow"  # VPN clients
      ];
      do-ip4               = true;
      do-ip6               = false;
      do-udp               = true;
      do-tcp               = true;
      hide-identity        = true;
      hide-version         = true;
      harden-glue          = true;
      harden-dnssec-stripped = true;
      edns-buffer-size     = 1232;
      prefetch             = true;
      private-address = [
        "192.168.0.0/16" "169.254.0.0/16"
        "172.16.0.0/12"  "10.0.0.0/8"
        "fd00::/8"        "fe80::/10"
      ];
      # VPN-only services → VPS VPN IP (no public A records in Cloudflare)
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
      name          = ".";
      forward-addr  = [ "9.9.9.9" "149.112.112.112" ];
    }];
    settings.remote-control.control-enable = false;
  };

  # ── Pi-hole (rootful podman, host networking) ─────────────────────────────────
  # Restore: copy ~/Backups/Server/pihole/ to /var/lib/pihole/
  # Pi-hole listens on 100.64.0.1:53 (VPN interface) — same as Ubuntu setup.
  # The podman gateway 10.88.0.1 is Pi-hole's upstream → Unbound.
  virtualisation.podman.enable = true;
  virtualisation.oci-containers.backend = "podman";
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
      TZ                           = "UTC";
      FTLCONF_dns_upstreams        = "127.0.0.1#5335";    # unbound on host loopback
      FTLCONF_dns_listeningMode    = "ALL";
      FTLCONF_dns_use_ipv6         = "false";
      FTLCONF_webserver_port       = "8083";
    };
    extraOptions = [
      "--network=host"
      "--cap-add=NET_ADMIN"
    ];
  };

  systemd.services.podman-pihole.after   = lib.mkAfter [ "unbound.service" ];
  systemd.services.podman-pihole.wants  = [ "unbound.service" ];


  systemd.tmpfiles.rules = [
    "d /var/lib/pihole/etc         0750 root root -"
    "d /var/lib/pihole/dnsmasq.d   0750 root root -"
    "d /var/lib/forgejo             0750 git  git  -"
    "d /var/lib/forgejo/custom      0750 git  git  -"
    # (Custom DNS file managed via activationScripts below — not tmpfiles)
  ];

  # ── Immich ───────────────────────────────────────────────────────────────────
  # Skipped for now. To enable:
  #   1. Create /var/lib/immich/docker-compose.yml + .env (from immich v2.7.4 release)
  #   2. Restore DB from ~/Backups/Immich/immich-db-backup-*.sql.gz
  #   3. Restore library from ~/Backups/ImmichLibrary/
  #   4. Fix ExecStart PATH so podman-compose can find podman
  #   5. Add nginx vhost back and uncomment service below

  # ── Syncthing ─────────────────────────────────────────────────────────────────
  # After first boot: re-share the send-only backup folders via the web UI.
  # UI at: https://syncthing.cloud-surf.com (VPN-only)
  services.syncthing = {
    enable       = true;
    user         = "syncthing";
    dataDir      = "/var/lib/syncthing";
    guiAddress   = "127.0.0.1:8384";
    openDefaultPorts = false;  # we open 22000 explicitly in firewall above
  };

  # ── Netdata ───────────────────────────────────────────────────────────────────
  services.netdata = {
    enable = true;
    config.global."bind to" = "127.0.0.1:19999";
  };

  # ── Tinyproxy ─────────────────────────────────────────────────────────────────
  # Access via SSH tunnel: ssh -L 8888:localhost:8888 vps
  services.tinyproxy = {
    enable = true;
    settings = {
      Port             = 8888;
      Listen           = "127.0.0.1";
      Timeout          = 600;
      Allow            = "127.0.0.1";
      DisableViaHeader = true;
    };
  };

  # ── CrowdSec ──────────────────────────────────────────────────────────────────
  # No NixOS service module in nixpkgs 24.11 — installed as package, configured manually.
  # After first boot:
  #   sudo cscli hub update && sudo cscli collections install crowdsecurity/nginx crowdsecurity/sshd
  #   sudo cscli bouncers add firewall-bouncer
  #   configure /etc/crowdsec/bouncers/crowdsec-firewall-bouncer.yaml then start the service

  # ── ACME (Let's Encrypt — DNS-01 via Cloudflare) ─────────────────────────────
  # Fixes the cert renewal issue that would have broken on 2026-07-11.
  # DNS-01 doesn't require HTTP access, works for all vhosts including VPN-only ones.
  # environmentFile must contain: CF_DNS_API_TOKEN=<token with Zone:DNS:Edit>
  # Zone ID: 4d9418859c4c6f4cd3d8cc0b673cc613
  #
  # NOTE: nginx's enableACME sets dnsProvider = lib.mkOverride 2000 null per-cert,
  # which overrides security.acme.defaults.dnsProvider (that only sets the option
  # default, not an explicit definition). We must set dnsProvider explicitly per-cert
  # at normal priority (100) to win over nginx's mkOverride 2000.
  security.acme = {
    acceptTerms = true;
    defaults = {
      email           = "e.shtoka@gmail.com";
      environmentFile = config.sops.secrets.cloudflare-acme-env.path;
    };
    certs = lib.genAttrs [
      "headscale.cloud-surf.com"
      "vault.cloud-surf.com"
      "git.cloud-surf.com"
      "syncthing.cloud-surf.com"
      "seer.cloud-surf.com"
      "netdata.cloud-surf.com"
      "matrix.cloud-surf.com"
    ] (_: { dnsProvider = "cloudflare"; webroot = null; });
  };

  # ── Nginx ─────────────────────────────────────────────────────────────────────
  services.nginx = {
    enable                    = true;
    recommendedProxySettings  = true;
    recommendedTlsSettings    = true;
    recommendedOptimisation   = true;
    recommendedGzipSettings   = true;
    serverTokens              = false;

    virtualHosts = let
      vpnOnly = ''
        allow 100.64.0.0/10;
        deny all;
      '';
    in {
      "headscale.cloud-surf.com" = {
        enableACME = true;
        forceSSL   = true;
        locations."/" = {
          proxyPass       = "http://127.0.0.1:8085";
          proxyWebsockets = true;
        };
      };

      "vault.cloud-surf.com" = {
        enableACME  = true;
        forceSSL    = true;
        extraConfig = ''
          ${vpnOnly}
          client_max_body_size 525M;
        '';
        locations."/" = {
          proxyPass       = "http://127.0.0.1:8080";
          proxyWebsockets = true;
        };
      };

      "git.cloud-surf.com" = {
        enableACME  = true;
        forceSSL    = true;
        extraConfig = ''
          ${vpnOnly}
          client_max_body_size 100M;
        '';
        locations."/" = {
          proxyPass = "http://127.0.0.1:3000";
        };
      };

      "matrix.cloud-surf.com" = {
        enableACME  = true;
        forceSSL    = true;
        extraConfig = vpnOnly;
        locations."/" = {
          proxyPass       = "http://127.0.0.1:6167";
          proxyWebsockets = true;
          extraConfig     = "proxy_read_timeout 3600;";
        };
      };

      # "immich.cloud-surf.com" — disabled until Immich is set up

      "syncthing.cloud-surf.com" = {
        enableACME  = true;
        forceSSL    = true;
        extraConfig = vpnOnly;
        locations."/" = {
          proxyPass = "http://127.0.0.1:8384";
        };
      };

      "seer.cloud-surf.com" = {
        enableACME  = true;
        forceSSL    = true;
        extraConfig = vpnOnly;
        locations."/" = {
          proxyPass = "http://127.0.0.1:8081";
        };
      };

      "netdata.cloud-surf.com" = {
        enableACME  = true;
        forceSSL    = true;
        extraConfig = vpnOnly;
        locations."/" = {
          proxyPass       = "http://127.0.0.1:19999";
          proxyWebsockets = true;
        };
      };
    };
  };

  # ── Kernel hardening ──────────────────────────────────────────────────────────
  boot.kernel.sysctl = {
    "dev.tty.ldisc_autoload"                = 0;
    "fs.protected_fifos"                    = 2;
    "fs.suid_dumpable"                      = 0;
    "kernel.core_uses_pid"                  = 1;
    "kernel.kptr_restrict"                  = 2;
    "kernel.sysrq"                          = 0;
    "net.core.bpf_jit_harden"              = 2;
    "net.ipv4.conf.all.log_martians"        = 1;
    "net.ipv4.conf.all.rp_filter"          = 1;
    "net.ipv4.conf.all.send_redirects"     = 0;
    "net.ipv4.conf.all.accept_source_route" = 0;
    "net.ipv4.conf.default.accept_source_route" = 0;
    "net.ipv4.conf.default.log_martians"   = 1;
  };

  boot.blacklistedKernelModules = [ "dccp" "sctp" "rds" "tipc" ];

  # ── Auditd ───────────────────────────────────────────────────────────────────
  security.auditd.enable = true;
  security.audit.enable  = true;
  security.audit.rules   = [
    "-w /etc/sudoers          -p wa -k identity"
    "-w /etc/ssh/sshd_config  -p wa -k sshd"
    "-w /etc/passwd           -p wa -k identity"
    "-w /etc/shadow           -p wa -k identity"
    "-w /etc/group            -p wa -k identity"
    "-a always,exit -F arch=b64 -S execve -F euid=0 -k root_commands"
  ];

  # ── Backup (systemd timers — replaces cron scripts) ───────────────────────────
  systemd.services.server-backup = {
    description = "Daily backup of stateful service data";
    serviceConfig = {
      Type    = "oneshot";
      User    = "root";
      ExecStart = pkgs.writeShellScript "server-backup" ''
        set -e
        OUT=/var/lib/server-backup
        mkdir -p $OUT/{headscale,forgejo,unbound}
        cp -a /var/lib/headscale/db.sqlite         $OUT/headscale/
        cp -a /var/lib/headscale/noise_private.key $OUT/headscale/
        rsync -a --delete /var/lib/forgejo/        $OUT/forgejo/
        rsync -a --delete /etc/unbound/            $OUT/unbound/
      '';
    };
  };
  systemd.timers.server-backup = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "03:00";
      Persistent = true;
    };
  };

  systemd.services.vaultwarden-backup = {
    description = "Daily backup of vaultwarden data";
    serviceConfig = {
      Type    = "oneshot";
      User    = "root";
      ExecStart = pkgs.writeShellScript "vaultwarden-backup" ''
        set -e
        OUT=/var/lib/vaultwarden-backup
        mkdir -p $OUT
        cp /var/lib/vaultwarden/db.sqlite3          $OUT/
        cp /var/lib/vaultwarden/rsa_key.pem         $OUT/ 2>/dev/null || true
        cp /var/lib/vaultwarden/rsa_key.pub.pem     $OUT/ 2>/dev/null || true
        rsync -a --delete /var/lib/vaultwarden/attachments/ $OUT/attachments/
      '';
    };
  };
  systemd.timers.vaultwarden-backup = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "03:00";
      Persistent = true;
    };
  };

  # ── Auto-upgrade ─────────────────────────────────────────────────────────────
  # Uncomment after pushing this flake to a git remote (e.g. forgejo or github).
  # system.autoUpgrade = {
  #   enable      = true;
  #   allowReboot = true;
  #   dates       = "04:00";
  #   flake       = "git+https://git.cloud-surf.com/eugene/nixos-vps.git#vps";
  # };

  # ── Packages ─────────────────────────────────────────────────────────────────
  environment.systemPackages = with pkgs; [
    git
    htop
    vim
    curl
    wget
    podman-compose
    crowdsec   # includes crowdsec-firewall-bouncer binary
  ];

  system.stateVersion = "24.11";
}
