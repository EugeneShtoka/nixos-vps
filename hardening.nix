{ config, pkgs, lib, ... }:
{
  # ── Firewall ──────────────────────────────────────────────────────────────────
  networking.firewall = {
    enable = true;
    allowedTCPPorts = [
      80 443      # nginx
      47293       # SSH
      2222        # Forgejo built-in SSH
      22000       # Syncthing sync protocol
    ];
    allowedUDPPorts = [
      41641       # WireGuard — headscale client connections
      22000       # Syncthing sync protocol
    ];
    trustedInterfaces = [ "tailscale0" ];
  };

  # ── Kernel hardening ──────────────────────────────────────────────────────────
  boot.kernel.sysctl = {
    "dev.tty.ldisc_autoload"                    = 0;
    "fs.protected_fifos"                        = 2;
    "fs.suid_dumpable"                          = 0;
    "kernel.core_uses_pid"                      = 1;
    "kernel.kptr_restrict"                      = 2;
    "kernel.sysrq"                              = 0;
    "net.core.bpf_jit_harden"                  = 2;
    "net.ipv4.conf.all.log_martians"            = 1;
    "net.ipv4.conf.all.rp_filter"              = 1;
    "net.ipv4.conf.all.send_redirects"         = 0;
    "net.ipv4.conf.all.accept_source_route"     = 0;
    "net.ipv4.conf.default.accept_source_route" = 0;
    "net.ipv4.conf.default.log_martians"        = 1;
  };

  boot.blacklistedKernelModules = [ "dccp" "sctp" "rds" "tipc" ];

  # ── Auditd ───────────────────────────────────────────────────────────────────
  security.auditd.enable = true;
  security.audit.enable  = true;
  security.audit.rules   = [
    "-w /etc/sudoers         -p wa -k identity"
    "-w /etc/ssh/sshd_config -p wa -k sshd"
    "-w /etc/passwd          -p wa -k identity"
    "-w /etc/shadow          -p wa -k identity"
    "-w /etc/group           -p wa -k identity"
    "-a always,exit -F arch=b64 -S execve -F euid=0 -k root_commands"
  ];
}
