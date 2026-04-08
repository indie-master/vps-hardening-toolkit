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
readonly F2B_SSHD_IGNOREIP="37.114.37.137 5.35.103.233 45.134.111.181 31.58.58.208 94.159.110.127 194.226.139.231 194.226.139.231 46.8.68.212 77.236.62.50 62.63.86.29"

fail2ban::ensure_jail_local() {
  if [[ -f "$F2B_JAIL" ]]; then
    return 0
  fi

  if [[ -f /etc/fail2ban/jail.conf ]]; then
    cp -a /etc/fail2ban/jail.conf "$F2B_JAIL"
    log::ok "Created jail.local from jail.conf"
  else
    touch "$F2B_JAIL"
    log::warn "jail.conf not found; created empty jail.local"
  fi
}

fail2ban::upsert_sshd_jail() {
  local tmp_file
  tmp_file="$(mktemp)"
  awk -v ignoreip="$F2B_SSHD_IGNOREIP" '
    BEGIN {
      found_sshd=0
      section_mode=0
      n=8
      order[1]="enabled";   val["enabled"]="true"
      order[2]="port";      val["port"]="ssh"
      order[3]="filter";    val["filter"]="sshd"
      order[4]="logpath";   val["logpath"]="/var/log/auth.log"
      order[5]="maxretry";  val["maxretry"]="3"
      order[6]="bantime";   val["bantime"]="10800"
      order[7]="findtime";  val["findtime"]="600"
      order[8]="ignoreip";  val["ignoreip"]=ignoreip
    }
    function flush_missing(  i,k) {
      if (section_mode != 1) return
      for (i=1; i<=n; i++) {
        k=order[i]
        if (!(k in seen)) {
          print k " = " val[k]
        }
      }
    }
    function trim(s) {
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", s)
      return s
    }
    /^[[:space:]]*\[[^]]+\][[:space:]]*$/ {
      flush_missing()
      header=$0
      lower=tolower(header)
      if (lower ~ /^[[:space:]]*\[sshd\][[:space:]]*$/) {
        if (!found_sshd) {
          found_sshd=1
          section_mode=1
          delete seen
          print "[sshd]"
        } else {
          section_mode=2
        }
        next
      }
      section_mode=0
      print
      next
    }
    {
      if (section_mode == 1) {
        if (match($0, /^[[:space:]]*#?[[:space:]]*([[:alnum:]_]+)[[:space:]]*=/, m)) {
          key=tolower(trim(m[1]))
          if (key in val) {
            if (!(key in seen)) {
              print key " = " val[key]
              seen[key]=1
            }
            next
          }
        }
        print
        next
      }
      if (section_mode == 2) {
        next
      }
      print
    }
    END {
      flush_missing()
      if (!found_sshd) {
        if (NR > 0) print ""
        print "[sshd]"
        for (i=1; i<=n; i++) {
          k=order[i]
          print k " = " val[k]
        }
      }
    }
  ' "$F2B_JAIL" > "$tmp_file"
  cat "$tmp_file" > "$F2B_JAIL"
  rm -f "$tmp_file"
}

fail2ban::write_configs() {
  mkdir -p /etc/fail2ban

  if [[ -f "$F2B_LOCAL" ]]; then fs::backup_file "$F2B_LOCAL"; fi
  fail2ban::ensure_jail_local
  fs::backup_file "$F2B_JAIL"

  cat > "$F2B_LOCAL" <<'CONF'
[Definition]
loglevel = INFO
logtarget = /var/log/fail2ban.log
socket = /var/run/fail2ban/fail2ban.sock
pidfile = /var/run/fail2ban/fail2ban.pid
CONF

  fail2ban::upsert_sshd_jail

  chmod 644 "$F2B_LOCAL" "$F2B_JAIL"
  log::ok "Fail2Ban configs updated without overwriting jail.local."
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
    local last_backup
    last_backup="$(find "$BACKUP_DIR" -maxdepth 1 -type f -name 'jail.local.*.bak' | sort -r | head -n 1 || true)"
    if [[ -n "$last_backup" ]]; then
      cp -a "$last_backup" "$F2B_JAIL"
      log::warn "Restored $F2B_JAIL from backup after failed validation."
    fi
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
