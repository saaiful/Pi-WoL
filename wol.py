from flask import Flask, jsonify, request, send_from_directory
from flask_cors import CORS
import json
import re
import socket
import struct
import subprocess
import platform
import os

app = Flask(__name__, static_folder='dist', static_url_path='')
CORS(app)  # still useful during dev if you test frontend separately

DEVICES_FILE = 'devices.json'

MAC_RE = re.compile(r'^([0-9A-F]{2}:){5}[0-9A-F]{2}$')
IP_RE  = re.compile(r'^(\d{1,3}\.){3}\d{1,3}$')
NAME_MAX_LEN = 64


def validate_mac(mac):
    """Normalize and validate a MAC address. Returns (clean_mac, error)."""
    if not mac or not isinstance(mac, str):
        return None, 'MAC address is required'
    mac = mac.upper().strip().replace('-', ':')
    if not MAC_RE.match(mac):
        return None, 'Invalid MAC address format (use AA:BB:CC:DD:EE:FF)'
    return mac, None


def validate_ip(ip):
    """Validate an optional IPv4 address. Returns (clean_ip, error)."""
    if not ip:
        return '', None
    if not isinstance(ip, str):
        return None, 'IP address must be a string'
    ip = ip.strip()
    if not ip:
        return '', None
    if not IP_RE.match(ip):
        return None, 'Invalid IP address format (use 192.168.1.100)'
    octets = ip.split('.')
    if any(int(o) > 255 for o in octets):
        return None, 'Invalid IP address (octet out of range 0-255)'
    return ip, None


def validate_name(name, default='Unnamed'):
    """Sanitize device name. Returns cleaned name."""
    if not name or not isinstance(name, str):
        return default
    name = name.strip()
    if len(name) > NAME_MAX_LEN:
        name = name[:NAME_MAX_LEN]
    return name or default


def load_devices():
    if os.path.exists(DEVICES_FILE):
        with open(DEVICES_FILE, 'r') as f:
            return json.load(f)
    return []

def save_devices(devices):
    with open(DEVICES_FILE, 'w') as f:
        json.dump(devices, f, indent=2)

def send_wol(mac):
    try:
        # Normalize and clean MAC
        mac_clean = mac.replace(':', '').replace('-', '').upper()
        mac_bytes = bytes.fromhex(mac_clean)
        if len(mac_bytes) != 6:
            raise ValueError("Invalid MAC address length")
        magic = b'\xFF' * 6 + mac_bytes * 16
        with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as s:
            s.setsockopt(socket.SOL_SOCKET, socket.SO_BROADCAST, 1)
            s.sendto(magic, ('255.255.255.255', 9))
        return True, None
    except Exception as e:
        return False, str(e)

def resolve_ip_from_mac(mac):
    """Look up the ARP table for an IP matching the given MAC address."""
    mac_clean = mac.upper().replace('-', ':').strip()
    try:
        output = subprocess.check_output(['arp', '-a'], text=True, stderr=subprocess.DEVNULL)
        for line in output.splitlines():
            # Windows format:  192.168.1.5   aa-bb-cc-dd-ee-ff   dynamic
            # Linux format:    host (192.168.1.5) at aa:bb:cc:dd:ee:ff ...
            parts = line.split()
            for i, part in enumerate(parts):
                normalized = part.upper().replace('-', ':')
                if normalized == mac_clean:
                    # Find the IP in this line
                    for p in parts:
                        p_stripped = p.strip('()')
                        if re.match(r'^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$', p_stripped):
                            return p_stripped
    except Exception:
        pass
    return None

def ping(ip):
    if not ip:
        return False
    sys = platform.system().lower()
    count = '-n' if sys == 'windows' else '-c'
    timeout = '-w' if sys == 'windows' else '-W'
    timeout_val = '1000' if sys == 'windows' else '1'
    cmd = ['ping', count, '1', timeout, timeout_val, ip]
    try:
        return subprocess.call(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL) == 0
    except:
        return False

# ── API Endpoints ───────────────────────────────────────────────

@app.route('/api/devices', methods=['GET'])
def get_devices():
    devices = load_devices()
    for d in devices:
        d['online'] = ping(d.get('last_ip'))
    return jsonify(devices)

