{ ... }:
{
  boot.initrd.availableKernelModules = [
    "ahci"
    "virtio_pci"
    "virtio_blk"
    "virtio_scsi"
    "sd_mod"
    "sr_mod"
  ];
  boot.initrd.kernelModules = [ ];
  boot.kernelModules = [ ];
}
