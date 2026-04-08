#!/usr/bin/env bash
set -euo pipefail

INSTALL_DIR="/opt/vps-hardening-toolkit"
BIN_LINK="/usr/local/bin/vps-hardening"

if [[ "${EUID}" -ne 0 ]]; then
  echo "[ERROR] Run uninstall.sh as root (sudo)."
  exit 1
fi

rm -f "$BIN_LINK"
rm -rf "$INSTALL_DIR"

echo "[OK] vps-hardening-toolkit removed."
