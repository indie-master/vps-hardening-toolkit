#!/usr/bin/env bash
set -euo pipefail

if [[ -n "${VPS_HARDENING_NGINX_SH:-}" ]]; then return 0; fi
VPS_HARDENING_NGINX_SH=1
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

readonly NGINX_KEYRING="/usr/share/keyrings/nginx-archive-keyring.gpg"
readonly NGINX_LIST="/etc/apt/sources.list.d/nginx.list"
readonly NGINX_PIN="/etc/apt/preferences.d/99nginx"
readonly NGINX_KEY_FINGERPRINT="573BFD6B3D8FBC641079A6ABABF5BD827BD9BF62"

nginx::ubuntu_version() { source /etc/os-release; printf '%s\n' "${VERSION_ID:-unknown}"; }
nginx::codename() { source /etc/os-release; printf '%s\n' "${VERSION_CODENAME:-}"; }

nginx::install_prerequisites() {
  DEBIAN_FRONTEND=noninteractive apt-get update -y
  DEBIAN_FRONTEND=noninteractive apt-get install -y curl gnupg2 ca-certificates lsb-release ubuntu-keyring
}

nginx::configure_official_repo() {
  local codename="$1" tmp_key fingerprint
  tmp_key="$(mktemp)"
  curl -fsSL https://nginx.org/keys/nginx_signing.key -o "$tmp_key"
  fingerprint="$(gpg --show-keys --with-colons "$tmp_key" 2>/dev/null | awk -F: '$1=="fpr" && !found {print $10; found=1}')"
  if [[ "$fingerprint" != "$NGINX_KEY_FINGERPRINT" ]]; then
    rm -f "$tmp_key"
    log::error "nginx signing key fingerprint mismatch: $fingerprint"
    return 1
  fi
  gpg --dearmor --yes --output "$NGINX_KEYRING" "$tmp_key"
  rm -f "$tmp_key"
  chmod 644 "$NGINX_KEYRING"
  printf 'deb [signed-by=%s] https://nginx.org/packages/ubuntu %s nginx\n' "$NGINX_KEYRING" "$codename" > "$NGINX_LIST"
  cat > "$NGINX_PIN" <<'EOF'
Package: *
Pin: origin nginx.org
Pin: release o=nginx
Pin-Priority: 900
EOF
  log::ok "Configured official nginx.org stable repository for Ubuntu $codename."
}

nginx::configure_repo() {
  local version codename
  version="$(nginx::ubuntu_version)"; codename="$(nginx::codename)"
  case "$version" in
    22.04|24.04) nginx::configure_official_repo "$codename" ;;
    20.04)
      rm -f "$NGINX_LIST" "$NGINX_PIN"
      log::warn "Ubuntu 20.04 is no longer supported by the current nginx.org repository; using Ubuntu's maintained package instead."
      ;;
    *)
      rm -f "$NGINX_LIST" "$NGINX_PIN"
      log::warn "No nginx.org repository policy defined for Ubuntu $version; using Ubuntu repository."
      ;;
  esac
}

nginx::runtime_user() {
  if getent passwd nginx >/dev/null 2>&1; then printf 'nginx\n'; else printf 'www-data\n'; fi
}

nginx::write_base_config() {
  local runtime_user
  runtime_user="$(nginx::runtime_user)"
  fs::backup_file /etc/nginx/nginx.conf
  mkdir -p /etc/nginx/conf.d
  cat > /etc/nginx/nginx.conf <<EOF
user $runtime_user;
worker_processes auto;
error_log /var/log/nginx/error.log notice;
pid /run/nginx.pid;

events { worker_connections 1024; }

http {
    include /etc/nginx/mime.types;
    default_type application/octet-stream;
    log_format main '\$remote_addr - \$remote_user [\$time_local] "\$request" '
                    '\$status \$body_bytes_sent "\$http_referer" '
                    '"\$http_user_agent" "\$http_x_forwarded_for"';
    access_log /var/log/nginx/access.log main;
    server_tokens off;
    sendfile on;
    tcp_nopush on;
    keepalive_timeout 65;
    client_max_body_size 20m;
    gzip on;
    gzip_vary on;
    gzip_proxied any;
    gzip_comp_level 5;
    gzip_min_length 1024;
    gzip_types text/plain text/css application/json application/javascript application/xml image/svg+xml;
    include /etc/nginx/conf.d/*.conf;
}
EOF
  rm -f /etc/nginx/conf.d/default.conf /etc/nginx/sites-enabled/default
  cat > /etc/nginx/conf.d/00-default.conf <<'EOF'
server {
    listen 80 default_server;
    listen [::]:80 default_server;
    server_name _;
    access_log off;
    return 404;
}
EOF
  log::ok "Base nginx configuration written (worker user: $runtime_user)."
}

nginx::configure() {
  require_root
  os::ensure_supported
  nginx::install_prerequisites
  nginx::configure_repo
  DEBIAN_FRONTEND=noninteractive apt-get update -y
  DEBIAN_FRONTEND=noninteractive apt-get install -y nginx
  nginx::write_base_config
  nginx -t || { log::error "nginx configuration test failed."; return 1; }
  systemctl enable nginx >/dev/null
  svc::restart_and_check nginx
  log::ok "nginx installed and configured: $(nginx -v 2>&1)"
}

nginx::status() {
  if ! command -v nginx >/dev/null 2>&1; then log::warn "nginx is not installed."; return 0; fi
  log::info "$(nginx -v 2>&1)"
  nginx -t || true
  systemctl is-active --quiet nginx && log::ok "Service active: nginx" || log::warn "Service inactive: nginx"
}
