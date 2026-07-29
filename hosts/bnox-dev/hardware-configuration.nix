{ ... }:
{
  fileSystems."/" = {
    device = "/dev/disk/by-label/root";
    fsType = "ext4";
  };

  boot.loader.systemd-boot.enable = true;
}
