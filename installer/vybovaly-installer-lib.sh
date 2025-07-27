# shellcheck disable=SC2148 # should only ever be sourced

set -f

# Global variables
VYB_USERNAME=""
VYB_SSH_KEY=""
VYB_HOSTNAME=""
VYB_DISK_LAYOUT=""
VYB_FLAKE_URL=""
VYB_DEBUG=""
export NIX_USER_CONF_FILES=/nix.conf

# Parse kernel command line
parse_kernel_cmdline() {
    local -a cmdline
    if [[ "${#@}" -gt 0 ]]; then
        cmdline=("$@")
    else
        eval "cmdline=($(cat /proc/cmdline))"
    fi

    for param in "${cmdline[@]}"; do
        case $param in
            vyb.username=*)
                VYB_USERNAME="${param#*=}"
                ;;
            vyb.ssh_key=*)
                VYB_SSH_KEY="${param#*=}"
                ;;
            vyb.hostname=*)
                VYB_HOSTNAME="${param#*=}"
                ;;
            vyb.disk_layout=*)
                VYB_DISK_LAYOUT="${param#*=}"
                ;;
            vyb.flake_url=*)
                VYB_FLAKE_URL="${param#*=}"
                ;;
            vyb.access_tokens=*)
                echo "extra-access-tokens = ${param#*=}" >> /nix.conf
                ;;
            vyb.debug=*)
                VYB_DEBUG="${param#*=}"
                ;;
            vyb.debug)
                VYB_DEBUG=1
                ;;
        esac
    done

    # Debug output if enabled
    if [[ -n "$VYB_DEBUG" ]]; then
        echo "Debug mode enabled"
        set -x
    fi
}

# Check if automation should run
should_run_automation() {
    parse_kernel_cmdline "$@"

    if [[ -n "$VYB_SSH_KEY" ]]; then
        for f in /root/.ssh/authorized_keys /root/.ssh/authorized_keys2 /etc/ssh/authorized_keys.d/root; do
            if ! [[ -e "$f" ]] || [[ -w "$f" ]]; then
                echo "$VYB_SSH_KEY" >> "$f" && break;
            fi
        done
    fi

    # All good if flake URL is given
    if [[ -n "$VYB_FLAKE_URL" ]]; then
        return 0
    fi

    # Otherwise require username and ssh_key for basic configuration
    [[ -n "$VYB_USERNAME" ]] && [[ -n "$VYB_SSH_KEY" ]]
}

# Wait for network connectivity
wait_for_network() {
    local retries=0
    local max_retries=60

    echo "Waiting for network connectivity..."

    while true; do
        if [[ $retries -ge $max_retries ]]; then
            echo "Error: No network connectivity after $max_retries attempts"
            return 1
        fi

        # Test connectivity by trying to reach the flake URL if provided
        if [[ -n "$VYB_FLAKE_URL" ]]; then
            if curl -s -o /dev/null "$VYB_FLAKE_URL"; then
                echo "Network connectivity established (can reach flake URL)"
                return 0
            fi
        else
            # Fallback: try to reach Nix cache (needed for installation anyway)
            if curl -I -s -w "%{http_code}" -o /dev/null "https://cache.nixos.org/nix-cache-info"; then
                echo "Network connectivity established (can reach Nix cache)"
                return 0
            fi
        fi

        echo "Waiting for network... (attempt $((retries + 1))/$max_retries)"
        sleep 5
        retries=$((retries + 1))
    done
}

# Built-in installer implementation using direct flake installation
run_installer() {
    echo "Running built-in automated installer with flake support..."

    # Set defaults
    local username="${VYB_USERNAME}"
    local ssh_key="${VYB_SSH_KEY}"
    local hostname="${VYB_HOSTNAME:-nixos}"
    local disk_layout="${VYB_DISK_LAYOUT:-single}"
    local flake_url="${VYB_FLAKE_URL}"

    echo "Installation parameters:"
    echo "  Username: $username"
    echo "  Hostname: $hostname"
    echo "  Disk layout: $disk_layout"
    echo "  Flake URL: $flake_url"

    # Validate required parameters
    if [[ -n "$flake_url" ]]; then
        echo "Using flake configuration - user details defined in flake"
    else
        if [[ -z "$username" ]] || [[ -z "$ssh_key" ]]; then
            echo "Error: username and ssh_key are required when not using a flake"
            return 1
        fi
    fi

    # Partition disks
    partition_disks "$disk_layout"

    if [[ -n "$flake_url" ]]; then
        # Handle flake installation
        if [[ "$flake_url" == "tftp://"* ]] || [[ "$flake_url" == *".tar.gz" ]]; then
            # Download TFTP tarball flake
            echo "Downloading flake tarball: $flake_url"
            local flake_tarball="/tmp/vybovaly-installer/flake.tar.gz"
            curl -s -o "$flake_tarball" "$flake_url"
            flake_url="file://$flake_tarball"
        fi

        echo "Installing NixOS from flake: $flake_url${hostname:+#$hostname}"
        nixos-install \
            --root /mnt \
            --flake "$flake_url${hostname:+#$hostname}" \
            --no-root-passwd --no-write-lock-file

        # Add automation SSH key if provided and no authorized_keys file exists
        add_automation_ssh_key_if_needed "$username" "$ssh_key"
    else
        # Fallback: create basic configuration and install
        echo "No flake URL provided, creating basic configuration..."
        create_basic_configuration "$username" "$ssh_key" "$hostname"
        nixos-install --root /mnt --no-root-passwd --flake '/mnt/etc/nixos#nixos'
    fi

    echo "Installation completed successfully!"
    echo "Rebooting in 10 seconds..."
    sleep 10
    reboot
}

