#!/usr/bin/env bash

# ==============================================================================
# HAWC SERVERS - Unified Proxmox Post-Install & UI Theming Script
# ==============================================================================
# Automatically fixes repositories, updates the system, removes nags, preserves
# high availability, and installs the custom HAWCMOX interface overlay.
# ==============================================================================

set -euo pipefail
shopt -s inherit_errexit nullglob

# --- HAWCMOX Variables ---
DATA_DIR="/usr/local/share/hawcmox"
PATCH_SCRIPT="/usr/local/bin/hawcmox-patch.sh"
UNINSTALL_SCRIPT="/usr/local/bin/hawcmox-uninstall"
APT_HOOK="/etc/apt/apt.conf.d/99hawcmox-theme"
LOGO_RAW_FILE="$DATA_DIR/hawcmox_logo.raw"
LOGO_SVG_FILE="$DATA_DIR/hawcmox_logo.svg"
CSS_FILE="$DATA_DIR/hawcmox.css"
JS_FILE="$DATA_DIR/hawcmox.js"
CONFIG_FILE="$DATA_DIR/config"
SUBLIB_FILE="/usr/share/javascript/proxmox-widget-toolkit/js/proxmoxlib.js"
SUBLIB_BACKUP="$DATA_DIR/proxmoxlib.js.orig"

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
  apt-get update &>/dev/null || msg_error "apt-get update failed"
  apt-get -y dist-upgrade &>/dev/null || msg_error "apt-get dist-upgrade failed"
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

  # High Availability is preserved by design - no disable routines run here.
}


# ==============================================================================
# HAWCMOX THEME INSTALLATION (Automated)
# ==============================================================================

download_file() {
    url="$1"
    destination="$2"
    temporary_file="${destination}.download"
    rm -f "$temporary_file"
    if command -v curl >/dev/null 2>&1; then
        curl -4 --fail --location --silent --show-error --retry 3 "$url" --output "$temporary_file"
    elif command -v wget >/dev/null 2>&1; then
        wget -4 --quiet --tries=3 --output-document="$temporary_file" "$url"
    fi
    mv "$temporary_file" "$destination"
}

prepare_logo_svg() {
    raw_file="$1"
    out_svg="$2"
    if head -c 512 "$raw_file" 2>/dev/null | grep -qi '<svg'; then
        cp -f "$raw_file" "$out_svg"
        return 0
    fi
    b64="$(base64 -w0 "$raw_file" 2>/dev/null || base64 "$raw_file" | tr -d '\n')"
    cat > "$out_svg" <<EOF_SVG
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 200 60" width="200" height="60">
  <image width="200" height="60" preserveAspectRatio="xMidYMid meet" href="data:image/png;base64,${b64}"/>
</svg>
EOF_SVG
}

