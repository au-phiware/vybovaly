# 🐛 Vybovaly Installation Troubleshooting Guide

This guide covers common issues and solutions when using the automated NixOS
installation system.

## Pre-Installation Issues

### 1. iPXE Script Configuration Issues

#### Symptom: SSH authentication fails with "Permission denied (publickey)"

**⚠️ IMPORTANT: Do NOT quote SSH keys in iPXE scripts**

A common issue occurs when SSH keys are quoted in iPXE scripts, causing double-quoting in the kernel command line.

**❌ WRONG:**
```ipxe
set ssh_key 'ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQC...'
```

**✅ CORRECT:**
```ipxe
set ssh_key ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQC...
```

**Why this happens:**
- The iPXE script automatically adds quotes when constructing the kernel command line
- Manual quotes result in: `vyb.ssh_key="'ssh-rsa AAAAB3...'"` (double-quoted)
- The installer then receives the SSH key with embedded quotes, causing authentication failure

**Other parameters that should NOT be quoted:**
- `flake_url` - URLs should not be quoted
- `hostname` - Hostnames should not be quoted  
- `username` - Usernames should not be quoted
- `cachix_cache` - Cache names should not be quoted

**Parameters that CAN be quoted (if they contain spaces):**
- `access_tokens` - Only if the token itself contains spaces (rare)

### 2. PXE Boot Failures

#### Symptom: Machine doesn't boot from network

**Possible Causes:**

- BIOS/UEFI not configured for network boot
- Network cable issues
- DHCP server not responding

**Solutions:**

```bash
# Check DHCP server status
sudo systemctl status dnsmasq
sudo journalctl -u dnsmasq -f

# Verify TFTP service
sudo systemctl status tftpd-hpa
sudo netstat -ulnp | grep :69

# Test network connectivity
ping <target-machine-ip>
tcpdump -i eth0 port 67 or port 68  # Monitor DHCP traffic
```

#### Symptom: iPXE script not loading

**Check:**

- TFTP server is running and accessible
- iPXE script syntax is correct
- File permissions are correct

```bash
# Test TFTP manually
tftp <tftp-server-ip>
> get boot.ipxe
> quit

# Check file permissions
ls -la /var/lib/tftpboot/
```

### 2. Network Configuration Issues

#### Symptom: No IP address assigned

```bash
# Check DHCP range and leases
cat /var/lib/dnsmasq/dnsmasq.leases
sudo dnsmasq --test  # Test configuration

# Monitor DHCP requests
sudo tcpdump -i eth0 -n port 67 or port 68
```

#### Symptom: DNS resolution failing

```bash
# Test DNS from target machine (when in installer)
nslookup google.com
dig @8.8.8.8 google.com

# Check DNS configuration in dnsmasq
grep dns-server /etc/dnsmasq.d/pxe.conf
```

## Installation Process Issues

### 4. Disk Partitioning Issues

#### Symptom: Disk not found

```bash
# List available disks
lsblk
fdisk -l
ls /dev/sd*

# Check if disks are recognized
dmesg | grep -i disk
```

#### Symptom: Partitioning fails

```bash
# Manual partitioning for debugging
parted /dev/sda print
parted /dev/sda mklabel gpt
parted /dev/sda mkpart ESP fat32 1MiB 512MiB

# Check disk errors
smartctl -a /dev/sda
```

### 5. Mount Issues

#### Symptom: Cannot mount filesystems

```bash
# Check filesystem creation
mkfs.fat -F 32 -n boot /dev/sda1
mkfs.ext4 -L nixos /dev/sda2

# Verify mounts
mount | grep /mnt
findmnt /mnt

# Manual mount for debugging
umount -R /mnt
mount /dev/sda2 /mnt
mkdir -p /mnt/boot
mount /dev/sda1 /mnt/boot
```

## Configuration Issues

### 6. Hardware Configuration Problems

#### Symptom: Hardware not detected properly

```bash
# Regenerate hardware config
nixos-generate-config --root /mnt --show-hardware-config

# Check for missing drivers
lspci | grep -i vga
lsmod | grep nvidia
```

#### Symptom: GPU not working after installation

```bash
# Check NVIDIA driver installation
nvidia-smi
lsmod | grep nvidia

# Verify hardware configuration
cat /etc/nixos/hardware-configuration.nix | grep -A5 -B5 nvidia
```

