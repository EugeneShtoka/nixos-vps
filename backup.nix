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
        ${pkgs.rsync}/bin/rsync -a --delete /var/lib/forgejo/        $OUT/forgejo/
        ${pkgs.rsync}/bin/rsync -a --delete /etc/unbound/            $OUT/unbound/
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
        ${pkgs.rsync}/bin/rsync -a --delete /var/lib/vaultwarden/attachments/ $OUT/attachments/
      '';
    };
  };
  systemd.timers.vaultwarden-backup = {
    wantedBy    = [ "timers.target" ];
    timerConfig = { OnCalendar = "03:00"; Persistent = true; };
  };

  # ── Matrix homeserver backup (daily 03:20 UTC) ───────────────────────────────
  #
  # tuwunel keeps everything in RocksDB and 1.8.3 ships no online-checkpoint
  # command, so a consistent copy means stopping it first. That costs seconds, not
  # minutes: the store is ~1.7 GB of mostly immutable SST files, so each run moves
  # only the day's deltas.
  #
  # The trap is the load-bearing line. Whatever the copy does — full disk, killed
  # job, a bad rsync flag — the homeserver comes back up. A backup job that can
  # leave Matrix down is worse than having no backup job.
  #
  # Dated snapshots rather than one mirror, because a single `rsync --delete` mirror
  # faithfully reproduces a corrupted database over the last good copy, and a
  # database is exactly where that matters. --link-dest makes the unchanged SSTs
  # hardlinks, so a week of dailies costs barely more than one copy.
  #
  # 03:20 rather than 03:00: the other two jobs run at 03:00, and this one stops a
  # service while it works.
  systemd.services.tuwunel-backup = {
    description   = "Daily backup of the Matrix homeserver database";
    serviceConfig = {
      Type      = "oneshot";
      User      = "root";
      ExecStart = pkgs.writeShellScript "tuwunel-backup" ''
        set -e
        OUT=/var/lib/tuwunel-backup
        DAY=$(date -u +%Y-%m-%d)
        mkdir -p $OUT

        ${pkgs.systemd}/bin/systemctl stop tuwunel
        trap "${pkgs.systemd}/bin/systemctl start tuwunel" EXIT

        # First run has nothing to hardlink against; every later one does.
        if [ -d $OUT/latest ]; then
          ${pkgs.rsync}/bin/rsync -a --delete --link-dest=$OUT/latest /var/lib/tuwunel/ $OUT/$DAY/
        else
          ${pkgs.rsync}/bin/rsync -a --delete /var/lib/tuwunel/ $OUT/$DAY/
        fi
        ln -sfn $OUT/$DAY $OUT/latest

        # Keep a week. Older snapshots share their inodes with newer ones, so
        # removing them frees only what actually changed.
        find $OUT -maxdepth 1 -type d -name "20*-*-*" -mtime +7 -exec rm -rf {} +
      '';
    };
  };
  systemd.timers.tuwunel-backup = {
    wantedBy    = [ "timers.target" ];
    timerConfig = { OnCalendar = "03:20"; Persistent = true; };
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
      Environment     = [
        "HOME=/home/eugene"
        "GIT_SSH_COMMAND=${pkgs.openssh}/bin/ssh"
      ];
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
