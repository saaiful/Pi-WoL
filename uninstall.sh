#!/usr/bin/env bash
set -euo pipefail

# ── Pi-WOL Uninstaller ────────────────────────────────────────
# Fully reverses what install.sh did:
#   1. Stops and disables the systemd service
#   2. Removes the service unit file
#   3. Drops the cap_net_raw capability from the venv python binary
#   4. Optionally backs up devices.json
#   5. Optionally removes the install directory (/opt/pi-wol)
#
# Usage:  sudo bash uninstall.sh
# ───────────────────────────────────────────────────────────────

APP_NAME="pi-wol"
INSTALL_DIR="/opt/${APP_NAME}"
SERVICE_FILE="/etc/systemd/system/${APP_NAME}.service"
VENV_PYTHON="${INSTALL_DIR}/venv/bin/python3"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

log()   { echo -e "${GREEN}[+]${NC} $*"; }
warn()  { echo -e "${YELLOW}[!]${NC} $*"; }
err()   { echo -e "${RED}[✗]${NC} $*" >&2; }
info()  { echo -e "${CYAN}[i]${NC} $*"; }

# ── Pre-flight ────────────────────────────────────────────────

if [[ $EUID -ne 0 ]]; then
    err "This script must be run as root (sudo)."
    exit 1
fi

echo ""
warn "This will remove the ${APP_NAME} service and its installation."
echo ""

# ── 1. Stop & disable systemd service ─────────────────────────

if systemctl is-active --quiet "${APP_NAME}" 2>/dev/null; then
    log "Stopping ${APP_NAME} service..."
    systemctl stop "${APP_NAME}"
else
    info "Service is not running."
fi

if systemctl is-enabled --quiet "${APP_NAME}" 2>/dev/null; then
    log "Disabling ${APP_NAME} service..."
    systemctl disable "${APP_NAME}"
else
    info "Service is not enabled."
fi

# ── 2. Remove service unit file ────────────────────────────────

if [[ -f "${SERVICE_FILE}" ]]; then
    log "Removing service unit file: ${SERVICE_FILE}"
    rm -f "${SERVICE_FILE}"
    systemctl daemon-reload
    systemctl reset-failed 2>/dev/null || true
else
    info "Service file not found — skipping."
fi

# ── 3. Drop cap_net_raw capability ────────────────────────────

if [[ -f "${VENV_PYTHON}" ]] && command -v setcap > /dev/null 2>&1; then
    log "Removing cap_net_raw capability from Python binary..."
    setcap -r "${VENV_PYTHON}" 2>/dev/null || true
fi

# ── 4. Backup devices.json (optional) ─────────────────────────

DEVICES_FILE="${INSTALL_DIR}/devices.json"
if [[ -f "${DEVICES_FILE}" ]]; then
    echo ""
    read -rp "Back up devices.json to your home directory before deleting? [Y/n] " backup_confirm
    if [[ ! "${backup_confirm}" =~ ^[Nn]$ ]]; then
        BACKUP_DEST="${HOME}/pi-wol-devices-backup-$(date +%Y%m%d%H%M%S).json"
        cp "${DEVICES_FILE}" "${BACKUP_DEST}"
        log "Devices saved to: ${BACKUP_DEST}"
    else
        warn "Skipping devices.json backup."
    fi
fi

# ── 5. Remove install directory ────────────────────────────────

echo ""
if [[ -d "${INSTALL_DIR}" ]]; then
    read -rp "Remove ${INSTALL_DIR} and all its contents? [y/N] " dir_confirm
    if [[ "${dir_confirm}" =~ ^[Yy]$ ]]; then
        log "Removing ${INSTALL_DIR}..."
        rm -rf "${INSTALL_DIR}"
    else
        warn "Kept ${INSTALL_DIR} — you can delete it manually later."
    fi
else
    info "${INSTALL_DIR} not found — nothing to remove."
fi

# ── Done ──────────────────────────────────────────────────────

echo ""
log "════════════════════════════════════════════════════"
log "  ${APP_NAME} has been uninstalled."
log "  To reinstall, run:  sudo bash install.sh"
log "════════════════════════════════════════════════════"
echo ""
