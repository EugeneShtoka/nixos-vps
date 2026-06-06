{ config, pkgs, lib, ... }:
{
  # ── Boot ─────────────────────────────────────────────────────────────────────
  # BIOS boot — VM uses SeaBIOS. device set automatically by disko via EF02 partition.
  boot.loader.grub.enable = true;
  boot.initrd.availableKernelModules = [ "virtio_pci" "virtio_blk" "virtio_scsi" "ata_piix" "uhci_hcd" "sd_mod" ];

  # ── Network ──────────────────────────────────────────────────────────────────
  networking = {
    hostName   = "vps";
    useDHCP    = true;       # Hetzner Cloud pushes IP via DHCP
    nameservers = [ "127.0.0.1" ];   # Pi-hole on localhost → unbound → 9.9.9.9
  };

  # ── Time / locale ─────────────────────────────────────────────────────────────
  time.timeZone      = "UTC";
  i18n.defaultLocale = "en_US.UTF-8";

  # ── Nix ──────────────────────────────────────────────────────────────────────
  nix.settings.experimental-features = [ "nix-command" "flakes" ];
  nix.gc = {
    automatic = true;
    dates     = "weekly";
    options   = "--delete-older-than 30d";
  };

  # ── Users ─────────────────────────────────────────────────────────────────────
  users.users.eugene = {
    isNormalUser = true;
    extraGroups  = [ "wheel" ];
    openssh.authorizedKeys.keyFiles = [ ./keys/eugene.pub ];
  };
  security.sudo.wheelNeedsPassword = false;

  # ── SSH ──────────────────────────────────────────────────────────────────────
  services.openssh = {
    enable = true;
    ports  = [ 47293 ];
    settings = {
      PermitRootLogin        = "no";
      PasswordAuthentication = false;
      AllowTcpForwarding     = "yes";   # needed for tinyproxy SSH tunnel
      AllowAgentForwarding   = "no";
      MaxAuthTries           = 3;
      MaxSessions            = 2;
      ClientAliveCountMax    = 2;
      TCPKeepAlive           = "no";
      LogLevel               = "VERBOSE";
    };
  };

  # ── Packages ─────────────────────────────────────────────────────────────────
  environment.systemPackages = with pkgs; [
    git htop vim curl wget podman-compose crowdsec
  ];

  system.stateVersion = "24.11";
}
