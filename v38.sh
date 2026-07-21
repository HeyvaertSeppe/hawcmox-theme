#!/bin/sh

# HAWCMOX Proxmox UI Manager v7.1 - For Proxmox 8+ and 9.2.2+
# Unified automated script to Install or Remove the custom theme.

set -eu

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

if [ "$(id -u)" -ne 0 ]; then
    printf '%s\n' "ERROR: This script must be run as root."
    exit 1
fi

if [ ! -d "/usr/share/pve-manager" ]; then
    printf '%s\n' "ERROR: This does not appear to be a Proxmox VE node."
    exit 1
fi

download_file() {
    url="$1"
    destination="$2"
    temporary_file="${destination}.download"
    rm -f "$temporary_file"

    if command -v curl >/dev/null 2>&1; then
        if ! curl -4 --fail --location --silent --show-error --retry 3 "$url" --output "$temporary_file"; then
            rm -f "$temporary_file"
            printf '%s\n' "ERROR: Download failed (curl could not fetch $url)."
            exit 1
        fi
    elif command -v wget >/dev/null 2>&1; then
        if ! wget -4 --quiet --tries=3 --output-document="$temporary_file" "$url"; then
            rm -f "$temporary_file"
            printf '%s\n' "ERROR: Download failed (wget could not fetch $url)."
            exit 1
        fi
    else
        printf '%s\n' "ERROR: Neither curl nor wget is installed."
        exit 1
    fi

    if [ ! -s "$temporary_file" ]; then
        rm -f "$temporary_file"
        printf '%s\n' "ERROR: Download failed. Check your URL."
        exit 1
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

    sig="$(head -c 8 "$raw_file" | od -An -tx1 | tr -d ' \n')"

    if [ "$sig" = "89504e470d0a1a0a" ]; then
        width="$(od -An -tu4 -j 16 -N 4 --endian=big "$raw_file" | tr -d ' ')"
        height="$(od -An -tu4 -j 20 -N 4 --endian=big "$raw_file" | tr -d ' ')"
        mime="image/png"
    else
        width="200"
        height="60"
        mime="image/*"
    fi

    b64="$(base64 -w0 "$raw_file" 2>/dev/null || base64 "$raw_file" | tr -d '\n')"

    cat > "$out_svg" <<EOF_SVG
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 ${width} ${height}" width="${width}" height="${height}">
  <image width="${width}" height="${height}" preserveAspectRatio="xMidYMid meet" href="data:${mime};base64,${b64}"/>
</svg>
EOF_SVG
}

