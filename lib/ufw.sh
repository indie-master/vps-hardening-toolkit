#!/usr/bin/env bash
set -euo pipefail

if [[ -n "${VPS_HARDENING_UFW_SH:-}" ]]; then
  return 0
fi
VPS_HARDENING_UFW_SH=1

# shellcheck disable=SC1091
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

readonly CF_NETWORKS=(
  "173.245.48.0/20" "103.21.244.0/22" "103.22.200.0/22" "103.31.4.0/22"
  "141.101.64.0/18" "108.162.192.0/18" "190.93.240.0/20" "188.114.96.0/20"
  "197.234.240.0/22" "198.41.128.0/17" "162.158.0.0/15" "104.16.0.0/13"
  "104.24.0.0/14" "172.64.0.0/13" "131.0.72.0/22" "2400:cb00::/32"
  "2606:4700::/32" "2803:f800::/32" "2405:b500::/32" "2405:8100::/32"
  "2a06:98c0::/29" "2c0f:f248::/32"
)

ufw::has_rule() {
  local check="$1"
  ufw status | grep -Fq "$check"
}

ufw::allow_once() {
  local rule="$1"
  if ufw::has_rule "$rule"; then
    log::ok "UFW rule already exists: $rule"
  else
    ufw allow "$rule"
    log::ok "UFW rule added: $rule"
  fi
}

ufw::allow_network_once() {
  local cidr="$1"
  local comment="${2:-}"
  if ufw status numbered | grep -Fq "$cidr"; then
    log::ok "UFW rule already exists for network: $cidr"
    return
  fi

  if [[ -n "$comment" ]]; then
    ufw allow from "$cidr" comment "$comment"
  else
    ufw allow from "$cidr"
  fi
  log::ok "Allowed network in UFW: $cidr"
}

ufw::add_custom_ips() {
  log::info "Add custom trusted IP/CIDR for UFW (blank to finish)."
  while true; do
    local cidr comment
    read -r -p "Trusted IP/CIDR: " cidr
    cidr="$(text::trim "$cidr")"
    [[ -z "$cidr" ]] && break

    if net::is_valid_ipv4 "$cidr" || net::is_valid_cidr4 "$cidr" || net::is_valid_ipv6_or_cidr "$cidr"; then
      read -r -p "Comment (optional): " comment
      ufw::allow_network_once "$cidr" "$comment"
    else
      log::warn "Invalid IP/CIDR skipped: $cidr"
    fi
  done
}

ufw::ensure_ssh_rule() {
  if ufw status | grep -Eq 'OpenSSH|22/tcp'; then
    log::ok "SSH allow rule already present."
  else
    ufw allow OpenSSH
    log::ok "Added UFW OpenSSH rule."
  fi
}

ufw::configure_logrotate() {
  cat > /etc/logrotate.d/ufw <<'CONF'
/var/log/ufw.log {
    weekly
    rotate 8
    compress
    delaycompress
    missingok
    notifempty
    create 0640 root adm
}
CONF
  chmod 644 /etc/logrotate.d/ufw
  log::ok "Configured logrotate for UFW log."
}

ufw::configure() {
  require_root
  pkg::install_if_missing ufw

  ufw::ensure_ssh_rule
  ufw::allow_once OpenSSH

  if ufw app info 'Nginx Full' >/dev/null 2>&1; then
    ufw::allow_once 'Nginx Full'
  else
    log::warn "UFW app profile 'Nginx Full' not found."
    if prompt::yes_no "Allow 80/tcp and 443/tcp manually?" "yes"; then
      ufw::allow_once '80/tcp'
      ufw::allow_once '443/tcp'
    fi
  fi

  log::info "Applying required Cloudflare network allow rules."
  for cidr in "${CF_NETWORKS[@]}"; do
    ufw::allow_network_once "$cidr" "vps-hardening-cloudflare"
  done

  ufw::add_custom_ips

  if ! ufw status | grep -Eq 'OpenSSH|22/tcp'; then
    log::error "No SSH allow rule found. Refusing to enable UFW to avoid lockout."
    return 1
  fi

  if ! prompt::yes_no "Enable UFW now?" "no"; then
    log::warn "UFW enable skipped by user."
    ufw status verbose || true
    return 0
  fi

  ufw --force enable
  ufw::configure_logrotate
  ufw status verbose
  log::ok "UFW configuration complete."
}

ufw::status() {
  if command -v ufw >/dev/null 2>&1; then
    ufw status verbose || true
  else
    log::warn "UFW is not installed."
  fi
}
