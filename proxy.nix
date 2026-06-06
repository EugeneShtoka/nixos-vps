{ config, pkgs, lib, ... }:
{
  # ── ACME (Let's Encrypt — DNS-01 via Cloudflare) ─────────────────────────────
  # DNS-01 works for all vhosts including VPN-only ones (no HTTP access needed).
  # environmentFile contains: CF_DNS_API_TOKEN=<token with Zone:DNS:Edit>
  # NOTE: nginx's enableACME sets dnsProvider = lib.mkOverride 2000 null per-cert,
  # which overrides security.acme.defaults.dnsProvider. We must set dnsProvider
  # explicitly per-cert at normal priority (100) to win over nginx's mkOverride 2000.
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
      "ntfy.cloud-surf.com"
    ] (_: { dnsProvider = "cloudflare"; webroot = null; });
  };

  # ── Nginx ─────────────────────────────────────────────────────────────────────
  services.nginx = {
    enable                   = true;
    recommendedProxySettings = true;
    recommendedTlsSettings   = true;
    recommendedOptimisation  = true;
    recommendedGzipSettings  = true;
    serverTokens             = false;

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
          proxyPass       = "http://127.0.0.1:8900";
          proxyWebsockets = true;
          extraConfig     = "proxy_read_timeout 3600;";
        };
      };

      "ntfy.cloud-surf.com" = {
        enableACME  = true;
        forceSSL    = true;
        extraConfig = vpnOnly;
        locations."/" = {
          proxyPass       = "http://127.0.0.1:2586";
          proxyWebsockets = true;
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
}
