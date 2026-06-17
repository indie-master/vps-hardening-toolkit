#!/usr/bin/env bash
set -euo pipefail

if [[ -n "${VPS_HARDENING_FAIL2BAN_SH:-}" ]]; then
  return 0
fi
VPS_HARDENING_FAIL2BAN_SH=1

# shellcheck disable=SC1091
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

readonly F2B_LOCAL="/etc/fail2ban/fail2ban.local"
readonly F2B_JAIL_DIR="/etc/fail2ban/jail.d"
readonly F2B_MANAGED_JAIL="/etc/fail2ban/jail.d/vps-hardening.local"
readonly F2B_NGINX_SCANNER_FILTER="/etc/fail2ban/filter.d/vps-hardening-nginx-scanner.conf"
readonly F2B_LOGROTATE="/etc/logrotate.d/vps-hardening-fail2ban"

# Runtime config can override every value below.
: "${VPSH_CONFIG_FILE:=/etc/vps-hardening/vps-hardening.env}"
[[ -f "$VPSH_CONFIG_FILE" ]] && source "$VPSH_CONFIG_FILE"

: "${VPSH_IGNORE_IPS:=127.0.0.1/8 ::1}"
: "${VPSH_BLOCKTYPE:=deny}"
: "${VPSH_USEDNS:=warn}"
: "${VPSH_DEFAULT_BANTIME:=1h}"
: "${VPSH_DEFAULT_FINDTIME:=10m}"
: "${VPSH_DEFAULT_MAXRETRY:=5}"
: "${VPSH_BANTIME_INCREMENT:=true}"
: "${VPSH_BANTIME_FACTOR:=2}"
: "${VPSH_BANTIME_MAXTIME:=7d}"
: "${VPSH_SSH_PORT:=auto}"
: "${VPSH_SSH_MODE:=aggressive}"
: "${VPSH_SSH_MAXRETRY:=3}"
: "${VPSH_SSH_FINDTIME:=10m}"
: "${VPSH_SSH_BANTIME:=6h}"
: "${VPSH_ENABLE_NGINX_JAILS:=true}"
: "${VPSH_NGINX_ACCESS_LOGS:=/var/log/nginx/access.log /var/log/nginx/*access.log}"
: "${VPSH_NGINX_ERROR_LOGS:=/var/log/nginx/error.log /var/log/nginx/*error.log}"
: "${VPSH_ENABLE_RECIDIVE:=true}"
: "${VPSH_LOGROTATE_ROTATE:=14}"

fail2ban::detect_ssh_port() {
  if [[ "$VPSH_SSH_PORT" != "auto" ]]; then
    printf '%s\n' "$VPSH_SSH_PORT"
    return 0
  fi
  sshd -T 2>/dev/null | awk '/^port / {print $2; exit}' || printf 'ssh\n'
}

fail2ban::multiline_logpaths() {
  local paths="$1"
  local first=true
  for p in $paths; do
    if [[ "$first" == true ]]; then
      printf '%s' "$p"
      first=false
    else
      printf '\n            %s' "$p"
    fi
  done
}

fail2ban::write_nginx_scanner_filter() {
  mkdir -p /etc/fail2ban/filter.d
  cat > "$F2B_NGINX_SCANNER_FILTER" <<'CONF'
[Definition]
failregex = ^<HOST> - .* "(GET|POST|HEAD) /(\.env|\.git|wp-login\.php|xmlrpc\.php|phpmyadmin|pma|adminer|boaform|HNAP1|actuator|manager/html|solr/admin|owa/auth|autodiscover|\.ssh|id_rsa|passwd|shell\.php|cmd\.php|eval-stdin\.php|debug/default/view|telescope/requests).*" (400|401|403|404|405|444) .*$
ignoreregex = ^<HOST> - .* "(GET|POST|HEAD) /(sbscr|api|assets|favicon|robots|apple-touch-icon|manifest|socket\.io|websocket|grpc|PubSubService|api/video/stream|health|status).*" .*$
CONF
}

