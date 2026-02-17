#!/usr/bin/env bash
set -euo pipefail

# ── Pi-WOL Installer ──────────────────────────────────────────
# Installs the Wake-on-LAN app as a systemd service on port 9090
# running as www-data.
#
# Usage:  sudo bash install.sh
# ───────────────────────────────────────────────────────────────

APP_NAME="pi-wol"
INSTALL_DIR="/opt/${APP_NAME}"
SERVICE_FILE="/etc/systemd/system/${APP_NAME}.service"
VENV_DIR="${INSTALL_DIR}/venv"
APP_USER="www-data"
APP_GROUP="www-data"
APP_PORT=9090

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log()   { echo -e "${GREEN}[+]${NC} $*"; }
warn()  { echo -e "${YELLOW}[!]${NC} $*"; }
err()   { echo -e "${RED}[✗]${NC} $*" >&2; }

# ── Pre-flight checks ─────────────────────────────────────────

if [[ $EUID -ne 0 ]]; then
    err "This script must be run as root (sudo)."
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ ! -f "${SCRIPT_DIR}/wol.py" ]]; then
    err "wol.py not found in ${SCRIPT_DIR}. Run this script from the project directory."
    exit 1
fi

if [[ ! -d "${SCRIPT_DIR}/dist" ]]; then
    err "dist/ folder not found. Run 'npm run build' first."
    exit 1
fi

# ── Install system dependencies ────────────────────────────────

log "Installing system dependencies..."
apt-get update -qq
apt-get install -y -qq python3 python3-venv python3-pip > /dev/null

# Ensure www-data user exists (it should on Debian/Ubuntu)
if ! id -u "${APP_USER}" > /dev/null 2>&1; then
    warn "User ${APP_USER} does not exist, creating..."
    useradd --system --no-create-home --shell /usr/sbin/nologin "${APP_USER}"
fi

# ── Create install directory ───────────────────────────────────

log "Setting up ${INSTALL_DIR}..."

mkdir -p "${INSTALL_DIR}"

# Copy application files
cp "${SCRIPT_DIR}/wol.py" "${INSTALL_DIR}/"
cp "${SCRIPT_DIR}/requirements.txt" "${INSTALL_DIR}/"
cp -r "${SCRIPT_DIR}/dist" "${INSTALL_DIR}/"

# Copy existing devices.json if present, or create empty one
if [[ -f "${SCRIPT_DIR}/devices.json" ]]; then
    # Don't overwrite existing devices on reinstall
    if [[ ! -f "${INSTALL_DIR}/devices.json" ]]; then
        cp "${SCRIPT_DIR}/devices.json" "${INSTALL_DIR}/"
    else
        warn "Keeping existing devices.json in ${INSTALL_DIR}"
    fi
else
    if [[ ! -f "${INSTALL_DIR}/devices.json" ]]; then
        echo "[]" > "${INSTALL_DIR}/devices.json"
    fi
fi

# ── Python virtual environment ─────────────────────────────────

log "Creating Python virtual environment..."
python3 -m venv "${VENV_DIR}"

log "Installing Python dependencies..."
"${VENV_DIR}/bin/pip" install --upgrade pip --quiet
"${VENV_DIR}/bin/pip" install -r "${INSTALL_DIR}/requirements.txt" --quiet

# ── Set ownership & permissions ────────────────────────────────

log "Setting permissions..."
chown -R "${APP_USER}:${APP_GROUP}" "${INSTALL_DIR}"
chmod 755 "${INSTALL_DIR}"
chmod 664 "${INSTALL_DIR}/devices.json"

# Allow www-data to send raw packets (needed for WOL magic packets)
# and to run ping
PYTHON_BIN="${VENV_DIR}/bin/python3"
if command -v setcap > /dev/null 2>&1; then
    setcap 'cap_net_raw+ep' "${PYTHON_BIN}" 2>/dev/null || true
fi

# ── Create systemd service ─────────────────────────────────────

log "Creating systemd service..."

cat > "${SERVICE_FILE}" <<EOF
[Unit]
Description=Pi Wake-on-LAN Service
After=network.target

[Service]
Type=simple
User=${APP_USER}
Group=${APP_GROUP}
WorkingDirectory=${INSTALL_DIR}
Environment="PATH=${VENV_DIR}/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin"
ExecStart=${VENV_DIR}/bin/gunicorn \\
    --bind 0.0.0.0:${APP_PORT} \\
    --workers 2 \\
    --access-logfile - \\
    --error-logfile - \\
    wol:app
Restart=on-failure
RestartSec=5
StandardOutput=journal
StandardError=journal

# Security hardening
NoNewPrivileges=true
ProtectSystem=strict
ReadWritePaths=${INSTALL_DIR}
ProtectHome=true
PrivateTmp=true

[Install]
WantedBy=multi-user.target
EOF

# ── Enable and start ───────────────────────────────────────────

log "Enabling and starting ${APP_NAME} service..."
systemctl daemon-reload
systemctl enable "${APP_NAME}"
systemctl restart "${APP_NAME}"

# Wait a moment then check status
sleep 2

if systemctl is-active --quiet "${APP_NAME}"; then
    echo ""
    log "════════════════════════════════════════════════════"
    log "  ${APP_NAME} installed successfully!"
    log "  URL:     http://$(hostname -I | awk '{print $1}'):${APP_PORT}"
    log "  Status:  sudo systemctl status ${APP_NAME}"
    log "  Logs:    sudo journalctl -u ${APP_NAME} -f"
    log "  Stop:    sudo systemctl stop ${APP_NAME}"
    log "════════════════════════════════════════════════════"
    echo ""
else
    err "Service failed to start. Check logs with:"
    err "  sudo journalctl -u ${APP_NAME} -e"
    exit 1
fi
