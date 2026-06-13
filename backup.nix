{ config, pkgs, lib, ... }:
{
  # ── Server backup (daily 03:00 UTC) ──────────────────────────────────────────
  systemd.services.server-backup = {
    description   = "Daily backup of stateful service data";
    serviceConfig = {
      Type      = "oneshot";
      User      = "root";
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
    wantedBy    = [ "timers.target" ];
    timerConfig = { OnCalendar = "03:00"; Persistent = true; };
  };

  # ── Vaultwarden backup (daily 03:00 UTC) ──────────────────────────────────────
  systemd.services.vaultwarden-backup = {
    description   = "Daily backup of vaultwarden data";
    serviceConfig = {
      Type      = "oneshot";
      User      = "root";
      ExecStart = pkgs.writeShellScript "vaultwarden-backup" ''
        set -e
        OUT=/var/lib/vaultwarden-backup
        mkdir -p $OUT
        cp /var/lib/vaultwarden/db.sqlite3      $OUT/
        cp /var/lib/vaultwarden/rsa_key.pem     $OUT/ 2>/dev/null || true
        cp /var/lib/vaultwarden/rsa_key.pub.pem $OUT/ 2>/dev/null || true
        rsync -a --delete /var/lib/vaultwarden/attachments/ $OUT/attachments/
      '';
    };
  };
  systemd.timers.vaultwarden-backup = {
    wantedBy    = [ "timers.target" ];
    timerConfig = { OnCalendar = "03:00"; Persistent = true; };
  };

  # ── Auto-push nixos config to GitHub after each rebuild ──────────────────────
  systemd.services.nixos-config-push = {
    description = "Push nixos-vps config to GitHub after rebuild";
    after       = [ "network-online.target" ];
    wants       = [ "network-online.target" ];
    wantedBy    = [ "multi-user.target" ];
    serviceConfig = {
      Type            = "oneshot";
      User            = "eugene";
      RemainAfterExit = true;
      ExecStart       = pkgs.writeShellScript "nixos-config-push" ''
        cd /etc/nixos
        ${pkgs.git}/bin/git add -A
        if ! ${pkgs.git}/bin/git diff-index --quiet HEAD; then
          ${pkgs.git}/bin/git commit -m "auto: post-rebuild $(${pkgs.coreutils}/bin/date -uI)"
          ${pkgs.git}/bin/git push
        fi
      '';
    };
  };

  # ── Auto-upgrade (uncomment after pushing flake to git remote) ───────────────
  # system.autoUpgrade = {
  #   enable      = true;
  #   allowReboot = true;
  #   dates       = "04:00";
  #   flake       = "git+https://git.cloud-surf.com/eugene/nixos-vps.git#vps";
  # };
}
