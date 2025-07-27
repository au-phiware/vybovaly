# Vybovaly Automated Installation Guide

This guide explains how to set up automated NixOS installation using iPXE with
flake support for cloud GPU configurations.

## Overview

The system consists of several components:

1. **iPXE script** - Boots NixOS installer with parameters
2. **Custom init script** - Handles early boot automation
3. **Installer script** - Performs the actual installation
4. **Flake configuration** - Defines your system configuration

## Setup Steps

### 1. Prepare the iPXE Environment

First, you need to host the installer script somewhere accessible or use GitHub
raw URLs.

### 2. Configure iPXE Parameters

The iPXE script accepts these parameters:

- `flake_url` - Git repository URL containing your flake (required)
- `username` - User account to create (optional, can be defined in flake)
- `ssh_key` - SSH public key for authentication (optional, can be defined in
  flake)
- `hostname` - System hostname (optional, let nixos-install decided based on
  flake)

### 3. Example Usage

#### Basic Usage

```ipxe
# Set parameters
set username myuser
set ssh_key ssh-rsa AAAAB3NzaC1yc2E...
set flake_url https://github.com/myuser/nixos-config
set hostname gpu-server-01

# Chain to the main script
chain nixos-install.ipxe
```

#### DHCP Integration

You can also pass parameters via DHCP options:

```sh
option-175 "username=myuser,ssh_key=ssh-rsa AAAAB3NzaC1yc2E...,flake_url=https://github.com/myuser/nixos-config"
```

### 4. Create Your Flake Configuration

Create a flake repository with your system configuration:

```nix
# flake.nix
{
  description = "NixOS GPU Server Configuration";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.05";
  };

  outputs = { self, nixpkgs }: {
    nixosConfigurations = {
      gpu-server-01 = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [
          ./configuration.nix
          ./hardware-configuration.nix
        ];
      };
    };
  };
}
```

```nix
# configuration.nix
{ config, pkgs, ... }:

{
  # Boot configuration
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  # Networking
  networking.hostName = "gpu-server-01";
  networking.networkmanager.enable = true;

  # NVIDIA GPU support
  services.xserver.videoDrivers = [ "nvidia" ];
  hardware.nvidia = {
    modesetting.enable = true;
    powerManagement.enable = false;
    powerManagement.finegrained = false;
    open = false;
    nvidiaSettings = true;
    package = config.boot.kernelPackages.nvidiaPackages.stable;
  };

  # CUDA support
  nixpkgs.config.allowUnfree = true;
  environment.systemPackages = with pkgs; [
    cudatoolkit
    python3
    git
    vim
  ];

  # SSH configuration
  services.openssh = {
    enable = true;
    settings.PasswordAuthentication = false;
    settings.PermitRootLogin = "no";
  };

  # User configuration
  users.users.myuser = {
    isNormalUser = true;
    extraGroups = [ "wheel" "networkmanager" ];
    openssh.authorizedKeys.keys = [
      "ssh-rsa AAAAB3NzaC1yc2E..."
    ];
  };

  # Docker for containerized workloads
  virtualisation.docker.enable = true;
  users.users.myuser.extraGroups = [ "docker" ];

  # System version
  system.stateVersion = "25.05";
}
```

## Disk Layout Options

### Single Disk Layout

```text
/dev/sda1 - 512MB EFI boot partition
/dev/sda2 - Remaining space for root filesystem
```

### RAID Layout

```text
/dev/sda1, /dev/sdb1 - 512MB EFI boot partitions
/dev/md0 - RAID1 mirror of /dev/sda2 and /dev/sdb2
```

## Testing

### Virtual Machine Testing

```bash
# Create a test VM
qemu-system-x86_64 -m 4G -enable-kvm -boot n -netdev user,id=net0 \
  -device rtl8139,netdev=net0 -drive file=test.qcow2,if=virtio
```

### Physical Hardware Testing

1. Configure your DHCP server to provide iPXE options
2. Boot your target machine via PXE
3. Monitor the installation process

## Troubleshooting

### Common Issues

1. **Network connectivity**: Ensure the installer can reach the internet
2. **SSH key format**: Use the full public key including the key type
3. **Flake URL**: Must be accessible without authentication
4. **Disk detection**: Verify disk device names match your hardware

### Debug Mode

Add `vyb.debug=1` to kernel parameters for verbose output.

### Manual Recovery

If automation fails, you can still access the NixOS installer environment and
install manually.

## Security Considerations

1. **SSH Keys**: Use dedicated keys for automated deployment
2. **Network Security**: Consider using VPN or private networks
3. **Flake Repository**: Ensure your configuration repository is secure
4. **Secrets Management**: Use NixOS secrets management for sensitive data

## Advanced Features

### Custom Disk Layouts

Modify the partitioning functions in the installer script for custom disk layouts.

### Multi-Stage Installation

The flake service runs after first boot, allowing for complex configurations
that require a running system.

### Cloud Integration

Integrate with cloud metadata services for dynamic configuration.

## Example Complete Workflow

1. **Prepare Infrastructure**:

   ```bash
   # Create flake repository
   git init nixos-config
   cd nixos-config
   # Add flake.nix and configuration.nix
   git add .
   git commit -m "Initial configuration"
   git push origin main
   ```

2. **Configure iPXE**:

   ```ipxe
   #!ipxe
   set username admin
   set ssh_key ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAAB...
   set flake_url https://github.com/youruser/nixos-config
   set hostname gpu-node-01
   chain nixos-install.ipxe
   ```

3. **Boot and Install**:
   - Boot target machine via PXE
   - Installation runs automatically
   - System reboots into configured environment

This setup provides a fully automated, parameterized installation system that
can deploy consistent NixOS configurations across multiple machines with GPU
support.
