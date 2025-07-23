# Vybovaly - Automated Installation System

A comprehensive system for automated NixOS installation on cloud GPU servers
using iPXE, with support for flake-based configurations and CI/CD integration.

## 🚀 Quick Start

1. **Fork this repository** and customize your configurations
2. **Set up GitHub Actions** to build your installer images
3. **Deploy to your PXE server** and boot target machines
4. **Enjoy automated installations** with your custom NixOS configurations

## 📋 Table of Contents

- [Features](#features)
- [Architecture](#architecture)
- [Getting Started](#getting-started)
- [Configuration](#configuration)
- [GitHub Actions CI/CD](#github-actions-cicd)
- [Local Development](#local-development)
- [Usage Examples](#usage-examples)
- [Troubleshooting](./TROUBLESHOOTING.md)
- [Contributing](./CONTRIBUTING.md)

## ✨ Features

### 🎯 Core Features

- **Fully Automated Installation**: Zero-touch NixOS deployment
- **Parameterized Configuration**: Username, SSH keys, hostname, disk layout via
  iPXE
- **Flake Integration**: Automatic system building from your NixOS flake
- **Multiple Disk Layouts**: Single disk or RAID configurations
- **GPU Support**: NVIDIA drivers, CUDA, ML stack pre-configured
- **CI/CD Ready**: GitHub Actions for building and releasing images

### 🛠 Technical Features

- **Custom Kernel/Initrd**: Embedded installer with automation
- **Error Handling**: Comprehensive validation and recovery
- **Debug Mode**: Verbose logging and troubleshooting tools
- **Version Pinning**: Reproducible builds with checksums
- **Multiple Variants**: Minimal, full, and GPU-optimized images

### 🔧 Operations Features

- **Monitoring Ready**: GPU health checks, system metrics
- **Security Hardened**: SSH key-only auth, firewall configured
- **ML/AI Stack**: JupyterLab, MLflow, TensorBoard, VS Code Server
- **Container Support**: Docker with GPU passthrough

## 🏗 Architecture

```text
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   iPXE Script   │    │ Custom Kernel/  │    │ Automated       │
│                 │    │ Initrd          │    │ Installer       │
│ • Parameters    │───▶│                 │───▶│                 │
│ • Validation    │    │ • Embedded libs │    │ • Disk setup    │
│ • Error handling│    │ • Network tools │    │ • NixOS install │
└─────────────────┘    └─────────────────┘    └─────────────────┘
                                                        │
                                                        ▼
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   Your Flake    │    │ Post-Install    │    │ Basic NixOS     │
│                 │    │ Service         │    │ System          │
│ • GPU modules   │◀───│                 │◀───│                 │
│ • ML stack      │    │ • Git clone     │    │ • SSH access    │
│ • Custom config │    │ • Flake rebuild │    │ • Network       │
└─────────────────┘    └─────────────────┘    └─────────────────┘
```

## 🚦 Getting Started

### Prerequisites

- **PXE Server**: dnsmasq + nginx/apache for TFTP/HTTP
- **Target Machines**: UEFI/BIOS with network boot support
- **Git Repository**: For your NixOS flake configuration
- **GitHub Account**: For CI/CD (optional but recommended)

### Step 1: Repository Setup

```bash
# Clone and customize
git clone https://github.com/au-phiware/vybovaly-installer
cd vybovaly-installer

# Create your flake configuration
mkdir -p hosts/gpu-server-01
cp examples/configuration.nix hosts/gpu-server-01/
```

### Step 2: Configure GitHub Actions

1. **Enable GitHub Actions** in your repository
2. **Set up Cachix** (optional but recommended for faster builds):

   ```bash
   # Set repository secrets:
   CACHIX_AUTH_TOKEN=your-token
   CACHIX_CACHE_NAME=your-cache-name
   ```

3. **Commit and push** to trigger your first build

### Step 3: Deploy PXE Server

```bash
# Use the deployment script
./scripts/deploy.sh setup
./scripts/deploy.sh deploy

# Or manually configure your PXE server
# See deployment documentation for details
```

### Step 4: Test Installation

```bash
# Test in VM first
./scripts/build.sh build gpu-optimized
./scripts/build.sh serve 8080

# Boot VM with network boot pointing to your server
qemu-system-x86_64 -m 4G -boot n \
  -netdev user,tftp=artifacts,bootfile=boot-menu.ipxe ...
```

## ⚙️ Configuration

### iPXE Parameters

Configure these parameters via DHCP options, iPXE script, or interactive prompt:

| Parameter       | Required | Description             | Example             |
|-----------------|----------|-------------------------|---------------------|
| `username`      | Yes      | User account to create  | `admin`             |
| `ssh_key`       | Yes      | SSH public key          | `ssh-rsa AAAAB3...` |
| `hostname`      | No       | System hostname         | `gpu-server-01`     |
| `flake_url`     | Yes      | Git repository URL      | `https://github.com/org/nixos-config` |
| `disk_layout`   | No       | Partitioning scheme     | `single`, `raid`    |
| `debug`         | No       | Enable debug mode       | `0`, `1`            |

### Example iPXE Script

```ipxe
#!ipxe

# Set your parameters
set username admin
set ssh_key "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQC..."
set flake_url https://github.com/your-org/nixos-gpu-config
set hostname gpu-server-01
set disk_layout single

# Chain to the installer
chain https://github.com/au-phiware/vybovaly-installer/releases/latest/download/nixos-install.ipxe
```

### NixOS Flake Structure

```text
your-nixos-config/
├── flake.nix                # Main flake definition
├── flake.lock               # Pinned dependencies
├── hosts/
│   ├── gpu-server-01/
│   │   ├── configuration.nix
│   │   └── hardware-configuration.nix
│   └── gpu-cluster-01/
│       ├── configuration.nix
│       └── hardware-configuration.nix
└── modules/
    ├── gpu.nix              # GPU configuration module
    ├── ml-stack.nix         # ML/AI software stack
    └── monitoring.nix       # System monitoring
```

## 🔄 GitHub Actions CI/CD

### Workflow Triggers

The GitHub Action builds new images on:

- **Push to main/develop**: Latest development builds
- **Pull requests**: Validation builds
- **Releases**: Stable versioned releases
- **Manual dispatch**: On-demand builds with custom parameters

### Build Variants

| Variant         | Size   | Contents              | Use Case           |
|-----------------|--------|-----------------------|--------------------|
| `minimal`       | ~200MB | Basic tools only      | Simple deployments |
| `full`          | ~500MB | Development tools     | General purpose    |
| `gpu-optimized` | ~800MB | GPU drivers, ML tools | AI/ML workloads    |

### Outputs

Each build produces:

- `bzImage` - Custom Linux kernel
- `initrd` - Initial ramdisk with installer
- `vybovaly-installer.sh` - Installation script
- `vybovaly.ipxe` - Main iPXE script
- `boot-menu.ipxe` - Interactive boot menu
- `version.json` - Build metadata and checksums
- `checksums.txt` - SHA256 checksums

## 💻 Local Development

### Building Locally

Requires Nix with flakes enabled.

```bash
# Enter development environment
nix develop
# or with direnv
direnv allow

# Build images locally
./scripts/build.sh build minimal
./scripts/build.sh build gpu-optimized

# Start test server
./scripts/build.sh serve 8080
```

### Testing with QEMU

```bash
# Create test VM
qemu-system-x86_64 \
  -m 4G \
  -smp 2 \
  -enable-kvm \
  -boot n \
  -netdev user,id=net0,tftp=build/artifacts,bootfile=boot-menu.ipxe \
  -device rtl8139,netdev=net0 \
  -drive file=test.qcow2,if=virtio \
  -vnc :1
```

### Development Workflow

1. **Modify configurations** in `modules/` or `installer/`
2. **Build locally** with `./scripts/build.sh build`
3. **Test in VM** to validate changes
4. **Commit and push** to trigger CI build
5. **Deploy release** to production PXE server

### Using the Flake Development Environment

```bash
# Available commands in dev shell
build-all-variants          # Build all installer variants
test-vm [variant]           # Start test VM
test-pxe-server [port]      # Start HTTP server for PXE testing
validate-build              # Validate generated artifacts
clean-build                 # Clean all build artifacts

# Direct flake commands
nix build .#installer-images.minimal.kernel
nix run .#test-vm -- gpu-optimized 8G
nix run .#test-pxe-server -- 9000
```

## 📖 Usage Examples

### Example 1: Basic GPU Server

```ipxe
#!ipxe
set username researcher
set ssh_key "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGq..."
set flake_url https://github.com/ml-lab/gpu-configs
set hostname ai-workstation-01
chain https://github.com/au-phiware/vybovaly-installer/releases/latest/download/nixos-install.ipxe
```

### Example 2: Multi-GPU Cluster Node

```ipxe
#!ipxe
set username cluster-admin
set ssh_key "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAAB..."
set flake_url https://github.com/company/hpc-cluster-config
set hostname gpu-node-${mac:hexhyp}
set disk_layout raid
chain https://github.com/au-phiware/vybovaly-installer/releases/latest/download/nixos-install.ipxe
```

### Example 3: DHCP Integration

Configure your DHCP server to automatically provide parameters:

```bash
# dnsmasq configuration
dhcp-option=option:bootfile-name,"boot-menu.ipxe"
dhcp-option=175,"username=auto-user,flake_url=https://github.com/org/configs"

# ISC DHCP configuration
option space ipxe;
option ipxe-encap-opts code 175 = encapsulate ipxe;
option ipxe.username code 1 = string;
option ipxe.ssh_key code 2 = string;
option ipxe.flake_url code 3 = string;

class "ipxe" {
  match if exists user-class and option user-class = "iPXE";
  option ipxe.username "admin";
  option ipxe.flake_url "https://github.com/company/nixos-configs";
}
```

### Example 4: Cloud Provider Integration

For cloud providers that support custom iPXE:

```ipxe
#!ipxe
# Auto-detect cloud metadata
set base_url http://169.254.169.254/latest/meta-data
set username ${username:cloud-user}
set hostname ${hostname:${base_url}/hostname}
set ssh_key ${ssh_key:${base_url}/public-keys/0/openssh-key}
set flake_url https://github.com/company/cloud-nixos-config

chain https://github.com/au-phiware/vybovaly-installer/releases/latest/download/nixos-install.ipxe
```

### Example 5: Development Environment

Quick setup for development machines:

```ipxe
#!ipxe
set username developer
set ssh_key "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAAB..."
set flake_url https://github.com/team/dev-environment
set hostname dev-${uuid}
set disk_layout single
set debug 1

chain https://github.com/team/nixos-dev-setup/releases/latest/download/nixos-install.ipxe
```

### Example 6: Production Deployment with Validation

```ipxe
#!ipxe
# Production deployment with pre-flight checks
set username ops
set ssh_key "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAAB..."
set flake_url https://github.com/company/production-nixos
set hostname prod-gpu-${serial}
set disk_layout raid

# Additional production parameters
set environment production
set monitoring_endpoint https://monitoring.company.com
set backup_target s3://company-backups/nixos

chain https://github.com/au-phiware/vybovaly-installer/releases/v2.1.0/download/nixos-install.ipxe
```