fail2ban::write_configs() {
  mkdir -p /etc/fail2ban "$F2B_JAIL_DIR" /etc/vps-hardening
  [[ -f "$F2B_LOCAL" ]] && fs::backup_file "$F2B_LOCAL"
  [[ -f "$F2B_MANAGED_JAIL" ]] && fs::backup_file "$F2B_MANAGED_JAIL"

  cat > "$F2B_LOCAL" <<'CONF'
[Definition]
loglevel = INFO
logtarget = /var/log/fail2ban.log
socket = /var/run/fail2ban/fail2ban.sock
pidfile = /var/run/fail2ban/fail2ban.pid
CONF

  local ssh_port access_paths error_paths
  ssh_port="$(fail2ban::detect_ssh_port)"
  access_paths="$(fail2ban::multiline_logpaths "$VPSH_NGINX_ACCESS_LOGS")"
  error_paths="$(fail2ban::multiline_logpaths "$VPSH_NGINX_ERROR_LOGS")"

  cat > "$F2B_MANAGED_JAIL" <<CONF
# Managed by vps-hardening-toolkit. Edit /etc/vps-hardening/vps-hardening.env, then run: vps-hardening fail2ban
[DEFAULT]
ignoreip = $VPSH_IGNORE_IPS
usedns = $VPSH_USEDNS
bantime = $VPSH_DEFAULT_BANTIME
bantime.increment = $VPSH_BANTIME_INCREMENT
bantime.factor = $VPSH_BANTIME_FACTOR
bantime.maxtime = $VPSH_BANTIME_MAXTIME
findtime = $VPSH_DEFAULT_FINDTIME
maxretry = $VPSH_DEFAULT_MAXRETRY
backend = systemd
banaction = ufw[blocktype=$VPSH_BLOCKTYPE]
banaction_allports = ufw[blocktype=$VPSH_BLOCKTYPE]
action = %(action_)s

[sshd]
enabled = true
port = $ssh_port
filter = sshd[mode=$VPSH_SSH_MODE]
journalmatch = _COMM=sshd
maxretry = $VPSH_SSH_MAXRETRY
findtime = $VPSH_SSH_FINDTIME
bantime = $VPSH_SSH_BANTIME
CONF

  if [[ "$VPSH_ENABLE_NGINX_JAILS" == "true" ]]; then
    fail2ban::write_nginx_scanner_filter
    cat >> "$F2B_MANAGED_JAIL" <<CONF

[vps-nginx-scanner]
enabled = true
port = http,https
filter = vps-hardening-nginx-scanner
backend = auto
logpath = $access_paths
maxretry = 6
findtime = 10m
bantime = 6h

[nginx-botsearch]
enabled = true
port = http,https
backend = auto
logpath = $error_paths
maxretry = 5
findtime = 10m
bantime = 6h
CONF
  fi

  if [[ "$VPSH_ENABLE_RECIDIVE" == "true" ]]; then
    cat >> "$F2B_MANAGED_JAIL" <<CONF

[recidive]
enabled = true
backend = auto
logpath = /var/log/fail2ban.log
banaction = ufw[blocktype=$VPSH_BLOCKTYPE]
findtime = 1d
bantime = 7d
maxretry = 3
CONF
  fi

  chmod 644 "$F2B_LOCAL" "$F2B_MANAGED_JAIL"
  log::ok "Fail2Ban managed config written: $F2B_MANAGED_JAIL"
}

fail2ban::configure_logrotate() {
  cat > "$F2B_LOGROTATE" <<CONF
/var/log/fail2ban.log {
    su root adm
    daily
    rotate $VPSH_LOGROTATE_ROTATE
    compress
    delaycompress
    missingok
    notifempty
    create 0640 root adm
    postrotate
        /usr/bin/fail2ban-client flushlogs >/dev/null 2>&1 || true
    endscript
}
CONF
  chmod 644 "$F2B_LOGROTATE"
  log::ok "Configured logrotate: $F2B_LOGROTATE"
}

fail2ban::configure() {
  require_root
  pkg::install_if_missing fail2ban
  pkg::install_if_missing ufw
  pkg::install_if_missing python3-systemd
  pkg::install_if_missing logrotate
  fail2ban::write_configs
  fail2ban::configure_logrotate
  fail2ban-client -t
  systemctl enable fail2ban
  svc::restart_and_check fail2ban
  fail2ban-client status || true
}

fail2ban::clean_reject() {
  require_root
  local pass nums
  pass=1
  while true; do
    nums="$(ufw status numbered | sed -nE 's/^\[[[:space:]]*([0-9]+)\][[:space:]]+.*REJECT[[:space:]]+IN.*/\1/p' | sort -rn || true)"
    [[ -z "$nums" ]] && break
    echo "$nums" | while read -r n; do
      [[ -n "$n" ]] || continue
      yes | ufw delete "$n" || true
    done
    pass=$((pass + 1))
    [[ "$pass" -gt 5 ]] && break
  done
  ufw status numbered || true
}

fail2ban::clear_db() {
  require_root
  systemctl stop fail2ban || true
  if [[ -f /var/lib/fail2ban/fail2ban.sqlite3 ]]; then
    cp -a /var/lib/fail2ban/fail2ban.sqlite3 "/root/fail2ban.sqlite3.bak_$(date +%F_%H-%M-%S)"
    rm -f /var/lib/fail2ban/fail2ban.sqlite3
  fi
  systemctl start fail2ban
  sleep 2
  fail2ban-client status || true
}

fail2ban::status() {
  systemctl is-active fail2ban >/dev/null 2>&1 && log::ok "fail2ban is active." || log::warn "fail2ban is not active."
  fail2ban-client status || true
  for jail in sshd vps-nginx-scanner nginx-botsearch recidive; do
    fail2ban-client status "$jail" 2>/dev/null || true
  done
  ufw status || true
}
