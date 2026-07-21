#!/usr/bin/env bash

# ==============================================================================
# HAWC SERVERS - Unified Proxmox Post-Install & UI Theming Script
# ==============================================================================
# Automatically fixes repositories, updates the system, removes nags, preserves
# high availability, and runs the remote HAWC theme installer.
# ==============================================================================

# --- Ensure execution with Bash, not standard sh ---
if [ -z "${BASH_VERSION:-}" ]; then
  echo -e "\033[01;31mERROR: This script must be run using bash, not sh.\033[m"
  echo -e "Please execute using: \033[33mbash -c \"\$(curl -fsSL <your-url>)\"\033[m"
  exit 1
fi

set -euo pipefail
shopt -s inherit_errexit nullglob

# --- Output Styling ---
RD=$(echo -ne "\033[01;31m")
YW=$(echo -ne "\033[33m")
GN=$(echo -ne "\033[1;92m")
CL=$(echo -ne "\033[m")
BFR="\\r\\033[K"
HOLD="-"
CM="${GN}✓${CL}"
CROSS="${RD}✗${CL}"

msg_info() {
  echo -ne " ${HOLD} ${YW}$1...${CL}"
}

msg_ok() {
  echo -e "${BFR} ${CM} ${GN}$1${CL}"
}

msg_error() {
  echo -e "${BFR} ${CROSS} ${RD}$1${CL}"
}

# --- Live Progress Tracker ---
# This captures standard output line-by-line and updates a single line on the 
# terminal, showing exactly what is happening without breaking the UI.
run_with_live_status() {
  local cmd="$1"
  local prefix="$2"
  
  eval "$cmd" 2>&1 | while IFS= read -r line; do
    # Keep only printable characters to avoid terminal breaking escape sequences
    local clean_line
    clean_line=$(echo "$line" | tr -cd '\40-\176')
    
    # Truncate to 75 characters so it doesn't wrap to the next line
    echo -ne "\r\033[K ${YW}➤ ${prefix}: ${clean_line:0:75}${CL}"
  done
  
  # Clear the live status line when the command finishes
  echo -ne "\r\033[K"
}

header_info() {
  clear
  cat <<"EOF"
    __  _____ _       _______   _________________ _    ____________  _____
   / / / /   | |     / / ___/  / ___/ ____/ __ \ |  / / ____/ __ \/ ___/
  / /_/ / /| | | /| / / /      \__ \/ __/ / /_/ / | / / __/ / /_/ /\__ \
 / __  / ___ | |/ |/ / /___   ___/ / /___/ _, _/| |/ / /___/ _, _/___/ /
/_/ /_/_/  |_|__/|__/\____/  /____/_____/_/ |_| |___/_____/_/ |_|/____/
                                                                      
EOF
  echo -e "\nInitializing HAWC SERVERS Automated Proxmox Deployment...\n"
}

if [ "$(id -u)" -ne 0 ]; then
    msg_error "This script must be run as root."
    exit 1
fi

get_pve_version() {
  pveversion | awk -F'/' '{print $2}' | awk -F'-' '{print $1}'
}

get_pve_major_minor() {
  local ver="$1"
  local major minor
  IFS='.' read -r major minor _ <<<"$ver"
  echo "$major $minor"
}

# ==============================================================================
# POST INSTALL ROUTINES (Automated)
# ==============================================================================

start_routines_8() {
  msg_info "Configuring Proxmox 8.x Sources"
  cat <<EOF >/etc/apt/sources.list
deb https://deb.debian.org/debian bookworm main contrib
deb https://deb.debian.org/debian bookworm-updates main contrib
deb https://security.debian.org/debian-security bookworm-security main contrib
EOF
  echo 'APT::Get::Update::SourceListWarnings::NonFreeFirmware "false";' >/etc/apt/apt.conf.d/no-bookworm-firmware.conf
  
  rm -f /etc/apt/sources.list.d/pve-enterprise.list
  cat <<EOF >/etc/apt/sources.list.d/pve-install-repo.list
deb http://download.proxmox.com/debian/pve bookworm pve-no-subscription
EOF
  cat <<EOF >/etc/apt/sources.list.d/ceph.list
deb http://download.proxmox.com/debian/ceph-quincy bookworm no-subscription
EOF
  msg_ok "Configured Proxmox 8.x Sources (Enterprise Disabled, No-Subscription Enabled)"
}

