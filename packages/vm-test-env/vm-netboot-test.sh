# shellcheck disable=SC2148 # writeShellApplication adds the she-bang

# Read test configuration parameters
# shellcheck source=/dev/null
source "${1:-"$DEFAULT_CONF"}"

: "${MEMORY:=4G}"
: "${DISK_SIZE:-10G}"
: "${IMAGE:=build/vm/test-vm.qcow2}"
: "${SSH_KEY_PATH=build/vm/keys/user}"
: "${TFTP_DIR:=build/vm/tftp}"

# Function to find available port
find_available_port() {
  local start_port=$1
  local port=$start_port
  while netstat -ln | grep -q ":$port "; do
    port=$((port + 1))
  done
  echo "$port"
}

# Auto-detect available ports
SSH_PORT=$(find_available_port 2222)
MONITOR_PORT=$(find_available_port 4444)
VNC_PORT=$(find_available_port 5901)

echo "=== NixOS Netboot Installer Test ==="
echo "Auto-detected ports:"
echo "  VNC Display: :$((VNC_PORT - 5900))"
echo "  QEMU Monitor: $MONITOR_PORT"
echo "  SSH Forward: $SSH_PORT"
echo

# Create test disk and build directories
mkdir -p "$(dirname "$IMAGE")"
if [[ ! -f "$IMAGE" ]]; then
  echo "Creating test disk..."
  qemu-img create -f qcow2 "$IMAGE" "$DISK_SIZE"
fi

# Generate test SSH key
if [[ -n "$SSH_KEY_PATH" ]]; then
  mkdir -p "$(dirname "$SSH_KEY_PATH")"
  if ! [ -f "$SSH_KEY_PATH.pub" ]; then
    ssh-keygen -t ed25519 -f "$SSH_KEY_PATH" -N "" -C "user@vybovaly-installer"
  fi
  TEST_SSH_KEY=$(cat "$SSH_KEY_PATH.pub")
fi

# Build TFTP files
mkdir -p "$TFTP_DIR"
rm -f "$TFTP_DIR"/*
for f in "$TFTP_SRC"/*; do
  ln -s "$f" "$TFTP_DIR"/
done

# Build ipxe parameters
cmdline+=("${USERNAME:+"vyb.username=$USERNAME"}")
cmdline+=("${TEST_SSH_KEY:+"vyb.ssh_key='$TEST_SSH_KEY'"}")
cmdline+=("${HOSTNAME:+"vyb.hostname=$HOSTNAME"}")
cmdline+=("${DISK_LAYOUT:+"vyb.disk_layout=$DISK_LAYOUT"}")
cmdline+=("${FLAKE_TARBALL:+"vyb.flake_url=tftp://10.0.2.2/$FLAKE_TARBALL"}")
cmdline+=("${ACCESS_TOKENS:+"vyb.access_tokens='$ACCESS_TOKENS'"}")
cmdline+=("${DEBUG:+"vyb.debug=1"}")
{
  echo '#!ipxe'
  echo "set cmdline ${cmdline[*]}"
  echo "chain netboot.ipxe"
} > "$TFTP_DIR/test.ipxe"

export MEMORY IMAGE SSH_PORT VNC_PORT MONITOR_PORT USERNAME DISK_SIZE SSH_KEY_PATH TFTP_DIR
exec mprocs --config "$MPROCS_CONFIG"
