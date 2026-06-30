#!/bin/bash
# forja_bootstrap.sh
# one-file Arch bootstrap: partitions, base install, system config
# following arch wiki, assuming:
#   - ethernet connection
#   - uefi system
set -euo pipefail

info()  { printf "\033[1;34m[INFO]\033[0m %s\n" "$*"; }
error() { printf "\033[1;31m[ERROR]\033[0m %s\n" "$*"; }
success() { printf "\033[1;32m[SUCCESS]\033[0m %s\n" "$*"; }

# verify bootmode
if [ ! -f /sys/firmware/efi/fw_platform_size ]; then
  error "Bootmode legacy BIOS/CSM, not UEFI. Exiting..."
  exit 1
fi

info "UEFI bootmode: $(cat /sys/firmware/efi/fw_platform_size)-bit"

# enforce use of .env
if [ ! -f .env ]; then
  error ".env not found in working direcotry. Copy template_.env to .env and set your values." >&2
  exit 2
fi
source .env

# idempotent set key value on configuration file
set_key_value() { # pls don't use | as key/value
  local key="$1" value="$2" file="$3"
  local line="${key}=${value}"
  if grep -q "^\s*${key}\s*=" "$file" 2>/dev/null; then
    sed -i "s|^\s*${key}\s*=.*|${line}|" "$file"
  else
    echo "${line}" >> "$file"
  fi
}

# 1.8 update system clock
info "Enabling NTP time sync"
timedatectl set-ntp true

# 1.9 partition disks
# resolve target
if [ -z "${DISK:-}" ] || [ ! -b "${DISK:-}" ]; then
  [ -n "${DISK:-}" ] && error "DISK='${DISK}' is not a block device."
  info "Available disks:"
  echo
  lsblk -dno NAME,SIZE,TYPE,TRAN,MODEL | awk '$3=="disk"' # filters column 3 (type) by "disk"
  echo

  names=() i=1
  while read -r name; do
    names+=("$name")
    printf "  %d) /dev/%s\n" "$i" "$name"
    i=$((i+1))
  done < <(lsblk -dno NAME,TYPE | awk '$2=="disk"{print $1}')

  [ "${#names[@]}" -gt 0 ] || { error "No disks found. Aborting."; exit 3; }
  echo
  while true; do
    read -rp "Type the number of the disk to install Arch to: " choice
    # if choice is a number in range break
    if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le "${#names[@]}" ]; then
      break
    fi
    error "Invalid selection. Enter a number between 1 and ${#names[@]}."
  done
  DISK="/dev/${names[$((choice-1))]}"
fi
info "Target disk: $DISK"



if [ -n "${PERS_KEY:-}" ] && [ -n "${KEYMAP_DIR:-}" ] && [ -n "${KEYMAP_WRITE:-}" ]; then
  info "Adding KEYMAP configuration from $PERS_KEYS to $KEYMAP_DIR"
  mkdir -p "$KEYMAP_DIR"
  cp "$PERS_KEYS" "$KEYMAP_DIR"
  set_key_value KEYMAP "$KEYMAP_WRITE" /etc/vconsole.conf
  info "Restarting systemd-vconsole service for the changes to take effect"
  systemctl restart systemd-vconsole-setup.service
  success "Successfully configured /etc/vconsole.conf"
else
  info "Keymap vars not set, skipping KEYMAP configuration"
fi



# no need to check for internet connection, assume its up scripts got git
# cloned anyway

if [ -n "${TIMEZONE:-}" ]; then
  info "Setting timezone: $TIMEZONE"
  timedatectl set-timezone "$TIMEZONE"
else
  info "TIMEZONE not set, skipping"
fi