install_theme() {
    printf '\n============================================================\n'
    printf ' HAWCMOX INSTALLER\n'
    printf '============================================================\n'

    BRAND_TITLE="HAWCMOX"
    LOGO_URL="https://raw.githubusercontent.com/HeyvaertSeppe/hawcmox-theme/main/proxmox_logo.png"
    INSTALL_APT_HOOK="yes"
    HIDE_NAG="yes"

    printf '\n[1/8] Creating directories...\n'
    mkdir -p "$DATA_DIR"
    chmod 755 "$DATA_DIR"

    printf '[2/8] Downloading and preparing custom logo...\n'
    download_file "$LOGO_URL" "$LOGO_RAW_FILE"
    prepare_logo_svg "$LOGO_RAW_FILE" "$LOGO_SVG_FILE"
    rm -f "$LOGO_RAW_FILE"
    chmod 644 "$LOGO_SVG_FILE"

    printf '[3/8] Generating modern slate CSS theme...\n'
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

    /* Action-button colors */
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

html, body, .x-viewport, .x-body {
    background-color: var(--hawc-bg) !important;
}

/* --- SAFE PANEL & WINDOW THEMING --- */
.x-panel, .x-panel-default, .x-window, .x-window-default, .x-message-box {
    background-color: var(--hawc-panel) !important;
}

.x-panel-header, .x-panel-header-default, .x-window-header, .x-window-header-default {
    background-color: var(--hawc-panel-alt) !important;
    color: var(--hawc-text) !important;
}

.x-panel-body, .x-panel-body-default, .x-window-body, .x-window-body-default {
    background-color: var(--hawc-bg) !important;
    color: var(--hawc-text) !important;
}
/* ---------------------------------- */

/* Fix Logs background specifically */
iframe, .x-html-editor-wrap iframe, .x-panel-body[style*="background-color: white"] {
    background-color: var(--hawc-bg) !important;
    color: var(--hawc-text) !important;
    color-scheme: dark !important;
}

/* Grids (Tasks List, Node Lists, etc) */
.x-grid-body, .x-grid-view {
    background-color: var(--hawc-bg) !important;
    color: var(--hawc-text) !important;
}

.x-grid-item {
    background-color: var(--hawc-panel) !important;
    color: var(--hawc-text) !important;
}

.x-grid-item-alt {
    background-color: var(--hawc-panel-alt) !important;
}

.x-toolbar {
    background-color: var(--hawc-panel-alt) !important;
}

.x-btn {
    border-radius: var(--hawc-radius-sm) !important;
    transition: background-color 0.15s ease, opacity 0.15s ease !important;
}

.x-btn-default-small, .x-btn-default-medium {
    background-color: var(--hawc-panel-alt) !important;
    border-color: var(--hawc-border) !important;
    color: var(--hawc-text) !important;
}

.x-btn:hover {
    opacity: 0.88 !important;
}

.x-btn-default-small.x-btn-over,
.x-btn-default-medium.x-btn-over {
    background-color: var(--hawc-accent) !important;
    border-color: var(--hawc-accent) !important;
}

.x-btn[data-hawc-action="reboot"] {
    background-color: var(--hawc-warn) !important;
    border-color: var(--hawc-warn) !important;
}
.x-btn[data-hawc-action="reboot"] .x-btn-inner {
    color: var(--hawc-warn-text) !important;
}

.x-btn[data-hawc-action="shutdown"],
.x-btn[data-hawc-action="stop"] {
    background-color: var(--hawc-danger) !important;
    border-color: var(--hawc-danger) !important;
}
.x-btn[data-hawc-action="shutdown"] .x-btn-inner,
.x-btn[data-hawc-action="stop"] .x-btn-inner {
    color: var(--hawc-danger-text) !important;
}

.x-btn[data-hawc-action="shell"],
.x-btn[data-hawc-action="console"] {
    background-color: var(--hawc-dark-btn) !important;
    border-color: var(--hawc-dark-btn) !important;
}
.x-btn[data-hawc-action="shell"] .x-btn-inner,
.x-btn[data-hawc-action="console"] .x-btn-inner {
    color: var(--hawc-dark-text) !important;
}

.x-btn[data-hawc-action="create-vm"],
.x-btn[data-hawc-action="create-ct"] {
    background-color: var(--hawc-create) !important;
    border-color: var(--hawc-create-border) !important;
}
.x-btn[data-hawc-action="create-vm"] .x-btn-inner,
.x-btn[data-hawc-action="create-ct"] .x-btn-inner {
    color: var(--hawc-create-text) !important;
}

.x-btn[data-hawc-action="system-report"] { display: none !important; }

.x-btn[data-hawc-action]:hover {
    filter: brightness(1.12) !important;
    opacity: 1 !important;
}

.x-form-text, 
.x-form-text-default, 
.x-form-field,
.x-form-text-wrap,
.x-form-trigger-wrap {
    background-color: var(--hawc-panel-alt) !important;
    color: var(--hawc-text) !important;
}

.x-menu, 
.x-menu-body, 
.x-boundlist {
    background-color: var(--hawc-bg) !important;
}

.x-tab {
    background-color: var(--hawc-panel) !important;
    color: var(--hawc-text-dim) !important;
}

.x-tab-active {
    background-color: var(--hawc-panel-alt) !important;
    color: var(--hawc-text) !important;
}

.x-grid-header-ct, .x-column-header {
    background-color: var(--hawc-panel-alt) !important;
    color: var(--hawc-text) !important;
}

.x-grid-row:hover .x-grid-cell,
.x-grid-row-over .x-grid-cell {
    background-color: var(--hawc-panel-alt) !important;
}

.x-grid-row-selected .x-grid-cell {
    background-color: rgba(255, 255, 255, 0.08) !important;
}

.x-boundlist-item-over {
    background-color: var(--hawc-accent) !important;
}

::-webkit-scrollbar {
    width: 10px;
    height: 10px;
}
::-webkit-scrollbar-track {
    background: var(--hawc-bg);
}
::-webkit-scrollbar-thumb {
    background: var(--hawc-border);
    border-radius: 6px;
}
::-webkit-scrollbar-thumb:hover {
    background: var(--hawc-accent);
}

.x-btn-inner,
.x-btn-button,
.x-btn-default-small .x-btn-inner,
.x-btn-default-medium .x-btn-inner,
.x-btn-default-toolbar-small .x-btn-inner,
.x-btn-default-toolbar-medium .x-btn-inner {
  color: #ffffff !important;
}

/* --- LOGO POSITONING (Original strict positioning + Anti-Invert) --- */
img[src*="proxmox_logo"] {
    object-fit: contain !important;
    height: 55px !important;
    max-width: 280px !important;
    max-height: none !important;
    filter: none !important;
    -webkit-filter: none !important;
    mix-blend-mode: normal !important;
    opacity: 1 !important;
    position: fixed !important; 
    z-index: 2147483647 !important; 
    top: 0 !important;
    left: 0 !important;
    margin-top: 10px !important;
    margin-left: 20px !important;
}
/* ------------------------------------------------------------------- */


/* --- EXACT FIX: Push down Left Navigation & Prevent Tasks Overlap --- */
.x-container.x-border-item.x-box-item[style*="left: 5px"],
div[id^="container-"][style*="left: 5px"] {
    top: 69px !important;
    height: calc(100vh - 130px) !important; /* Dynamically shrinks to prevent overlapping the Tasks window */
    z-index: 10 !important;
}

[id^="pveResourceTree-"] .x-tree-view {
    height: calc(100vh - 170px) !important; /* Perfect scaling equivalent to your 600px test */
    max-height: calc(100vh - 170px) !important;
    overflow-y: auto !important;
}
/* ------------------------------------------------------------------- */


/* Left Menu Coloring */
[id^="pveResourceTree-"] .x-grid-row .x-grid-cell,
[id^="pveResourceTree-"] .x-grid-row,
[id^="pveResourceTree-"] .x-grid-item,
[id^="pveResourceTree-"] .x-grid-cell-inner,
[id^="pveResourceTree-"] .x-tree-view,
[id^="pveResourceTree-"] .x-grid-item-container {
  background-color: var(--hawc-panel-alt) !important;
}

[id^="pveResourceTree-"] .x-grid-row-over .x-grid-cell,
[id^="pveResourceTree-"] .x-grid-row-selected .x-grid-cell,
[id^="pveResourceTree-"] .x-grid-item-selected .x-grid-cell {
  background-color: rgba(59, 130, 246, 0.22) !important;
}

[id^="pveResourceTree-"] .x-grid-row-over .x-grid-cell,
[id^="pveResourceTree-"] .x-grid-row:hover .x-grid-cell,
[id^="pveResourceTree-"] .x-grid-item-over .x-grid-cell,
[id^="pveResourceTree-"] .x-grid-item-focused .x-grid-cell {
  background-color: var(--hawc-nav-hover) !important;
  color: var(--hawc-nav-active-text) !important;
}

[id^="pveResourceTree-"] .x-grid-row-selected .x-grid-cell,
[id^="pveResourceTree-"] .x-grid-item-selected .x-grid-cell,
[id^="pveResourceTree-"] .x-grid-item-selected .x-grid-cell-inner,
[id^="pveResourceTree-"] .x-grid-row-selected .x-grid-cell-inner {
  background-color: var(--hawc-nav-active) !important;
  color: var(--hawc-nav-active-text) !important;
}

[id^="pveResourceTree-"] .x-grid-row-selected .x-tree-node-text,
[id^="pveResourceTree-"] .x-grid-row-over .x-tree-node-text,
[id^="pveResourceTree-"] .x-grid-item-selected .x-tree-node-text,
[id^="pveResourceTree-"] .x-grid-item-over .x-tree-node-text {
  color: var(--hawc-nav-active-text) !important;
}

.x-tab:hover,
.x-tab-over,
.x-tab-default:hover,
.x-tab-default.x-tab-over,
.x-tab-button:hover,
.x-tab .x-tab-inner:hover {
  background-color: var(--hawc-nav-hover) !important;
  color: var(--hawc-nav-active-text) !important;
}

.x-tab-active,
.x-tab-active.x-tab-default,
.x-tab-focus.x-tab-active,
.x-tab.x-tab-active {
  background-color: var(--hawc-nav-active) !important;
  color: var(--hawc-nav-active-text) !important;
}

.x-tab-active .x-tab-inner,
.x-tab:hover .x-tab-inner,
.x-tab-over .x-tab-inner,
.x-tab-active .x-tab-icon-el,
.x-tab:hover .x-tab-icon-el,
.x-tab-over .x-tab-icon-el {
  color: var(--hawc-nav-active-text) !important;
}

.x-panel .x-grid-row-over .x-grid-cell,
.x-panel .x-grid-row:hover .x-grid-cell,
.x-panel .x-menu-item:hover .x-menu-item-link,
.x-panel .x-menu-item-active .x-menu-item-link,
.x-panel .x-boundlist-item-over {
  background-color: var(--hawc-nav-hover) !important;
  color: var(--hawc-nav-active-text) !important;
}

.x-panel .x-grid-row-selected .x-grid-cell,
.x-panel .x-grid-item-selected .x-grid-cell,
.x-panel .x-boundlist-selected,
.x-panel .x-menu-item-focus .x-menu-item-link {
  background-color: var(--hawc-nav-active) !important;
  color: var(--hawc-nav-active-text) !important;
}

.x-treelist,
.x-treelist-root-container,
.x-treelist-container,
.x-treelist-row,
.x-treelist-item-wrap,
.x-treelist-item,
.x-treelist-toolstrip {
  background-color: var(--hawc-panel-alt) !important;
  color: var(--hawc-text) !important;
}

.x-treelist .x-treelist-item-text,
.x-treelist .x-treelist-item-icon,
.x-treelist .x-treelist-item-expander,
.x-treelist .x-treelist-item-tool {
  color: inherit !important;
}

.x-treelist .x-treelist-item:hover > .x-treelist-row,
.x-treelist .x-treelist-row:hover,
.x-treelist .x-treelist-item-over > .x-treelist-row,
.x-treelist .x-treelist-item:hover > .x-treelist-row .x-treelist-item-wrap {
  background-color: var(--hawc-nav-hover) !important;
  color: var(--hawc-nav-active-text) !important;
}

.x-treelist .x-treelist-item-selected > .x-treelist-row,
.x-treelist .x-treelist-item-selected > .x-treelist-row .x-treelist-item-wrap,
.x-treelist .x-treelist-item-selected > .x-treelist-row .x-treelist-item-text,
.x-treelist .x-treelist-item-selected > .x-treelist-row .x-treelist-item-icon,
.x-treelist .x-treelist-item-selected > .x-treelist-row .x-treelist-item-expander,
.x-treelist .x-treelist-item-selected > .x-treelist-row .x-treelist-item-tool {
  background-color: var(--hawc-nav-active) !important;
  color: var(--hawc-nav-active-text) !important;
}

.x-treelist-item-tool:hover,
.x-treelist-item-tool.x-treelist-item-selected {
  background-color: var(--hawc-nav-active) !important;
  color: var(--hawc-nav-active-text) !important;
}

.hawc-subscription-card {
  display: flex !important;
  flex-direction: column !important;
  align-items: flex-start !important;
  gap: 12px !important;
  padding: 18px !important;
  box-sizing: border-box !important;
  border-radius: var(--hawc-radius) !important;
  background-color: var(--hawc-panel-alt) !important;
  border: 1px solid var(--hawc-border) !important;
  color: var(--hawc-text) !important;
}

.hawc-card-title {
  color: #ffffff !important;
  font-size: 18px !important;
  font-weight: 600 !important;
  margin: 0 !important;
}

.hawc-card-text {
  color: inherit !important;
  line-height: 1.45 !important;
  margin: 0 !important;
}

.hawc-subscription-link {
  color: #93c5fd !important;
  text-decoration: none !important;
}

.hawc-subscription-link:hover {
  color: #bfdbfe !important;
  text-decoration: underline !important;
}

.hawc-contact-btn {
  display: inline-flex !important;
  align-items: center !important;
  justify-content: center !important;
  padding: 8px 14px !important;
  background-color: var(--hawc-nav-active) !important;
  border: 1px solid var(--hawc-nav-active) !important;
  border-radius: var(--hawc-radius-sm) !important;
  color: #ffffff !important;
  text-decoration: none !important;
  cursor: pointer !important;
}

.hawc-contact-btn:hover {
  background-color: var(--hawc-nav-hover) !important;
  border-color: var(--hawc-nav-hover) !important;
  color: #ffffff !important;
}

.x-btn-icon-el.fa-gear,
.x-btn-icon-el.fa-fw.fa-gear {
  color: #ffffff !important;
  opacity: 1 !important;
}

.pmx-hint {
    display: none !important;
}

/* --- Fixed Element Styles for Version Info --- */
#versioninfo {
    font-size: 12px !important;
    line-height: 20px !important;
    padding: 0px 5px !important;
    left: 287px !important;
    height: 20px !important;
    margin: 0px !important;
    top: 10px !important;
    width: 150px !important;
    position: absolute !important;
    background: transparent !important;
    border: none !important;
}