### 7. Network Issues Post-Installation

#### Symptom: No internet after reboot

```bash
# Check network manager
systemctl status NetworkManager
nmcli device status

# Check interface configuration
ip addr show
ip route show

# Restart networking
sudo systemctl restart NetworkManager
```

### 8. SSH Access Issues

#### Symptom: Cannot SSH to installed system

```bash
# Check SSH service
systemctl status sshd
journalctl -u sshd

# Verify SSH keys
cat ~/.ssh/authorized_keys
ssh-keygen -lf ~/.ssh/authorized_keys

# Check firewall
sudo ufw status
sudo iptables -L
```

## Flake-Related Issues

### 9. Flake Repository Access

#### Symptom: Cannot clone flake repository

```bash
# Test git access
git clone https://github.com/user/repo.git /tmp/test-clone

# Check network and authentication
ssh -T git@github.com
git config --global --list
```

#### Symptom: Flake build fails

```bash
# Debug flake evaluation
nix flake show /path/to/flake
nix flake check /path/to/flake

# Test flake build
nix build /path/to/flake#nixosConfigurations.hostname.config.system.build.toplevel
```

### 10. NixOS Rebuild Issues

#### Symptom: nixos-rebuild switch fails

```bash
# Check flake syntax
cd /etc/nixos/flake
nix flake check

# Build without switching
nixos-rebuild build --flake .#hostname

# Check for conflicts
nixos-rebuild switch --flake .#hostname --show-trace
```

## Service Issues

### 11. ML Stack Services Not Starting

#### Symptom: JupyterLab not accessible

```bash
# Check service status
systemctl status jupyterlab
journalctl -u jupyterlab -f

# Check port binding
netstat -tlnp | grep 8888
ss -tlnp | grep 8888

# Test manual start
sudo -u jupyter /nix/store/.../bin/jupyter lab --ip=0.0.0.0 --port=8888
```

#### Symptom: GPU not available in containers

```bash
# Check NVIDIA container runtime
docker run --rm --gpus all nvidia/cuda:11.0-base nvidia-smi

# Verify container toolkit
nvidia-container-cli info
```

## Debugging Tools and Commands

### 12. System Diagnostics

```bash
# System information
uname -a
lscpu
lsmem
lspci
lsusb

# Memory and disk usage
free -h
df -h
iotop
htop

# Network diagnostics
ip addr
ip route
ss -tuln
netstat -rn

# Service debugging
systemctl --failed
journalctl --since "1 hour ago" --no-pager
dmesg | tail -50
```

### 13. NixOS-Specific Debugging

```bash
# Check NixOS configuration
nixos-version
nix-env --version

# List installed packages
nix-env -qa --installed

# Check store integrity
nix-store --verify --check-contents

# Rebuild with debugging
nixos-rebuild switch --show-trace --verbose
```

### 14. GPU-Specific Debugging

```bash
# NVIDIA diagnostics
nvidia-smi
nvidia-debugdump -l
nvidia-settings -q all

# CUDA verification
nvcc --version
cat /proc/driver/nvidia/version

# GPU memory and processes
nvidia-smi pmon
fuser -v /dev/nvidia*
```

## Recovery Procedures

### 15. Boot Recovery

#### If system won't boot after installation

```bash
# Boot from NixOS installer
# Mount the installed system
mount /dev/sda2 /mnt
mount /dev/sda1 /mnt/boot

# Check configuration
cat /mnt/etc/nixos/configuration.nix

# Fix configuration and rebuild
nixos-install --root /mnt

# Or enter chroot for manual fixes
nixos-enter --root /mnt
```

#### If flake configuration is broken

```bash
# Revert to working configuration
cd /etc/nixos
git log --oneline
git checkout <working-commit>
nixos-rebuild switch --flake .#hostname

# Or use rollback
nixos-rebuild --rollback
```

### 16. Network Recovery

#### If network is completely broken

```bash
# Manual network configuration
ip link set eth0 up
ip addr add 192.168.1.100/24 dev eth0
ip route add default via 192.168.1.1

# Or use NetworkManager
nmcli device wifi connect "SSID" password "password"
nmcli connection up "connection-name"
```

### 17. Emergency Shell Access

#### If SSH is broken but console works

