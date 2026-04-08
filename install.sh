#!/usr/bin/env bash
set -euo pipefail

REPO_URL="https://github.com/indie-master/vps-hardening-toolkit.git"
INSTALL_DIR="/opt/vps-hardening-toolkit"
BIN_LINK="/usr/local/bin/vps-hardening"

if [[ "${EUID}" -ne 0 ]]; then
  echo "[ERROR] Run install.sh as root (sudo)."
  exit 1
fi

if ! command -v git >/dev/null 2>&1; then
  apt-get update -y
  apt-get install -y git
fi

if [[ -d "$INSTALL_DIR/.git" ]]; then
  echo "[INFO] Existing installation found. Updating..."
  git -C "$INSTALL_DIR" pull --ff-only
else
  rm -rf "$INSTALL_DIR"
  git clone "$REPO_URL" "$INSTALL_DIR"
fi

chmod +x "$INSTALL_DIR/bin/vps-hardening"
chmod +x "$INSTALL_DIR/uninstall.sh"
ln -sf "$INSTALL_DIR/bin/vps-hardening" "$BIN_LINK"

echo "[OK] Installed. Run:"
echo "  vps-hardening doctor"
echo "  vps-hardening all"
