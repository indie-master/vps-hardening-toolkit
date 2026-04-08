#!/usr/bin/env bash
set -euo pipefail

if [[ -n "${VPS_HARDENING_SSH_SH:-}" ]]; then
  return 0
fi
VPS_HARDENING_SSH_SH=1

# shellcheck disable=SC1091
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

readonly SSH_DROPIN="/etc/ssh/sshd_config.d/99-vps-hardening.conf"
readonly SSH_KEY_DIR="/root/.ssh/vps-hardening"

ssh::ensure_permissions() {
  mkdir -p /root/.ssh
  chmod 700 /root/.ssh
  chown root:root /root/.ssh

  touch /root/.ssh/authorized_keys
  chmod 600 /root/.ssh/authorized_keys
  chown root:root /root/.ssh/authorized_keys

  log::ok "SSH permissions fixed for /root/.ssh and authorized_keys."
}

ssh::has_valid_root_key() {
  [[ -s /root/.ssh/authorized_keys ]] && grep -Eq '^(ssh-ed25519|ssh-rsa|ecdsa-sha2-nistp)' /root/.ssh/authorized_keys
}

ssh::generate_keypair() {
  mkdir -p "$SSH_KEY_DIR"
  chmod 700 "$SSH_KEY_DIR"

  local ts key_name private_key public_key
  ts="$(date '+%Y%m%d-%H%M%S')"
  key_name="root-ed25519-${ts}"
  private_key="$SSH_KEY_DIR/$key_name"
  public_key="$SSH_KEY_DIR/$key_name.pub"

  ssh-keygen -t ed25519 -a 100 -N '' -C "vps-hardening-${ts}" -f "$private_key" >/dev/null
  chmod 600 "$private_key"
  chmod 644 "$public_key"

  cat "$public_key" >> /root/.ssh/authorized_keys
  sort -u /root/.ssh/authorized_keys -o /root/.ssh/authorized_keys
  log::ok "Generated and installed key pair: $private_key"

  printf '\nPrivate key handling options:\n'
  printf '1) Use SCP: scp root@<SERVER_IP>:%s ./%s\n' "$private_key" "$key_name"
  printf '2) Print private key now (not recommended)\n'
  printf '3) Send private key via Telegram Bot API\n'
  printf '4) Skip\n'

  local option
  read -r -p "Choose option [1-4]: " option
  case "$option" in
    1)
      log::info "Use the displayed scp command to copy private key securely."
      ;;
    2)
      log::warn "Displaying private key in terminal. Ensure no one can see/capture this session."
      cat "$private_key"
      ;;
    3)
      ssh::send_key_telegram "$private_key"
      ;;
    *)
      log::info "Skipped key export actions."
      ;;
  esac
}

ssh::send_key_telegram() {
  local private_key="$1"
  local bot_token chat_id
  read -r -p "Enter Telegram BOT_TOKEN: " bot_token
  read -r -p "Enter Telegram CHAT_ID: " chat_id

  if [[ -z "$bot_token" || -z "$chat_id" ]]; then
    log::warn "BOT_TOKEN or CHAT_ID empty; skipped Telegram export."
    return 0
  fi

  if ! command -v curl >/dev/null 2>&1; then
    pkg::install_if_missing curl
  fi

  if curl -fsS -X POST "https://api.telegram.org/bot${bot_token}/sendDocument" \
    -F chat_id="$chat_id" \
    -F document=@"$private_key" >/dev/null; then
    log::ok "Private key sent to Telegram chat ${chat_id}."
  else
    log::error "Failed to send private key via Telegram API."
    return 1
  fi
}

ssh::manual_key_add() {
  log::info "Paste your public key (single line), then press Enter:"
  local pubkey
  read -r pubkey
  if [[ ! "$pubkey" =~ ^(ssh-ed25519|ssh-rsa|ecdsa-sha2-nistp)\  ]]; then
    log::error "Invalid SSH public key format."
    return 1
  fi

  printf '%s\n' "$pubkey" >> /root/.ssh/authorized_keys
  sort -u /root/.ssh/authorized_keys -o /root/.ssh/authorized_keys
  log::ok "Public key added to /root/.ssh/authorized_keys."
}

ssh::write_dropin() {
  fs::backup_file "$SSH_DROPIN"
  cat > "$SSH_DROPIN" <<'CONF'
# Managed by vps-hardening-toolkit
PubkeyAuthentication yes
PasswordAuthentication no
PermitRootLogin prohibit-password
CONF
  chmod 644 "$SSH_DROPIN"
  log::ok "Updated SSH drop-in config: $SSH_DROPIN"
}

ssh::configure() {
  require_root
  ssh::ensure_permissions

  printf '\nSSH key setup options:\n'
  printf '1) Generate ed25519 key pair on server\n'
  printf '2) Paste existing public key manually\n'
  printf '3) Skip key actions\n'

  local action
  read -r -p "Choose option [1-3]: " action
  case "$action" in
    1) ssh::generate_keypair ;;
    2) ssh::manual_key_add ;;
    3) log::info "Skipping SSH key setup." ;;
    *) log::warn "Unknown option. Skipping." ;;
  esac

  ssh::ensure_permissions

  if ! ssh::has_valid_root_key; then
    log::warn "No valid SSH key found in /root/.ssh/authorized_keys."
    log::warn "PasswordAuthentication will not be disabled to avoid lockout."
    return 0
  fi

  if ! prompt::yes_no "Disable SSH password authentication and apply hardened settings?" "no"; then
    log::info "User declined password authentication disable."
    return 0
  fi

  ssh::write_dropin

  if ! sshd -t; then
    log::error "sshd configuration test failed. Dangerous changes were not applied."
    return 1
  fi

  log::info "sshd -t passed. Ready to restart SSH service."
  if ! prompt::yes_no "Restart SSH service now?" "no"; then
    log::warn "Skipped SSH restart by user choice."
    return 0
  fi

  if systemctl list-unit-files | grep -q '^ssh\.service'; then
    svc::restart_and_check ssh
  else
    svc::restart_and_check sshd
  fi
}

ssh::status() {
  if [[ -f "$SSH_DROPIN" ]]; then
    log::info "SSH drop-in config found: $SSH_DROPIN"
    sed 's/^/  /' "$SSH_DROPIN"
  else
    log::warn "SSH drop-in config not found: $SSH_DROPIN"
  fi

  if ssh::has_valid_root_key; then
    log::ok "At least one valid SSH public key is present for root."
  else
    log::warn "No valid SSH public keys found for root."
  fi
}