start_routines_9() {
  local PVE_MINOR="${1:-0}"
  msg_info "Configuring Proxmox 9.x Sources (deb822)"
  
  rm -f /etc/apt/sources.list.d/*.list
  if [ -f /etc/apt/sources.list ]; then
    sed -i '/proxmox/d;/bookworm/d;/trixie/d' /etc/apt/sources.list
  fi

  cat >/etc/apt/sources.list.d/debian.sources <<EOF
Types: deb
URIs: http://deb.debian.org/debian
Suites: trixie trixie-updates
Components: main contrib
Signed-By: /usr/share/keyrings/debian-archive-keyring.gpg

Types: deb
URIs: http://security.debian.org/debian-security
Suites: trixie-security
Components: main contrib
Signed-By: /usr/share/keyrings/debian-archive-keyring.gpg
EOF

  rm -f /etc/apt/sources.list.d/pve-enterprise.sources
  for file in /etc/apt/sources.list.d/*.sources; do
    if grep -q "enterprise.proxmox.com" "$file" 2>/dev/null; then
      rm -f "$file"
    fi
  done

  cat >/etc/apt/sources.list.d/proxmox.sources <<EOF
Types: deb
URIs: http://download.proxmox.com/debian/pve
Suites: trixie
Components: pve-no-subscription
Signed-By: /usr/share/keyrings/proxmox-archive-keyring.gpg
EOF

  local CEPH_RELEASE="ceph-squid"
  if ((PVE_MINOR >= 2)); then CEPH_RELEASE="ceph-tentacle"; fi
  cat >/etc/apt/sources.list.d/ceph.sources <<EOF
Types: deb
URIs: http://download.proxmox.com/debian/${CEPH_RELEASE}
Suites: trixie
Components: no-subscription
Signed-By: /usr/share/keyrings/proxmox-archive-keyring.gpg
EOF
  msg_ok "Configured Proxmox 9.x Sources (Enterprise Disabled, No-Subscription Enabled)"
}

post_routines_common() {
  msg_info "Updating system packages (This may take a moment)"
  
  run_with_live_status "apt-get update" "Updating Repos" || msg_error "apt-get update failed"
  
  local upgrade_cmd='DEBIAN_FRONTEND=noninteractive apt-get -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" -y dist-upgrade'
  run_with_live_status "$upgrade_cmd" "Upgrading Packages" || msg_error "apt-get dist-upgrade failed"
  
  msg_ok "System packages updated successfully"

  msg_info "Applying automated UI Nag remover"
  mkdir -p /usr/local/bin
  cat >/usr/local/bin/pve-remove-nag.sh <<'EOF'
#!/bin/sh
WEB_JS=/usr/share/javascript/proxmox-widget-toolkit/proxmoxlib.js
if [ -s "$WEB_JS" ] && ! grep -q NoMoreNagging "$WEB_JS"; then
    sed -i -e "/data\.status/ s/!//" -e "/data\.status/ s/active/NoMoreNagging/" "$WEB_JS"
fi
EOF
  chmod 755 /usr/local/bin/pve-remove-nag.sh
  cat >/etc/apt/apt.conf.d/no-nag-script <<'EOF'
DPkg::Post-Invoke { "/usr/local/bin/pve-remove-nag.sh || true"; };
EOF
  chmod 644 /etc/apt/apt.conf.d/no-nag-script
  /usr/local/bin/pve-remove-nag.sh
  msg_ok "Subscription Nag automatically bypassed"
}

# ==============================================================================
# EXTERNAL HAWCMOX THEME INSTALLATION
# ==============================================================================

install_theme() {
    msg_info "Deploying HAWC SERVERS UI Environment"
    
    # Executing the external theme script directly from GitHub
    run_with_live_status "curl -fsSL https://raw.githubusercontent.com/HeyvaertSeppe/hawcmox-theme/refs/heads/main/theme.sh | bash" "Installing Theme" || msg_error "Theme installation failed"
    
    msg_ok "UI Environment deployed successfully"
}

# ==============================================================================
# MAIN EXECUTION
# ==============================================================================

main() {
  header_info

  # Determine Proxmox Version
  local PVE_VERSION PVE_MAJOR PVE_MINOR
  PVE_VERSION="$(get_pve_version)"
  read -r PVE_MAJOR PVE_MINOR <<<"$(get_pve_major_minor "$PVE_VERSION")"

  if [[ "$(dpkg --print-architecture 2>/dev/null)" == "arm64" ]]; then
    msg_info "ARM64 detected - skipping repository configuration"
  else
    if [[ "$PVE_MAJOR" == "8" ]]; then
      start_routines_8
    elif [[ "$PVE_MAJOR" == "9" ]]; then
      start_routines_9 "$PVE_MINOR"
    else
      msg_error "Unsupported Proxmox VE major version: $PVE_MAJOR. Exiting."
      exit 1
    fi
  fi

  post_routines_common
  install_theme

  echo ""
  msg_ok "DEPLOYMENT COMPLETE"
  echo -e "${YW}Please clear your browser cache or open an Incognito window to view the new UI.${CL}\n"
}

main
