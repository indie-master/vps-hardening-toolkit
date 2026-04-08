#!/usr/bin/env bash
set -euo pipefail

if [[ -n "${VPS_HARDENING_COMMON_SH:-}" ]]; then
  return 0
fi
VPS_HARDENING_COMMON_SH=1

readonly PROJECT_NAME="vps-hardening-toolkit"
readonly PROJECT_CMD="vps-hardening"
readonly PROJECT_VERSION="1.0.0"
readonly LOG_FILE="/var/log/vps-hardening.log"
readonly BACKUP_DIR="/var/backups/vps-hardening"

readonly SUPPORTED_UBUNTU=("20.04" "22.04" "24.04")

_color() {
  local code="$1"
  local text="$2"
  if [[ -t 1 ]]; then
    printf "\033[%sm%s\033[0m\n" "$code" "$text"
  else
    printf "%s\n" "$text"
  fi
}

log::timestamp() {
  date '+%Y-%m-%d %H:%M:%S'
}

log::write() {
  local level="$1"
  local message="$2"
  mkdir -p "$(dirname "$LOG_FILE")"
  printf "%s [%s] %s\n" "$(log::timestamp)" "$level" "$message" >> "$LOG_FILE"
}

log::info() { log::write "INFO" "$1"; _color "36" "[INFO] $1"; }
log::warn() { log::write "WARN" "$1"; _color "33" "[WARN] $1"; }
log::error() { log::write "ERROR" "$1"; _color "31" "[ERROR] $1"; }
log::ok() { log::write "OK" "$1"; _color "32" "[OK] $1"; }

require_root() {
  if [[ "${EUID}" -ne 0 ]]; then
    log::error "Run as root (sudo)."
    exit 1
  fi
}

os::ensure_supported() {
  if [[ ! -f /etc/os-release ]]; then
    log::error "Unable to detect OS (/etc/os-release missing)."
    exit 1
  fi

  # shellcheck disable=SC1091
  source /etc/os-release
  if [[ "${ID:-}" != "ubuntu" ]]; then
    log::error "Unsupported OS: ${PRETTY_NAME:-unknown}. Ubuntu 20.04/22.04/24.04 required."
    exit 1
  fi

  local version_ok=false
  for ver in "${SUPPORTED_UBUNTU[@]}"; do
    if [[ "${VERSION_ID:-}" == "$ver" ]]; then
      version_ok=true
      break
    fi
  done

  if [[ "$version_ok" != true ]]; then
    log::error "Unsupported Ubuntu version: ${VERSION_ID:-unknown}. Supported: ${SUPPORTED_UBUNTU[*]}"
    exit 1
  fi

  log::ok "Detected supported system: ${PRETTY_NAME}."
}

prompt::yes_no() {
  local question="$1"
  local default="${2:-no}"
  local answer
  while true; do
    if [[ "$default" == "yes" ]]; then
      read -r -p "$question [Y/n]: " answer
      answer="${answer:-y}"
    else
      read -r -p "$question [y/N]: " answer
      answer="${answer:-n}"
    fi

    case "${answer,,}" in
      y|yes) return 0 ;;
      n|no) return 1 ;;
      *) log::warn "Please answer yes or no." ;;
    esac
  done
}

fs::backup_file() {
  local file_path="$1"
  if [[ ! -f "$file_path" ]]; then
    return 0
  fi

  mkdir -p "$BACKUP_DIR"
  local ts
  ts="$(date '+%Y%m%d-%H%M%S')"
  local backup_name
  backup_name="$(basename "$file_path").${ts}.bak"
  cp -a "$file_path" "$BACKUP_DIR/$backup_name"
  log::ok "Backup created: $BACKUP_DIR/$backup_name"
}

fs::ensure_file() {
  local file_path="$1"
  local owner="$2"
  local mode="$3"

  touch "$file_path"
  chown "$owner" "$file_path"
  chmod "$mode" "$file_path"
}

pkg::install_if_missing() {
  local package="$1"
  if dpkg -s "$package" >/dev/null 2>&1; then
    log::ok "Package already installed: $package"
  else
    log::info "Installing package: $package"
    DEBIAN_FRONTEND=noninteractive apt-get update -y
    DEBIAN_FRONTEND=noninteractive apt-get install -y "$package"
    log::ok "Package installed: $package"
  fi
}

svc::restart_and_check() {
  local service="$1"
  systemctl restart "$service"
  if systemctl is-active --quiet "$service"; then
    log::ok "Service active: $service"
  else
    log::error "Service failed to start: $service"
    systemctl status "$service" --no-pager || true
    return 1
  fi
}

net::is_valid_ipv4() {
  local ip="$1"
  [[ "$ip" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] || return 1
  IFS='.' read -r o1 o2 o3 o4 <<< "$ip"
  for octet in "$o1" "$o2" "$o3" "$o4"; do
    ((octet >= 0 && octet <= 255)) || return 1
  done
}

net::is_valid_cidr4() {
  local cidr="$1"
  [[ "$cidr" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}/([0-9]|[1-2][0-9]|3[0-2])$ ]] || return 1
  net::is_valid_ipv4 "${cidr%/*}"
}

net::is_valid_ipv6_or_cidr() {
  local value="$1"
  if [[ "$value" =~ : ]]; then
    if [[ "$value" == */* ]]; then
      [[ "$value" =~ ^[0-9a-fA-F:]+/[0-9]{1,3}$ ]]
    else
      [[ "$value" =~ ^[0-9a-fA-F:]+$ ]]
    fi
  else
    return 1
  fi
}

text::trim() {
  local var="$*"
  var="${var#"${var%%[![:space:]]*}"}"
  var="${var%"${var##*[![:space:]]}"}"
  printf '%s' "$var"
}