# Disk partitioning function
partition_disks() {
    local layout="$1"

    case "$layout" in
        single)
            partition_single_disk
            ;;
        raid)
            partition_raid_disks
            ;;
        *)
            echo "Unknown disk layout: $layout"
            exit 1
            ;;
    esac
}

# Single disk partitioning using disko
partition_single_disk() {
    # Auto-detect the first suitable disk (>1GB, sorted by size ascending)
    local disk
    local min_size=$((1024*1024*1024))  # 1GB in bytes

    while read -r name size type; do
        if [[ "$type" == "disk" ]] && [[ "$size" -gt "$min_size" ]]; then
            disk="$name"
            break
        fi
    done < <(lsblk -xSIZE -bpno NAME,SIZE,TYPE)

    if [[ -z "$disk" ]]; then
        echo "Error: No suitable disk found for installation (need >1GB)"
        echo "Available block devices:"
        lsblk
        exit 1
    fi

    echo "Auto-detected disk: $disk ($(numfmt --to=iec --format="%.1f" "$(lsblk -bno SIZE "$disk")")))"
    echo "Using disko for declarative disk partitioning"

    # Create disko configuration for single disk
    local disko_config="/tmp/vybovaly-installer/disko-config.nix"
    cat > "$disko_config" << EOF
{
  disko.devices = {
    disk = {
      main = {
        type = "disk";
        device = "$disk";
        content = {
          type = "gpt";
          partitions = {
            bios = {
              priority = 1;
              name = "bios";
              start = "1M";
              size = "1M";
              type = "EF02";  # BIOS Boot Partition
            };
            boot = {
              priority = 2;
              name = "boot";
              start = "2M";
              size = "1022M";  # 1024M - 2M = 1022M to reach 1G total
              type = "8300";
              content = {
                type = "filesystem";
                format = "ext4";
                mountpoint = "/boot";
                mountOptions = [
                  "defaults"
                ];
                extraArgs = [ "-L" "boot" ];
              };
            };
            root = {
              size = "100%";
              content = {
                type = "filesystem";
                format = "ext4";
                mountpoint = "/";
                extraArgs = [ "-L" "nixos" ];
              };
            };
          };
        };
      };
    };
  };
}
EOF

    echo "Partitioning disk with disko..."
    disko --mode disko "$disko_config"

    echo "Single disk partitioning completed"
}

