{ config, pkgs, lib, ... }:
{
  # BIOS boot — VM uses SeaBIOS. device set automatically by disko via EF02 partition.
  boot.loader.grub.enable = true;
  boot.initrd.availableKernelModules = [ "virtio_pci" "virtio_blk" "virtio_scsi" "ata_piix" "uhci_hcd" "sd_mod" ];
}
