#!/usr/bin/env bash
set -euo pipefail

if [[ -n "${VPS_HARDENING_SYSTEM_SH:-}" ]]; then
  return 0
fi
VPS_HARDENING_SYSTEM_SH=1

# shellcheck disable=SC1091
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
# shellcheck disable=SC1091
source "$(dirname "${BASH_SOURCE[0]}")/ssh.sh"
# shellcheck disable=SC1091
source "$(dirname "${BASH_SOURCE[0]}")/fail2ban.sh"
# shellcheck disable=SC1091
source "$(dirname "${BASH_SOURCE[0]}")/ufw.sh"

system::doctor() {
  require_root
  os::ensure_supported

  log::info "Running doctor checks..."
  command -v sshd >/dev/null 2>&1 && log::ok "sshd binary found." || log::error "sshd binary missing."
  command -v fail2ban-client >/dev/null 2>&1 && log::ok "fail2ban-client found." || log::warn "fail2ban-client missing."
  command -v ufw >/dev/null 2>&1 && log::ok "ufw binary found." || log::warn "ufw binary missing."

  if sshd -t >/dev/null 2>&1; then
    log::ok "sshd configuration test passed."
  else
    log::error "sshd configuration test failed."
  fi

  log::info "Doctor checks finished."
}

system::status() {
  require_root
  log::info "--- SSH status ---"
  ssh::status
  log::info "--- Fail2Ban status ---"
  fail2ban::status
  log::info "--- UFW status ---"
  ufw::status
}

system::rollback() {
  require_root
  mkdir -p "$BACKUP_DIR"

  mapfile -t backups < <(find "$BACKUP_DIR" -maxdepth 1 -type f -name '*.bak' | sort -r)
  if [[ ${#backups[@]} -eq 0 ]]; then
    log::warn "No backup files found in $BACKUP_DIR"
    return 0
  fi

  log::info "Available backups:"
  local i=1
  for b in "${backups[@]}"; do
    printf '%d) %s\n' "$i" "$(basename "$b")"
    ((i++))
  done

  local choice
  read -r -p "Select backup number to restore: " choice
  if [[ ! "$choice" =~ ^[0-9]+$ ]] || ((choice < 1 || choice > ${#backups[@]})); then
    log::error "Invalid selection."
    return 1
  fi

  local selected file_name target
  selected="${backups[$((choice - 1))]}"
  file_name="$(basename "$selected")"
  target="${file_name%.*.*}"

  case "$target" in
    sshd_config) target="/etc/ssh/sshd_config" ;;
    99-vps-hardening.conf) target="/etc/ssh/sshd_config.d/99-vps-hardening.conf" ;;
    fail2ban.local) target="/etc/fail2ban/fail2ban.local" ;;
    jail.local) target="/etc/fail2ban/jail.local" ;;
    *)
      log::error "Unknown backup target for file: $file_name"
      return 1
      ;;
  esac

  cp -a "$selected" "$target"
  log::ok "Restored $target from $selected"

  if [[ "$target" == *sshd* ]]; then
    sshd -t && svc::restart_and_check ssh || true
  elif [[ "$target" == *fail2ban* || "$target" == *jail.local ]]; then
    fail2ban-client -t && svc::restart_and_check fail2ban || true
  fi
}
