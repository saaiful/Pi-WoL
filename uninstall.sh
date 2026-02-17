#!/usr/bin/env bash
set -euo pipefail

# ── Pi-WOL Uninstaller ────────────────────────────────────────
# Removes the systemd service and optionally the install directory.
#
# Usage:  sudo bash uninstall.sh
# ───────────────────────────────────────────────────────────────

APP_NAME="pi-wol"
INSTALL_DIR="/opt/${APP_NAME}"
SERVICE_FILE="/etc/systemd/system/${APP_NAME}.service"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log()   { echo -e "${GREEN}[+]${NC} $*"; }
warn()  { echo -e "${YELLOW}[!]${NC} $*"; }
err()   { echo -e "${RED}[✗]${NC} $*" >&2; }

if [[ $EUID -ne 0 ]]; then
    err "This script must be run as root (sudo)."
    exit 1
fi

# ── Stop and remove service ────────────────────────────────────

if systemctl is-active --quiet "${APP_NAME}" 2>/dev/null; then
    log "Stopping ${APP_NAME} service..."
    systemctl stop "${APP_NAME}"
fi

if systemctl is-enabled --quiet "${APP_NAME}" 2>/dev/null; then
    log "Disabling ${APP_NAME} service..."
    systemctl disable "${APP_NAME}"
fi

if [[ -f "${SERVICE_FILE}" ]]; then
    log "Removing service file..."
    rm -f "${SERVICE_FILE}"
    systemctl daemon-reload
fi

# ── Remove install directory ───────────────────────────────────

if [[ -d "${INSTALL_DIR}" ]]; then
    read -rp "Remove ${INSTALL_DIR} and all data? [y/N] " confirm
    if [[ "${confirm}" =~ ^[Yy]$ ]]; then
        log "Removing ${INSTALL_DIR}..."
        rm -rf "${INSTALL_DIR}"
    else
        warn "Kept ${INSTALL_DIR}"
    fi
fi

echo ""
log "${APP_NAME} has been uninstalled."
