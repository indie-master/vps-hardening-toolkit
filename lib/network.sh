#!/usr/bin/env bash
set -euo pipefail

if [[ -n "${VPS_HARDENING_NETWORK_SH:-}" ]]; then
  return 0
fi
VPS_HARDENING_NETWORK_SH=1

# shellcheck disable=SC1091
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

network::configure_bbr() {
  require_root

  if ! modinfo tcp_bbr >/dev/null 2>&1; then
    log::warn "tcp_bbr is not available for kernel $(uname -r); leaving congestion control unchanged."
    return 0
  fi

  cat > /etc/modules-load.d/bbr.conf <<'EOF'
tcp_bbr
EOF
  modprobe tcp_bbr

  cat > /etc/sysctl.d/99-bbr.conf <<'EOF'
# Managed by vps-hardening-toolkit
net.core.default_qdisc=fq
net.ipv4.tcp_congestion_control=bbr
EOF

  sysctl -q -p /etc/sysctl.d/99-bbr.conf

  if [[ "$(sysctl -n net.ipv4.tcp_congestion_control)" == "bbr" ]] && \
     [[ "$(sysctl -n net.core.default_qdisc)" == "fq" ]]; then
    log::ok "BBR enabled with fq qdisc."
  else
    log::error "BBR configuration did not become effective."
    return 1
  fi
}

network::status() {
  log::info "TCP congestion control: $(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null || echo unknown)"
  log::info "Default qdisc: $(sysctl -n net.core.default_qdisc 2>/dev/null || echo unknown)"
  log::info "Available congestion controls: $(sysctl -n net.ipv4.tcp_available_congestion_control 2>/dev/null || echo unknown)"
}