#versioninfo .x-autocontainer-innerCt {
    font-size: 12px !important;
    color: var(--hawc-text-dim) !important;
}
/* --------------------------------------------- */
EOF_CSS
    chmod 644 "$CSS_FILE"

    printf '[4/8] Generating UI patcher script...\n'
    cat > "$JS_FILE" <<'EOF_JS'
(function () {
    
    function buildSupportMailto() {
      return 'mailto:support@hawc.be?subject=' + encodeURIComponent('HAWCMOX Support Request') + '&body=' + encodeURIComponent('Hello HAWC Support,\n\nI need help with HAWCMOX.\n\nServer: \nIssue: \nPreferred contact name: \n\nThanks,');
    }

    function updateUI() {
        
        // 1. Version Info Text modification
        var versionContainer = document.querySelector('#versioninfo .x-autocontainer-innerCt');
        if (versionContainer && !versionContainer.getAttribute('data-hawc-patched')) {
            versionContainer.textContent = versionContainer.textContent.replace(/Virtual Environment\s*([\d.]+)/i, 'VE v$1');
            versionContainer.setAttribute('data-hawc-patched', 'true');
        }

        // 2. Action Button styling properties
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

        // 3. Subscription Nag Removal inside Popups
        var wins = document.querySelectorAll('.x-window, .x-message-box');
        for (var w = 0; w < wins.length; w++) {
            if (/no valid subscription/i.test(wins[w].textContent)) {
                var btn = wins[w].querySelector('.x-btn');
                if (btn) btn.click();
            }
        }

        // 4. Transform Datacenter Support Panels directly into HAWC Support
        var targets = document.querySelectorAll('[id^="pveDcSupport-"] .x-autocontainer-innerCt:not([data-hawc-card]), [id^="pveDcSupport-"] .x-panel-body:not([data-hawc-card])');
        for (var k = 0; k < targets.length; k++) {
            var el = targets[k];
            var txt = (el.textContent || '').replace(/\s+/g, ' ').trim();
            if (/No valid subscription/i.test(txt) || el.closest('[id^="pveDcSupport-"]')) {
                el.innerHTML = '' +
                '<div class="hawc-subscription-card">' +
                  '<div class="hawc-card-title">HAWCMOX Support</div>' +
                  '<div class="hawc-card-text">Contact info: <a class="hawc-subscription-link" href="mailto:support@hawc.be">support@hawc.be</a></div>' +
                  '<div class="hawc-card-text">Use the button below to open a prefilled HAWCMOX support email.</div>' +
                  '<a class="hawc-contact-btn" href="' + buildSupportMailto() + '">Contact now</a>' +
                  '<a href="#" id="hawcmox-uninstall-btn" style="color: #e5484d; font-size: 12px; margin-top: 10px; text-decoration: underline; cursor: pointer;">Uninstall HAWCMOX Theme</a>' +
                '</div>';
                el.setAttribute('data-hawc-card', 'done');

                // Attach Uninstaller Click Event
                var uninstallBtn = el.querySelector('#hawcmox-uninstall-btn');
                if (uninstallBtn) {
                    uninstallBtn.addEventListener('click', function(e) {
                        e.preventDefault();
                        if (typeof Ext !== 'undefined' && Ext.Msg) {
                            Ext.Msg.confirm('Uninstall HAWCMOX Theme', 'Are you sure you want to completely remove the HAWCMOX theme and revert to the original Proxmox design?', function(btnResult) {
                                if (btnResult === 'yes') {
                                    Ext.Msg.show({
                                        title: 'Action Required',
                                        message: 'For security reasons, themes must be uninstalled via the host shell. <br><br>Please open your Node Shell and run:<br><br><div style="background:#1b1f26; padding:10px; border-radius:6px; color:#e6e9ee; font-family:monospace; user-select:all; border:1px solid #363e4a;">hawcmox-uninstall</div><br>This command will automatically download the original Proxmox logos and remove all theme files.',
                                        buttons: Ext.Msg.OK,
                                        icon: Ext.Msg.WARNING
                                    });
                                }
                            });
                        }
                    });
                }
            }
        }

        // 5. Replace "Documentation" header button with "Support" button correctly
        var docSpans = document.querySelectorAll('.x-btn-inner');
        for (var s = 0; s < docSpans.length; s++) {
            if (docSpans[s].textContent.trim() === 'Documentation') {
                var docBtn = docSpans[s].closest('.x-btn');
                if (docBtn && docBtn.getAttribute('data-hawc-support') !== 'done') {
                    
                    // Hide original documentation button smoothly
                    docBtn.style.setProperty('display', 'none', 'important');
                    docBtn.setAttribute('data-hawc-support', 'done');
                    
                    // Inject an identically styled standalone HTML anchor
                    var a = document.createElement('a');
                    a.id = 'hawc-support-btn';
                    a.href = '#v1:0:18:=pveDcSupport:::::::27';
                    a.className = docBtn.className;
                    a.style.cssText = docBtn.style.cssText;
                    a.style.setProperty('display', 'inline-flex', 'important');
                    a.style.setProperty('align-items', 'center', 'important');
                    a.style.setProperty('text-decoration', 'none', 'important');
                    
                    // Matches the exact gap between Create VM & CT
                    a.style.setProperty('margin-right', '10px', 'important');
                    a.style.setProperty('padding', '2px 8px', 'important');
                    
                    a.innerHTML = '<span class="x-btn-wrap" style="display:flex; align-items:center; gap:6px; height: 100%;"><span class="x-btn-icon-el fa fa-life-ring" style="color:#ffffff;"></span><span class="x-btn-inner" style="color:#ffffff; font-size:12px;">Support</span></span>';
                    
                    // Bind explicit click event to ensure Hash Routing natively triggers ExtJS
                    a.addEventListener('click', function(e) {
                        e.preventDefault();
                        window.location.hash = '#v1:0:18:=pveDcSupport:::::::27';
                    });
                    
                    docBtn.parentNode.insertBefore(a, docBtn);
                }
                break;
            }
        }
    }

    var throttleTimeout;
    var observer = new MutationObserver(function() {
        if (throttleTimeout) return;
        throttleTimeout = setTimeout(function() {
            updateUI();
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

    printf '%s\n%s\n' "$BRAND_TITLE" "$HIDE_NAG" > "$CONFIG_FILE"

    printf '[5/8] Creating persistent patcher...\n'
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

SUBLIB_FILE="/usr/share/javascript/proxmox-widget-toolkit/js/proxmoxlib.js"
SUBLIB_BACKUP="$DATA_DIR/proxmoxlib.js.orig"

BRAND_TITLE="HAWCMOX"
HIDE_NAG="yes"
if [ -s "$CONFIG_FILE" ]; then
    BRAND_TITLE="$(sed -n '1p' "$CONFIG_FILE")"
    HIDE_NAG="$(sed -n '2p' "$CONFIG_FILE")"
    [ -z "$BRAND_TITLE" ] && BRAND_TITLE="HAWCMOX"
    [ -z "$HIDE_NAG" ] && HIDE_NAG="yes"
fi

escape_sed_replacement() {
    printf '%s' "$1" | sed 's/[\/&|\\]/\\&/g'
}

if [ -f "$TARGET_LOGO_PWT" ] && [ ! -f "$TARGET_LOGO_PWT_BACKUP" ]; then
    cp -f "$TARGET_LOGO_PWT" "$TARGET_LOGO_PWT_BACKUP" 2>/dev/null || true
fi

if [ -f "$SOURCE_LOGO" ]; then
    if [ -d "$(dirname "$TARGET_LOGO_PWT")" ]; then
        cp -f "$SOURCE_LOGO" "$TARGET_LOGO_PWT" && chmod 644 "$TARGET_LOGO_PWT"
    fi
    if [ -f "$TARGET_LOGO_PVE" ]; then
        cp -f "$SOURCE_LOGO" "$TARGET_LOGO_PVE" 2>/dev/null || true
    fi
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

if [ -f "$SUBLIB_FILE" ]; then
    if [ ! -f "$SUBLIB_BACKUP" ]; then
        cp -f "$SUBLIB_FILE" "$SUBLIB_BACKUP" 2>/dev/null || true
    fi

    if [ "$HIDE_NAG" = "yes" ]; then
        if [ -f "$SUBLIB_BACKUP" ]; then
            cp -f "$SUBLIB_BACKUP" "$SUBLIB_FILE"
        fi
        sed -i "s/res === null || res === undefined || \!res || res.data.status.toLowerCase() !== 'active'/false/g" "$SUBLIB_FILE" 2>/dev/null || true
        sed -i "s/res === null || res === undefined || \!res || res/false/g" "$SUBLIB_FILE" 2>/dev/null || true
    else
        if [ -f "$SUBLIB_BACKUP" ]; then
            cp -f "$SUBLIB_BACKUP" "$SUBLIB_FILE"
        fi
    fi
fi

if command -v systemctl >/dev/null 2>&1; then
    systemctl restart pveproxy.service >/dev/null 2>&1 || true
fi
EOF_PATCH
    chmod 755 "$PATCH_SCRIPT"

    printf '[6/8] Creating uninstaller utility...\n'
    cat > "$UNINSTALL_SCRIPT" <<'EOF_UNINSTALL'
#!/bin/sh
set -eu
printf '\n============================================================\n'
printf ' HAWCMOX UNINSTALLER\n'
printf '============================================================\n'

SUBLIB_FILE="/usr/share/javascript/proxmox-widget-toolkit/js/proxmoxlib.js"
SUBLIB_BACKUP="/usr/local/share/hawcmox/proxmoxlib.js.orig"

printf '[1/4] Restoring proxmoxlib.js (subscription check) if patched...\n'
if [ -f "$SUBLIB_BACKUP" ] && [ -f "$SUBLIB_FILE" ]; then
    cp -f "$SUBLIB_BACKUP" "$SUBLIB_FILE" 2>/dev/null || true
fi

printf '[2/4] Removing HAWCMOX files and APT hooks...\n'
rm -rf "/usr/local/share/hawcmox"
rm -f "/usr/local/bin/hawcmox-patch.sh"
rm -f "/usr/local/bin/hawcmox-uninstall"
rm -f "/etc/apt/apt.conf.d/99hawcmox-theme"
rm -f "/usr/share/pve-manager/css/hawcmox.css"
rm -f "/usr/share/pve-manager/js/hawcmox.js"

printf '[3/4] Restoring original Proxmox HTML templates, logo and widget toolkit...\n'
export DEBIAN_FRONTEND=noninteractive
apt-get update >/dev/null 2>&1 || true
apt-get install --reinstall pve-manager proxmox-widget-toolkit -y >/dev/null 2>&1

printf '[4/4] Restarting Proxmox web interface...\n'
if command -v systemctl >/dev/null 2>&1; then
    systemctl restart pveproxy.service >/dev/null 2>&1 || true
fi

printf '\n============================================================\n'
printf ' REVERT COMPLETE\n'
printf ' Open Proxmox in an Incognito window to see the default UI.\n'
printf '============================================================\n\n'
EOF_UNINSTALL
    chmod 755 "$UNINSTALL_SCRIPT"

    printf '[7/8] Applying customization...\n'
    if [ "$INSTALL_APT_HOOK" = "yes" ]; then
        cat > "$APT_HOOK" <<'EOF_HOOK'
DPkg::Post-Invoke { "/usr/local/bin/hawcmox-patch.sh || true"; };
EOF_HOOK
        chmod 644 "$APT_HOOK"
    else
        rm -f "$APT_HOOK"
    fi

    "$PATCH_SCRIPT"

    printf '[8/8] Done.\n'
    printf '\n============================================================\n'
    printf ' HAWCMOX INSTALLATION COMPLETE\n'
    printf '============================================================\n\n'
    printf 'IMPORTANT: The backend service has been reloaded.\n'
    printf 'Open Proxmox in a brand new Incognito/Private window to bypass your cache and see the changes.\n'
}

uninstall_theme() {
    if [ -x "$UNINSTALL_SCRIPT" ]; then
        "$UNINSTALL_SCRIPT"
    else
        printf 'Uninstall script not found. Please re-run the installer and select Install first to generate it.\n'
        exit 1
    fi
}

printf '\n============================================================\n'
printf ' HAWCMOX UI MANAGER\n'
printf '============================================================\n'
printf ' 1) Install / Update HAWCMOX Theme\n'
printf ' 2) Remove HAWCMOX Theme (Restore Default)\n'
printf ' 3) Exit\n'
printf '============================================================\n'
printf 'Select an option [1-3]: '

read -r choice || choice=""
[ -z "$choice" ] && choice="1"

case "$choice" in
    1) install_theme ;;
    2) uninstall_theme ;;
    3) exit 0 ;;
    *) printf 'Invalid choice. Exiting.\n'; exit 1 ;;
esac
