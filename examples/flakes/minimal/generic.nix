# Minimal NixOS configuration for vybovaly installer
# This serves as an example of a generic flake-based installation
{ config, pkgs, lib, modulesPath, ... }:

{
  imports =
    [ (modulesPath + "/profiles/minimal.nix")
      (modulesPath + "/hardware/all-hardware.nix")
      (modulesPath + "/hardware/all-firmware.nix")
    ];

  # Boot configuration - use GRUB with EFI for better compatibility
  boot.loader.grub = {
    enable = lib.mkDefault true;
    efiSupport = lib.mkDefault true;
    device = lib.mkDefault "nodev";  # For EFI, don't install to MBR
    useOSProber = lib.mkDefault false;
  };
  boot.loader.efi.canTouchEfiVariables = lib.mkDefault true;
  
  # Enable flakes
  nix.settings.experimental-features = [ "nix-command" "flakes" ];

  hardware.enableAllHardware = true;
  hardware.enableRedistributableFirmware = lib.mkDefault true;


  # Network configuration
  networking = {
    hostName = lib.mkDefault "nixos";
    networkmanager.enable = lib.mkDefault true;
    
    # Basic firewall
    firewall = {
      enable = lib.mkDefault true;
      allowedTCPPorts = [ 22 ];
    };
  };

  # SSH configuration
  services.openssh = {
    enable = true;
    settings = {
      PasswordAuthentication = false;
      PermitRootLogin = "no";
    };
  };

  # Allow sudo without password for wheel group (useful for automation)
  security.sudo.wheelNeedsPassword = lib.mkDefault false;

  # Default user (can be overridden)
  users.users.user = {
    isNormalUser = true;
    extraGroups = [ "wheel" "networkmanager" ];
    # SSH keys would typically be set via the flake or installer automation
  };

  # Essential packages
  environment.systemPackages = with pkgs; [
    testdisk # useful for repairing boot problems
    efibootmgr
    efivar
    parted
    gptfdisk
    ddrescue
    ccrypt
    cryptsetup # needed for dm-crypt volumes

    # Some text editors.
    vim

    # Some networking tools.
    fuse
    fuse3
    sshfs-fuse
    socat
    screen
    tcpdump

    # Hardware-related tools.
    sdparm
    hdparm
    smartmontools # for diagnosing hard disks
    pciutils
    usbutils
    nvme-cli

    # Some compression/archiver tools.
    unzip
    zip

    # Some dev tools.
    git
    curl
    wget
    htop
    tree
  ];

  # Filesystem configuration (should match disko labels)
  fileSystems."/" =
    { device = "/dev/disk/by-label/nixos";
      fsType = "ext4";
    };

  fileSystems."/boot" =
    { device = "/dev/disk/by-label/boot";
      fsType = "vfat";
      options = [ "fmask=0022" "dmask=0022" ];
    };

  # System version
  system.stateVersion = "25.05";
}