```bash
# Enable root login temporarily
passwd root
systemctl restart sshd

# Fix SSH configuration
vi /etc/ssh/sshd_config
systemctl reload sshd
```

## Performance Optimization

### 18. ML Workload Performance Issues

#### Symptom: Slow GPU utilization

```bash
# Check GPU clock speeds
nvidia-smi -q -d CLOCK

# Monitor GPU utilization
nvidia-smi dmon

# Check thermal throttling
nvidia-smi -q -d TEMPERATURE

# Optimize GPU settings
nvidia-smi -pm 1  # Enable persistence mode
nvidia-smi -ac 5001,1400  # Set memory,graphics clocks
```

#### Symptom: Memory issues with large models

```bash
# Check system memory
free -h
cat /proc/meminfo

# Monitor GPU memory
nvidia-smi --query-gpu=memory.used,memory.total --format=csv

# Increase shared memory for containers
echo 'tmpfs /dev/shm tmpfs defaults,size=32g 0 0' >> /etc/fstab
mount -a
```

### 19. Storage Performance

#### Symptom: Slow disk I/O

```bash
# Test disk performance
hdparm -tT /dev/sda
dd if=/dev/zero of=/tmp/test bs=1M count=1000

# Check filesystem type and options
mount | grep /data
tune2fs -l /dev/sda2

# Monitor I/O
iotop
iostat 1
```

## Monitoring and Logging

### 20. Setting Up Comprehensive Logging

```bash
# Enable detailed logging
journalctl --verify
systemctl status systemd-journald

# Configure log retention
mkdir -p /etc/systemd/journald.conf.d
cat > /etc/systemd/journald.conf.d/retention.conf << EOF
[Journal]
SystemMaxUse=1G
SystemMaxFileSize=100M
SystemMaxFiles=10
MaxRetentionSec=1week
EOF

systemctl restart systemd-journald
```

### 21. Automated Health Checks

Create a comprehensive health check script:

```bash
#!/bin/bash
# /usr/local/bin/system-health-check.sh

log_file="/var/log/health-check.log"
timestamp=$(date '+%Y-%m-%d %H:%M:%S')

echo "[$timestamp] Starting system health check" >> "$log_file"

# Check disk space
disk_usage=$(df / | awk 'NR==2 {print $5}' | sed 's/%//')
if [ "$disk_usage" -gt 90 ]; then
    echo "[$timestamp] WARNING: Disk usage is ${disk_usage}%" >> "$log_file"
fi

# Check memory usage
mem_usage=$(free | awk 'NR==2{printf "%.2f", $3*100/$2}')
if (( $(echo "$mem_usage > 90" | bc -l) )); then
    echo "[$timestamp] WARNING: Memory usage is ${mem_usage}%" >> "$log_file"
fi

# Check GPU status
if command -v nvidia-smi >/dev/null; then
    gpu_temp=$(nvidia-smi --query-gpu=temperature.gpu --format=csv,noheader,nounits)
    if [ "$gpu_temp" -gt 80 ]; then
        echo "[$timestamp] WARNING: GPU temperature is ${gpu_temp}°C" >> "$log_file"
    fi
fi

# Check critical services
services=("sshd" "NetworkManager" "docker")
for service in "${services[@]}"; do
    if ! systemctl is-active --quiet "$service"; then
        echo "[$timestamp] ERROR: Service $service is not running" >> "$log_file"
    fi
done

echo "[$timestamp] Health check completed" >> "$log_file"
```

Add to systemd timer:

```bash
# /etc/systemd/system/health-check.timer
[Unit]
Description=System Health Check Timer

[Timer]
OnCalendar=*:0/15  # Every 15 minutes
Persistent=true

[Install]
WantedBy=timers.target
```

## Common Error Patterns

### 22. Error Message Reference

| Error | Likely Cause | Solution |
|-------|--------------|----------|
| `mount: /mnt: special device /dev/sda2 does not exist` | Wrong disk device | Check `lsblk`, adjust device names |
| `NVIDIA-SMI has failed because it couldn't communicate with the NVIDIA driver` | Driver not loaded | Rebuild with GPU module enabled |
| `Failed to start Load Kernel Modules` | Module conflicts | Check `dmesg`, rebuild initrd |
| `nixos-rebuild switch` fails with evaluation error | Flake syntax error | Run `nix flake check`, fix syntax |
| `docker: Error response from daemon: could not select device driver` | NVIDIA runtime missing | Install nvidia-container-toolkit |
| `Permission denied (publickey)` | SSH key issues | Verify key format and authorized_keys |
| `No space left on device` during install | Insufficient disk space | Check disk size, clean up space |
| `Network is unreachable` | Network configuration | Check routing, DNS, firewall |

