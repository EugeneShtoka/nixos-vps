{ config, pkgs, lib, ... }:
{
  services.searx = {
    enable          = true;
    package         = pkgs.searxng;
    environmentFile = config.sops.secrets.searxng-secret-key.path;
    settings = {
      server = {
        port         = 8081;
        bind_address = "127.0.0.1";
        base_url     = "https://seer.cloud-surf.com/";
        secret_key   = "@SEARXNG_SECRET_KEY@";
      };
      ui.default_theme    = "simple";
      search.safe_search  = 0;
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
        { name = "qwant"; engine = "qwant"; shortcut = "qw"; }
      ];
    };
  };
}