@app.route('/api/devices', methods=['POST'])
def add_device():
    data = request.get_json(silent=True)
    if not data or not isinstance(data, dict):
        return jsonify({"error": "Invalid or missing JSON body"}), 400

    mac, mac_err = validate_mac(data.get('mac', ''))
    if mac_err:
        return jsonify({"error": mac_err}), 400

    last_ip, ip_err = validate_ip(data.get('last_ip', ''))
    if ip_err:
        return jsonify({"error": ip_err}), 400

    name = validate_name(data.get('name', ''), default='Device')

    # Reject duplicates
    devices = load_devices()
    if any(d['mac'] == mac for d in devices):
        return jsonify({"error": f"Device with MAC {mac} already exists"}), 409

    # Auto-resolve IP from ARP table if not provided
    if not last_ip:
        resolved = resolve_ip_from_mac(mac)
        if resolved:
            last_ip = resolved

    devices.append({"name": name, "mac": mac, "last_ip": last_ip})
    save_devices(devices)
    return jsonify({"message": "Device added", "mac": mac, "last_ip": last_ip}), 201

@app.route('/api/devices/<mac>', methods=['PUT'])
def update_device(mac):
    mac, mac_err = validate_mac(mac)
    if mac_err:
        return jsonify({"error": mac_err}), 400

    data = request.get_json(silent=True)
    if not data or not isinstance(data, dict):
        return jsonify({"error": "Invalid or missing JSON body"}), 400

    devices = load_devices()
    for d in devices:
        if d['mac'] == mac:
            # Validate optional new name
            if 'name' in data:
                d['name'] = validate_name(data['name'], default=d['name'])

            # Validate optional new MAC
            if 'mac' in data and data['mac']:
                new_mac, new_mac_err = validate_mac(data['mac'])
                if new_mac_err:
                    return jsonify({"error": new_mac_err}), 400
                # Check for duplicate if MAC is changing
                if new_mac != mac and any(other['mac'] == new_mac for other in devices):
                    return jsonify({"error": f"Device with MAC {new_mac} already exists"}), 409
                d['mac'] = new_mac

            # Validate optional new IP
            if 'last_ip' in data:
                new_ip, ip_err = validate_ip(data['last_ip'])
                if ip_err:
                    return jsonify({"error": ip_err}), 400
                d['last_ip'] = new_ip

            save_devices(devices)
            return jsonify({"message": "Device updated", "device": d})
    return jsonify({"error": "Device not found"}), 404

@app.route('/api/devices/<mac>', methods=['DELETE'])
def delete_device(mac):
    mac, mac_err = validate_mac(mac)
    if mac_err:
        return jsonify({"error": mac_err}), 400
    devices = load_devices()
    new_devices = [d for d in devices if d['mac'] != mac]
    if len(new_devices) == len(devices):
        return jsonify({"error": "Device not found"}), 404
    save_devices(new_devices)
    return jsonify({"message": f"Device {mac} deleted"})

@app.route('/api/wake/<mac>', methods=['POST'])
def wake(mac):
    mac, mac_err = validate_mac(mac)
    if mac_err:
        return jsonify({"error": mac_err}), 400
    success, error = send_wol(mac)
    if success:
        return jsonify({"message": f"WOL packet sent to {mac}"})
    return jsonify({"error": error or "Failed to send WOL packet"}), 500

@app.route('/api/resolve/<mac>', methods=['GET'])
def resolve_mac(mac):
    mac, mac_err = validate_mac(mac)
    if mac_err:
        return jsonify({"error": mac_err}), 400
    ip = resolve_ip_from_mac(mac)
    if ip:
        return jsonify({"ip": ip, "mac": mac})
    return jsonify({"error": "Could not resolve IP for this MAC", "mac": mac}), 404

# ── Serve Vue SPA ───────────────────────────────────────────────

@app.route('/', defaults={'path': ''})
@app.route('/<path:path>')
def serve_spa(path):
    if path and os.path.exists(os.path.join(app.static_folder, path)):
        return send_from_directory(app.static_folder, path)
    # For all other paths → serve index.html (Vue router / SPA behavior)
    return send_from_directory(app.static_folder, 'index.html')

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000, debug=True)