### 23. Prevention Strategies

#### Automated Testing

```bash
# Create validation script for new deployments
#!/bin/bash
# /usr/local/bin/validate-deployment.sh

errors=0

# Test GPU
if ! nvidia-smi >/dev/null 2>&1; then
    echo "ERROR: GPU not accessible"
    ((errors++))
fi

# Test ML services
services=("jupyterlab" "mlflow" "tensorboard")
for service in "${services[@]}"; do
    if ! systemctl is-active --quiet "$service"; then
        echo "ERROR: $service not running"
        ((errors++))
    fi
done

# Test network connectivity
if ! ping -c 1 8.8.8.8 >/dev/null 2>&1; then
    echo "ERROR: No internet connectivity"
    ((errors++))
fi

# Test SSH
if ! ss -tlnp | grep -q :22; then
    echo "ERROR: SSH not listening"
    ((errors++))
fi

if [ $errors -eq 0 ]; then
    echo "All validation checks passed"
    exit 0
else
    echo "Validation failed with $errors errors"
    exit 1
fi
```

#### Configuration Backup

```bash
# Automated configuration backup
#!/bin/bash
backup_dir="/backup/nixos-config-$(date +%Y%m%d)"
mkdir -p "$backup_dir"

# Backup critical files
cp -r /etc/nixos "$backup_dir/"
nixos-generate-config --show-hardware-config > "$backup_dir/hardware-config-backup.nix"

# Create system info snapshot
{
    echo "=== System Information ==="
    uname -a
    nixos-version
    echo -e "\n=== Hardware ==="
    lscpu
    lsmem --summary
    nvidia-smi -L 2>/dev/null || echo "No NVIDIA GPUs found"
    echo -e "\n=== Network ==="
    ip addr
    echo -e "\n=== Services ==="
    systemctl list-units --failed
} > "$backup_dir/system-info.txt"

echo "Backup created in $backup_dir"
```

## Getting Help

### 24. Information to Gather for Support

When seeking help, collect this information:

```bash
#!/bin/bash
# System information gathering script
output_file="debug-info-$(date +%Y%m%d-%H%M%S).txt"

{
    echo "=== NixOS Debug Information ==="
    echo "Generated: $(date)"
    echo

    echo "=== System ==="
    uname -a
    nixos-version
    nix --version

    echo -e "\n=== Hardware ==="
    lscpu | head -20
    lsmem --summary
    lspci | grep -E "(VGA|3D|GPU)"

    echo -e "\n=== Disks ==="
    lsblk
    df -h

    echo -e "\n=== Memory ==="
    free -h

    echo -e "\n=== Network ==="
    ip addr show
    ip route show

    echo -e "\n=== Services ==="
    systemctl --failed --no-pager

    echo -e "\n=== Recent Errors ==="
    journalctl --since "1 hour ago" --priority=err --no-pager | tail -20

    echo -e "\n=== GPU Status ==="
    nvidia-smi 2>/dev/null || echo "No NVIDIA GPU or driver issues"

    echo -e "\n=== NixOS Configuration ==="
    if [ -f /etc/nixos/flake.nix ]; then
        echo "Using flake configuration"
        nix flake show /etc/nixos 2>/dev/null || echo "Flake show failed"
    else
        echo "Using traditional configuration"
    fi

} > "$output_file"

echo "Debug information saved to: $output_file"
```

### 25. Useful Resources

- **NixOS Manual**: <https://nixos.org/manual/nixos/stable/>
- **Nix Pills**: <https://nixos.org/guides/nix-pills/>
- **NixOS Hardware**: <https://github.com/NixOS/nixos-hardware>
- **GPU Passthrough**: <https://nixos.wiki/wiki/Nvidia>
- **iPXE Documentation**: <https://ipxe.org/docs>

This troubleshooting guide should help you resolve most common issues with the
automated NixOS installation system. Remember to always backup your
configuration before making significant changes, and test modifications in a
virtual machine when possible.
