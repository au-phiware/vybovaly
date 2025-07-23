# Minimal NixOS Flake Example

This is a minimal example flake for use with the vybovaly installer. It demonstrates how to create a generic NixOS configuration that works with automated installation.

## Features

- **Generic hardware support** - Uses sensible defaults that work with most systems
- **No hardware-configuration.nix dependency** - Self-contained configuration
- **Automation-friendly** - Passwordless sudo, SSH keys, etc.
- **Minimal package set** - Only essential tools included

## Usage

### With vybovaly installer

The installer can use this flake directly from various sources:

```bash
# From a Git repository
nixos.flake_url=https://github.com/user/repo#minimal

# From a local directory  
nixos.flake_url=/path/to/flake#minimal

# From a tarball
nixos.flake_url=https://example.com/flake.tar.gz#minimal
```

### Manual installation

You can also use this flake for manual installations:

```bash
# Clone or download the flake
git clone <repo> /tmp/flake

# Install
nixos-install --root /mnt --flake /tmp/flake#minimal
```

## Configuration

The configuration uses `lib.mkDefault` for most settings, so they can be easily overridden:

- **Hostname**: Defaults to "nixos", override with `networking.hostName`
- **User**: Creates a "user" account, add your own users as needed
- **Boot**: Uses systemd-boot with EFI, can be changed to GRUB
- **Filesystems**: Expects `/dev/disk/by-label/nixos` and `/dev/disk/by-label/boot`

## Customization

To customize this flake for your needs:

1. Copy this directory to your own repository
2. Modify `generic.nix` (or another nix file) with your settings
3. Add additional modules as needed
4. Update the flake inputs if you need specific nixpkgs versions
