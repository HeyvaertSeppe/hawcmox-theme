#!/bin/sh

# HAWCMOX Uninstaller - Revert to Stock Proxmox UI

set -eu

printf '%s\n' "============================================================"
printf '%s\n' " HAWCMOX Proxmox UI Uninstaller"
printf '%s\n' "============================================================"

if [ "$(id -u)" -ne 0 ]; then
    printf '%s\n' "ERROR: This script must be run as root."
    exit 1
fi

printf '%s\n' "[1/3] Removing HAWCMOX files and APT hooks..."
rm -rf "/usr/local/share/hawcmox"
rm -f "/usr/local/bin/hawcmox-patch.sh"
rm -f "/etc/apt/apt.conf.d/99hawcmox-theme"
rm -f "/usr/share/pve-manager/css/hawcmox.css"

printf '%s\n' "[2/3] Restoring original Proxmox logo and HTML template..."
# Reinstalling pve-manager is the safest and most reliable way 
# to restore the exact original stock Proxmox files.
export DEBIAN_FRONTEND=noninteractive
apt-get install --reinstall pve-manager -y >/dev/null 2>&1

printf '%s\n' "[3/3] Restarting Proxmox web interface..."
if command -v systemctl >/dev/null 2>&1; then
    systemctl restart pveproxy.service >/dev/null 2>&1 || true
fi

printf '\n'
printf '%s\n' "============================================================"
printf '%s\n' " REVERT COMPLETE"
printf '%s\n' "============================================================"
printf '\n'
printf '%s\n' "The server is now back to stock Proxmox defaults."
printf '%s\n' "IMPORTANT: If you still see the custom theme, IT IS YOUR BROWSER CACHE."
printf '%s\n' "You must clear your cache for this site or open it in an Incognito/Private window."
