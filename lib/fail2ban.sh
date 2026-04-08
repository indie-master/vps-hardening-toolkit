#!/usr/bin/env bash
set -euo pipefail

if [[ -n "${VPS_HARDENING_FAIL2BAN_SH:-}" ]]; then
  return 0
fi
VPS_HARDENING_FAIL2BAN_SH=1

# shellcheck disable=SC1091
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

readonly F2B_LOCAL="/etc/fail2ban/fail2ban.local"
readonly F2B_JAIL="/etc/fail2ban/jail.local"
readonly F2B_BLOCK_BEGIN="# BEGIN VPS-HARDENING"
readonly F2B_BLOCK_END="# END VPS-HARDENING"

fail2ban::collect_ignoreip() {
  local entries=()
  log::info "Enter trusted IP/CIDR for fail2ban ignoreip (blank to finish)."
  while true; do
    local ip
    read -r -p "Trusted IP/CIDR: " ip
    ip="$(text::trim "$ip")"
    [[ -z "$ip" ]] && break

    if net::is_valid_ipv4 "$ip" || net::is_valid_cidr4 "$ip" || net::is_valid_ipv6_or_cidr "$ip"; then
      entries+=("$ip")
    else
      log::warn "Invalid IP/CIDR skipped: $ip"
    fi
  done

  if [[ ${#entries[@]} -eq 0 ]]; then
    printf '127.0.0.1/8 ::1\n'
  else
    printf '127.0.0.1/8 ::1 %s\n' "${entries[*]}"
  fi
}

fail2ban::write_configs() {
  mkdir -p /etc/fail2ban

  if [[ -f "$F2B_LOCAL" ]]; then fs::backup_file "$F2B_LOCAL"; fi
  if [[ -f "$F2B_JAIL" ]]; then fs::backup_file "$F2B_JAIL"; fi

  cat > "$F2B_LOCAL" <<'CONF'
[Definition]
loglevel = INFO
logtarget = /var/log/fail2ban.log
socket = /var/run/fail2ban/fail2ban.sock
pidfile = /var/run/fail2ban/fail2ban.pid
CONF

  local ignoreip
  ignoreip="$(fail2ban::collect_ignoreip)"

  cat > "$F2B_JAIL" <<CONF
$F2B_BLOCK_BEGIN
[DEFAULT]
ignoreip = $ignoreip
bantime = 10800
findtime = 600
maxretry = 3

[sshd]
enabled = true
port = ssh
filter = sshd
logpath = /var/log/auth.log
maxretry = 3
bantime = 10800
findtime = 600
ignoreip = $ignoreip
$F2B_BLOCK_END
CONF

  chmod 644 "$F2B_LOCAL" "$F2B_JAIL"
  log::ok "Fail2Ban configs written."
}

fail2ban::configure_logrotate() {
  cat > /etc/logrotate.d/fail2ban <<'CONF'
/var/log/fail2ban.log {
    weekly
    rotate 8
    compress
    delaycompress
    missingok
    notifempty
    create 0640 root adm
    postrotate
        systemctl reload fail2ban >/dev/null 2>&1 || true
    endscript
}
CONF
  chmod 644 /etc/logrotate.d/fail2ban
  log::ok "Configured logrotate for fail2ban."
}

fail2ban::configure() {
  require_root
  pkg::install_if_missing fail2ban

  fail2ban::write_configs
  fail2ban::configure_logrotate

  if ! fail2ban-client -t; then
    log::error "Fail2Ban config test failed. Aborting restart."
    return 1
  fi

  systemctl enable fail2ban
  svc::restart_and_check fail2ban

  fail2ban-client status || true
  fail2ban-client status sshd || true

  log::ok "Fail2Ban configuration complete."
}

fail2ban::status() {
  systemctl is-enabled fail2ban >/dev/null 2>&1 && log::ok "fail2ban is enabled." || log::warn "fail2ban is not enabled."
  systemctl is-active fail2ban >/dev/null 2>&1 && log::ok "fail2ban is active." || log::warn "fail2ban is not active."
  fail2ban-client status || true
  fail2ban-client status sshd || true
}