# RAID disk partitioning using disko
partition_raid_disks() {
    # Auto-detect suitable disks (>1GB, sorted by size ascending, need at least 2)
    local disks=()
    local min_size=$((1024*1024*1024))  # 1GB in bytes

    while read -r name size type; do
        if [[ "$type" == "disk" ]] && [[ "$size" -gt "$min_size" ]]; then
            disks+=("$name")
        fi
    done < <(lsblk -xSIZE -bpno NAME,SIZE,TYPE)

    if [[ ${#disks[@]} -lt 2 ]]; then
        echo "Error: Need at least 2 suitable disks for RAID configuration (each >1GB)"
        echo "Available disks: ${disks[*]}"
        lsblk
        exit 1
    fi

    local disk1="${disks[0]}"
    local disk2="${disks[1]}"

    echo "Auto-detected disks: $disk1 ($(numfmt --to=iec --format="%.1f" "$(lsblk -bno SIZE "$disk1")")), $disk2 ($(numfmt --to=iec --format="%.1f" "$(lsblk -bno SIZE "$disk2")")"
    echo "Using disko for RAID1 configuration"

    # Create disko configuration for RAID1
    local disko_config="/tmp/vybovaly-installer/disko-raid-config.nix"
    cat > "$disko_config" << EOF
{
  disko.devices = {
    disk = {
      disk1 = {
        type = "disk";
        device = "$disk1";
        content = {
          type = "gpt";
          partitions = {
            ESP = {
              priority = 1;
              name = "ESP";
              start = "1M";
              end = "1G";
              type = "EF00";
              content = {
                type = "filesystem";
                format = "vfat";
                mountpoint = "/boot";
                extraArgs = [ "-n" "boot" ];
              };
            };
            raid = {
              size = "100%";
              content = {
                type = "mdraid";
                name = "raid1";
              };
            };
          };
        };
      };
      disk2 = {
        type = "disk";
        device = "$disk2";
        content = {
          type = "gpt";
          partitions = {
            raid = {
              size = "100%";
              content = {
                type = "mdraid";
                name = "raid1";
              };
            };
          };
        };
      };
    };
    mdadm = {
      raid1 = {
        type = "mdadm";
        level = 1;
        content = {
          type = "filesystem";
          format = "ext4";
          mountpoint = "/";
          extraArgs = [ "-L" "nixos" ];
        };
      };
    };
  };
}
EOF

    echo "Partitioning disks with disko RAID1..."
    disko --mode disko "$disko_config"

    echo "RAID disk partitioning completed"
}

# Create basic NixOS configuration
create_basic_configuration() {
    local username="$1"
    local ssh_key="$2"
    local hostname="$3"

    echo "Creating NixOS configuration..."

    # Generate hardware configuration
    echo "Generating hardware configuration..."
    nixos-generate-config --root /mnt --flake

    cat > /mnt/etc/nixos/configuration.nix << EOF
{ config, pkgs, ... }:

{
  imports = [ ./hardware-configuration.nix ];

  # Boot loader
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  # Networking
  networking.hostName = "${hostname:-nixos}";
  networking.networkmanager.enable = true;

  # SSH
  services.openssh = {
    enable = true;
    settings.PasswordAuthentication = false;
    settings.PermitRootLogin = "no";
  };

  # User configuration
  users.users.$username = {
    isNormalUser = true;
    extraGroups = [ "wheel" "networkmanager" ];
    openssh.authorizedKeys.keys = [
      "$ssh_key"
    ];
  };

  # Security
  security.sudo.wheelNeedsPassword = false;

  # Basic packages
  environment.systemPackages = with pkgs; [
    vim git curl wget htop
  ];

  # Enable flakes
  nix.settings.experimental-features = [ "nix-command" "flakes" ];

  # Firewall
  networking.firewall.allowedTCPPorts = [ 22 ];

  system.stateVersion = "25.05";
}
EOF
}

# Add automation SSH key if provided and authorized_keys doesn't exist
add_automation_ssh_key_if_needed() {
    local target_username="$1"
    local automation_ssh_key="$2"

    # Skip if no SSH key or username provided
    if [[ -z "$automation_ssh_key" ]] || [[ -z "$target_username" ]]; then
        echo "No automation SSH key or username provided, skipping SSH key injection"
        return 0
    fi

    local user_home="/mnt/home/$target_username"
    local ssh_dir="$user_home/.ssh"
    local authorized_keys_file="$ssh_dir/authorized_keys"

    echo "Checking SSH key injection for user: $target_username"

    # Check if authorized_keys already exists
    if [[ -f "$authorized_keys_file" ]]; then
        echo "SSH authorized_keys file already exists, skipping automation key injection"
        echo "Existing keys preserved in user's configuration"
        return 0
    fi

    # Check if user home directory exists
    if [[ ! -d "$user_home" ]]; then
        echo "Warning: User home directory $user_home not found, skipping SSH key injection"
        return 0
    fi

    echo "Adding automation SSH key for bootstrap access..."

    # Create .ssh directory if it doesn't exist
    mkdir -p "$ssh_dir"

    # Add the automation SSH key
    echo "$automation_ssh_key" > "$authorized_keys_file"
    echo "# Added by vybovaly installer for bootstrap access" >> "$authorized_keys_file"

    # Set proper permissions and ownership
    chown -R "$(stat -c %u "$user_home")":"$(stat -c %g "$user_home")" "$ssh_dir"
    chmod 700 "$ssh_dir"
    chmod 600 "$authorized_keys_file"

    echo "Automation SSH key added successfully"
    echo "Note: This key provides bootstrap access - add your permanent keys via NixOS configuration"
}

# Main automation function
run_automated_installation() {
    echo "Starting automated NixOS installation..."

    # Parse command line
    parse_kernel_cmdline

    # Wait for network
    wait_for_network || {
        echo "Network setup failed, cannot continue"
        exit 1
    }

    run_installer
}