install_theme() {
    msg_info "Deploying HAWC SERVERS UI Environment"

    BRAND_TITLE="HAWC SERVERS"
    LOGO_URL="https://raw.githubusercontent.com/HeyvaertSeppe/hawcmox-theme/main/proxmox_logo.png"

    mkdir -p "$DATA_DIR"
    chmod 755 "$DATA_DIR"

    download_file "$LOGO_URL" "$LOGO_RAW_FILE"
    prepare_logo_svg "$LOGO_RAW_FILE" "$LOGO_SVG_FILE"
    rm -f "$LOGO_RAW_FILE"
    chmod 644 "$LOGO_SVG_FILE"

    cat > "$CSS_FILE" <<'EOF_CSS'
/* HAWCMOX - Modern Slate Proxmox Theme */

:root {
    --hawc-bg:           #1b1f26;
    --hawc-panel:        #242a33;
    --hawc-panel-alt:    #2b323d;
    --hawc-border:       #363e4a;
    --hawc-text:         #e6e9ee;
    --hawc-text-dim:     #a4acb8;
    --hawc-accent:       #5b6472;
    --hawc-accent-hov:   #6d7788;
    --hawc-nav-hover:    #24476b;
    --hawc-nav-active:   #2f6ea1;
    --hawc-nav-active-text:#ffffff;
    --hawc-success:      #22c55e;
    --hawc-success-bg:   rgba(34, 197, 94, 0.12);
    --hawc-radius:       10px;
    --hawc-radius-sm:    6px;

    --hawc-warn:         #eab308;
    --hawc-warn-text:    #1b1f26;
    --hawc-danger:       #e5484d;
    --hawc-danger-text:  #ffffff;
    --hawc-dark-btn:     #14171c;
    --hawc-dark-text:    #e6e9ee;
    --hawc-create:       #2f6f55;
    --hawc-create-border:#3f8f70;
    --hawc-create-text:  #e6e9ee;
}

html, body, .x-viewport, .x-body { background-color: var(--hawc-bg) !important; }
.x-panel, .x-panel-default, .x-window, .x-window-default, .x-message-box { background-color: var(--hawc-panel) !important; }
.x-panel-header, .x-panel-header-default, .x-window-header, .x-window-header-default { background-color: var(--hawc-panel-alt) !important; color: var(--hawc-text) !important; }
.x-panel-body, .x-panel-body-default, .x-window-body, .x-window-body-default { background-color: var(--hawc-bg) !important; color: var(--hawc-text) !important; }
iframe, .x-html-editor-wrap iframe, .x-panel-body[style*="background-color: white"] { background-color: var(--hawc-bg) !important; color: var(--hawc-text) !important; color-scheme: dark !important; }
.x-grid-body, .x-grid-view { background-color: var(--hawc-bg) !important; color: var(--hawc-text) !important; }
.x-grid-item { background-color: var(--hawc-panel) !important; color: var(--hawc-text) !important; }
.x-grid-item-alt { background-color: var(--hawc-panel-alt) !important; }
.x-toolbar { background-color: var(--hawc-panel-alt) !important; }
.x-btn { border-radius: var(--hawc-radius-sm) !important; transition: background-color 0.15s ease, opacity 0.15s ease !important; }
.x-btn-default-small, .x-btn-default-medium { background-color: var(--hawc-panel-alt) !important; border-color: var(--hawc-border) !important; color: var(--hawc-text) !important; }
.x-btn:hover { opacity: 0.88 !important; }
.x-btn-default-small.x-btn-over, .x-btn-default-medium.x-btn-over { background-color: var(--hawc-accent) !important; border-color: var(--hawc-accent) !important; }
.x-btn[data-hawc-action="reboot"] { background-color: var(--hawc-warn) !important; border-color: var(--hawc-warn) !important; }
.x-btn[data-hawc-action="reboot"] .x-btn-inner { color: var(--hawc-warn-text) !important; }
.x-btn[data-hawc-action="shutdown"], .x-btn[data-hawc-action="stop"] { background-color: var(--hawc-danger) !important; border-color: var(--hawc-danger) !important; }
.x-btn[data-hawc-action="shutdown"] .x-btn-inner, .x-btn[data-hawc-action="stop"] .x-btn-inner { color: var(--hawc-danger-text) !important; }
.x-btn[data-hawc-action="shell"], .x-btn[data-hawc-action="console"] { background-color: var(--hawc-dark-btn) !important; border-color: var(--hawc-dark-btn) !important; }
.x-btn[data-hawc-action="shell"] .x-btn-inner, .x-btn[data-hawc-action="console"] .x-btn-inner { color: var(--hawc-dark-text) !important; }
.x-btn[data-hawc-action="create-vm"], .x-btn[data-hawc-action="create-ct"] { background-color: var(--hawc-create) !important; border-color: var(--hawc-create-border) !important; }
.x-btn[data-hawc-action="create-vm"] .x-btn-inner, .x-btn[data-hawc-action="create-ct"] .x-btn-inner { color: var(--hawc-create-text) !important; }
.x-btn[data-hawc-action="system-report"] { display: none !important; }
.x-btn[data-hawc-action]:hover { filter: brightness(1.12) !important; opacity: 1 !important; }
.x-form-text, .x-form-text-default, .x-form-field, .x-form-text-wrap, .x-form-trigger-wrap { background-color: var(--hawc-panel-alt) !important; color: var(--hawc-text) !important; }
.x-menu, .x-menu-body, .x-boundlist { background-color: var(--hawc-bg) !important; }
.x-tab { background-color: var(--hawc-panel) !important; color: var(--hawc-text-dim) !important; }
.x-tab-active { background-color: var(--hawc-panel-alt) !important; color: var(--hawc-text) !important; }
.x-grid-header-ct, .x-column-header { background-color: var(--hawc-panel-alt) !important; color: var(--hawc-text) !important; }
.x-grid-row:hover .x-grid-cell, .x-grid-row-over .x-grid-cell { background-color: var(--hawc-panel-alt) !important; }
.x-grid-row-selected .x-grid-cell { background-color: rgba(255, 255, 255, 0.08) !important; }
.x-boundlist-item-over { background-color: var(--hawc-accent) !important; }
::-webkit-scrollbar { width: 10px; height: 10px; }
::-webkit-scrollbar-track { background: var(--hawc-bg); }
::-webkit-scrollbar-thumb { background: var(--hawc-border); border-radius: 6px; }
::-webkit-scrollbar-thumb:hover { background: var(--hawc-accent); }
.x-btn-inner, .x-btn-button, .x-btn-default-small .x-btn-inner, .x-btn-default-medium .x-btn-inner, .x-btn-default-toolbar-small .x-btn-inner, .x-btn-default-toolbar-medium .x-btn-inner { color: #ffffff !important; }

/* LOGO POSITONING */
img[src*="proxmox_logo"] { object-fit: contain !important; height: 55px !important; max-width: 280px !important; max-height: none !important; filter: none !important; -webkit-filter: none !important; mix-blend-mode: normal !important; opacity: 1 !important; position: fixed !important; z-index: 2147483647 !important; top: 0 !important; left: 0 !important; margin-top: 10px !important; margin-left: 20px !important; }

/* MENU FIXES */
.x-container.x-border-item.x-box-item[style*="left: 5px"], div[id^="container-"][style*="left: 5px"] { top: 69px !important; }
div[id^="pveResourceTree-"][id$="-body"] { height: 600px !important; }

/* Left Menu Coloring */
[id^="pveResourceTree-"] .x-grid-row .x-grid-cell, [id^="pveResourceTree-"] .x-grid-row, [id^="pveResourceTree-"] .x-grid-item, [id^="pveResourceTree-"] .x-grid-cell-inner, [id^="pveResourceTree-"] .x-tree-view, [id^="pveResourceTree-"] .x-grid-item-container { background-color: var(--hawc-panel-alt) !important; }
[id^="pveResourceTree-"] .x-grid-row-over .x-grid-cell, [id^="pveResourceTree-"] .x-grid-row-selected .x-grid-cell, [id^="pveResourceTree-"] .x-grid-item-selected .x-grid-cell { background-color: rgba(59, 130, 246, 0.22) !important; }
[id^="pveResourceTree-"] .x-grid-row-over .x-grid-cell, [id^="pveResourceTree-"] .x-grid-row:hover .x-grid-cell, [id^="pveResourceTree-"] .x-grid-item-over .x-grid-cell, [id^="pveResourceTree-"] .x-grid-item-focused .x-grid-cell { background-color: var(--hawc-nav-hover) !important; color: var(--hawc-nav-active-text) !important; }
[id^="pveResourceTree-"] .x-grid-row-selected .x-grid-cell, [id^="pveResourceTree-"] .x-grid-item-selected .x-grid-cell, [id^="pveResourceTree-"] .x-grid-item-selected .x-grid-cell-inner, [id^="pveResourceTree-"] .x-grid-row-selected .x-grid-cell-inner { background-color: var(--hawc-nav-active) !important; color: var(--hawc-nav-active-text) !important; }
[id^="pveResourceTree-"] .x-grid-row-selected .x-tree-node-text, [id^="pveResourceTree-"] .x-grid-row-over .x-tree-node-text, [id^="pveResourceTree-"] .x-grid-item-selected .x-tree-node-text, [id^="pveResourceTree-"] .x-grid-item-over .x-tree-node-text { color: var(--hawc-nav-active-text) !important; }
.x-tab:hover, .x-tab-over, .x-tab-default:hover, .x-tab-default.x-tab-over, .x-tab-button:hover, .x-tab .x-tab-inner:hover { background-color: var(--hawc-nav-hover) !important; color: var(--hawc-nav-active-text) !important; }
.x-tab-active, .x-tab-active.x-tab-default, .x-tab-focus.x-tab-active, .x-tab.x-tab-active { background-color: var(--hawc-nav-active) !important; color: var(--hawc-nav-active-text) !important; }
.x-tab-active .x-tab-inner, .x-tab:hover .x-tab-inner, .x-tab-over .x-tab-inner, .x-tab-active .x-tab-icon-el, .x-tab:hover .x-tab-icon-el, .x-tab-over .x-tab-icon-el { color: var(--hawc-nav-active-text) !important; }
.x-panel .x-grid-row-over .x-grid-cell, .x-panel .x-grid-row:hover .x-grid-cell, .x-panel .x-menu-item:hover .x-menu-item-link, .x-panel .x-menu-item-active .x-menu-item-link, .x-panel .x-boundlist-item-over { background-color: var(--hawc-nav-hover) !important; color: var(--hawc-nav-active-text) !important; }
.x-panel .x-grid-row-selected .x-grid-cell, .x-panel .x-grid-item-selected .x-grid-cell, .x-panel .x-boundlist-selected, .x-panel .x-menu-item-focus .x-menu-item-link { background-color: var(--hawc-nav-active) !important; color: var(--hawc-nav-active-text) !important; }
.x-treelist, .x-treelist-root-container, .x-treelist-container, .x-treelist-row, .x-treelist-item-wrap, .x-treelist-item, .x-treelist-toolstrip { background-color: var(--hawc-panel-alt) !important; color: var(--hawc-text) !important; }
.x-treelist .x-treelist-item-text, .x-treelist .x-treelist-item-icon, .x-treelist .x-treelist-item-expander, .x-treelist .x-treelist-item-tool { color: inherit !important; }
.x-treelist .x-treelist-item:hover > .x-treelist-row, .x-treelist .x-treelist-row:hover, .x-treelist .x-treelist-item-over > .x-treelist-row, .x-treelist .x-treelist-item:hover > .x-treelist-row .x-treelist-item-wrap { background-color: var(--hawc-nav-hover) !important; color: var(--hawc-nav-active-text) !important; }
.x-treelist .x-treelist-item-selected > .x-treelist-row, .x-treelist .x-treelist-item-selected > .x-treelist-row .x-treelist-item-wrap, .x-treelist .x-treelist-item-selected > .x-treelist-row .x-treelist-item-text, .x-treelist .x-treelist-item-selected > .x-treelist-row .x-treelist-item-icon, .x-treelist .x-treelist-item-selected > .x-treelist-row .x-treelist-item-expander, .x-treelist .x-treelist-item-selected > .x-treelist-row .x-treelist-item-tool { background-color: var(--hawc-nav-active) !important; color: var(--hawc-nav-active-text) !important; }
.x-treelist-item-tool:hover, .x-treelist-item-tool.x-treelist-item-selected { background-color: var(--hawc-nav-active) !important; color: var(--hawc-nav-active-text) !important; }

/* Custom Support Card */
.hawc-subscription-card { display: flex !important; flex-direction: column !important; align-items: flex-start !important; gap: 12px !important; padding: 18px !important; box-sizing: border-box !important; border-radius: var(--hawc-radius) !important; background-color: var(--hawc-panel-alt) !important; border: 1px solid var(--hawc-border) !important; color: var(--hawc-text) !important; }
.hawc-card-title { color: #ffffff !important; font-size: 18px !important; font-weight: 600 !important; margin: 0 !important; }
.hawc-card-text { color: inherit !important; line-height: 1.45 !important; margin: 0 !important; }
.hawc-subscription-link { color: #93c5fd !important; text-decoration: none !important; }
.hawc-subscription-link:hover { color: #bfdbfe !important; text-decoration: underline !important; }
.hawc-contact-btn { display: inline-flex !important; align-items: center !important; justify-content: center !important; padding: 8px 14px !important; background-color: var(--hawc-nav-active) !important; border: 1px solid var(--hawc-nav-active) !important; border-radius: var(--hawc-radius-sm) !important; color: #ffffff !important; text-decoration: none !important; cursor: pointer !important; }
.hawc-contact-btn:hover { background-color: var(--hawc-nav-hover) !important; border-color: var(--hawc-nav-hover) !important; color: #ffffff !important; }
.x-btn-icon-el.fa-gear, .x-btn-icon-el.fa-fw.fa-gear { color: #ffffff !important; opacity: 1 !important; }
.pmx-hint { display: none !important; }

#versioninfo { font-size: 12px !important; line-height: 20px !important; padding: 0px 5px !important; left: 287px !important; height: 20px !important; margin: 0px !important; top: 10px !important; width: 150px !important; position: absolute !important; background: transparent !important; border: none !important; }
#versioninfo .x-autocontainer-innerCt { font-size: 12px !important; color: var(--hawc-text-dim) !important; }
EOF_CSS
    chmod 644 "$CSS_FILE"

    cat > "$JS_FILE" <<'EOF_JS'
(function () {
    function buildSupportMailto() {
      return 'mailto:support@hawc.be?subject=' + encodeURIComponent('HAWC SERVERS Support Request') + '&body=' + encodeURIComponent('Hello HAWC Support,\n\nI need help with my Node.\n\nServer: \nIssue: \nPreferred contact name: \n\nThanks,');
    }
    function updateUI() {
        var versionContainer = document.querySelector('#versioninfo .x-autocontainer-innerCt');
        if (versionContainer && !versionContainer.getAttribute('data-hawc-patched')) {
            versionContainer.textContent = versionContainer.textContent.replace(/Virtual Environment\s*([\d.]+)/i, 'VE v$1');
            versionContainer.setAttribute('data-hawc-patched', 'true');
        }
        var btns = document.querySelectorAll('.x-btn:not([data-hawc-action])');
        for (var i = 0; i < btns.length; i++) {
            var t = (btns[i].textContent || btns[i].getAttribute('data-qtip') || '').trim().toLowerCase();
            if (t === 'create vm') btns[i].setAttribute('data-hawc-action', 'create-vm');
            else if (t === 'create ct') btns[i].setAttribute('data-hawc-action', 'create-ct');
            else if (t === 'reboot') btns[i].setAttribute('data-hawc-action', 'reboot');
            else if (t === 'shutdown' || t === 'stop') btns[i].setAttribute('data-hawc-action', 'shutdown');
            else if (t === 'console' || t === 'shell' || t === '>_ console') btns[i].setAttribute('data-hawc-action', 'console');
            else btns[i].setAttribute('data-hawc-action', 'none'); 
        }
        var wins = document.querySelectorAll('.x-window, .x-message-box');
        for (var w = 0; w < wins.length; w++) {
            if (/no valid subscription/i.test(wins[w].textContent)) {
                var btn = wins[w].querySelector('.x-btn');
                if (btn) btn.click();
            }
        }
        var targets = document.querySelectorAll('[id^="pveDcSupport-"] .x-autocontainer-innerCt:not([data-hawc-card]), [id^="pveDcSupport-"] .x-panel-body:not([data-hawc-card])');
        for (var k = 0; k < targets.length; k++) {
            var el = targets[k];
            var txt = (el.textContent || '').replace(/\s+/g, ' ').trim();
            if (/No valid subscription/i.test(txt) || el.closest('[id^="pveDcSupport-"]')) {
                el.innerHTML = '' +
                '<div class="hawc-subscription-card">' +
                  '<div class="hawc-card-title">HAWC SERVERS Support</div>' +
                  '<div class="hawc-card-text">Contact info: <a class="hawc-subscription-link" href="mailto:support@hawc.be">support@hawc.be</a></div>' +
                  '<div class="hawc-card-text">Use the button below to open a prefilled support email.</div>' +
                  '<a class="hawc-contact-btn" href="' + buildSupportMailto() + '">Contact now</a>' +
                '</div>';
                el.setAttribute('data-hawc-card', 'done');
            }
        }
        var docSpans = document.querySelectorAll('.x-btn-inner');
        for (var s = 0; s < docSpans.length; s++) {
            if (docSpans[s].textContent.trim() === 'Documentation') {
                var docBtn = docSpans[s].closest('.x-btn');
                if (docBtn && docBtn.getAttribute('data-hawc-support') !== 'done') {
                    docSpans[s].textContent = 'Support';
                    var icon = docBtn.querySelector('.fa-book');
                    if (icon) {
                        icon.classList.remove('fa-book');
                        icon.classList.add('fa-life-ring');
                    }
                    docBtn.style.setProperty('display', 'inline-block', 'important');
                    docBtn.addEventListener('click', function(e) {
                        e.preventDefault();
                        e.stopPropagation(); 
                        window.location.hash = '#v1:0:18:=pveDcSupport:::::::27';
                    }, true);
                    docBtn.removeAttribute('data-qtip');
                    docBtn.setAttribute('data-hawc-support', 'done');
                }
                break;
            }
        }
    }
    var resizeTimeout;
    function nudgeExtLayout() {
        if (resizeTimeout) return;
        resizeTimeout = setTimeout(function() {
            try {
                if (typeof Ext !== 'undefined' && Ext.EventManager && Ext.EventManager.fireResize) {
                    Ext.EventManager.fireResize();
                } else {
                    window.dispatchEvent(new Event('resize'));
                }
            } catch (e) {}
            resizeTimeout = null;
        }, 60);
    }
    var throttleTimeout;
    var observer = new MutationObserver(function() {
        if (throttleTimeout) return;
        throttleTimeout = setTimeout(function() {
            updateUI();
            nudgeExtLayout();
            throttleTimeout = null;
        }, 50);
    });
    document.addEventListener('DOMContentLoaded', function() {
        updateUI();
        observer.observe(document.body, { childList: true, subtree: true });
    });
    if (document.readyState === 'complete' || document.readyState === 'interactive') {
        updateUI();
        observer.observe(document.body, { childList: true, subtree: true });
    }
})();
EOF_JS
    chmod 644 "$JS_FILE"

    printf '%s\nyes\n' "$BRAND_TITLE" > "$CONFIG_FILE"

    cat > "$PATCH_SCRIPT" <<'EOF_PATCH'
#!/bin/sh
set -eu
DATA_DIR="/usr/local/share/hawcmox"
CONFIG_FILE="$DATA_DIR/config"
SOURCE_LOGO="$DATA_DIR/hawcmox_logo.svg"
SOURCE_CSS="$DATA_DIR/hawcmox.css"
SOURCE_JS="$DATA_DIR/hawcmox.js"
TARGET_LOGO_PWT="/usr/share/javascript/proxmox-widget-toolkit/images/proxmox_logo.svg"
TARGET_LOGO_PWT_BACKUP="$DATA_DIR/proxmox_logo.svg.orig"
TARGET_LOGO_PVE="/usr/share/pve-manager/images/proxmox_logo.png"
TARGET_CSS="/usr/share/pve-manager/css/hawcmox.css"
TARGET_JS="/usr/share/pve-manager/js/hawcmox.js"
TEMPLATE_FILE="/usr/share/pve-manager/index.html.tpl"

BRAND_TITLE="HAWC SERVERS"
escape_sed_replacement() { printf '%s' "$1" | sed 's/[\/&|\\]/\\&/g'; }

if [ -f "$TARGET_LOGO_PWT" ] && [ ! -f "$TARGET_LOGO_PWT_BACKUP" ]; then cp -f "$TARGET_LOGO_PWT" "$TARGET_LOGO_PWT_BACKUP" 2>/dev/null || true; fi
if [ -f "$SOURCE_LOGO" ]; then
    if [ -d "$(dirname "$TARGET_LOGO_PWT")" ]; then cp -f "$SOURCE_LOGO" "$TARGET_LOGO_PWT" && chmod 644 "$TARGET_LOGO_PWT"; fi
    if [ -f "$TARGET_LOGO_PVE" ]; then cp -f "$SOURCE_LOGO" "$TARGET_LOGO_PVE" 2>/dev/null || true; fi
fi

[ -f "$SOURCE_CSS" ] && cp -f "$SOURCE_CSS" "$TARGET_CSS" && chmod 644 "$TARGET_CSS"
[ -f "$SOURCE_JS" ] && cp -f "$SOURCE_JS" "$TARGET_JS" && chmod 644 "$TARGET_JS"

if [ -f "$TEMPLATE_FILE" ]; then
    escaped_title="$(escape_sed_replacement "$BRAND_TITLE")"
    sed -i "s|<title>[^<]*</title>|<title>${escaped_title}</title>|" "$TEMPLATE_FILE"
    if ! grep -q 'css/hawcmox.css' "$TEMPLATE_FILE"; then
        sed -i 's|</head>|    <link rel="stylesheet" type="text/css" href="/pve2/css/hawcmox.css">\n</head>|' "$TEMPLATE_FILE"
    fi
    if ! grep -q 'js/hawcmox.js' "$TEMPLATE_FILE"; then
        sed -i 's|</head>|    <script type="text/javascript" src="/pve2/js/hawcmox.js"></script>\n</head>|' "$TEMPLATE_FILE"
    fi
fi

if command -v systemctl >/dev/null 2>&1; then systemctl restart pveproxy.service >/dev/null 2>&1 || true; fi
EOF_PATCH
    chmod 755 "$PATCH_SCRIPT"

    cat > "$APT_HOOK" <<'EOF_HOOK'
DPkg::Post-Invoke { "/usr/local/bin/hawcmox-patch.sh || true"; };
EOF_HOOK
    chmod 644 "$APT_HOOK"

    "$PATCH_SCRIPT"
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
