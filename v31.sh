#!/bin/sh

# HAWCMOX Proxmox UI Manager v6.5 - Safer Proxmox 8/9 theme installer
# - Fixes broken Tasks/Create popup behavior
# - Keeps global search bar intact
# - Reuses native header button for Support
# - Adds GUI uninstall flow with confirm popup + backend helper

set -eu

DATA_DIR="/usr/local/share/hawcmox"
PATCH_SCRIPT="/usr/local/bin/hawcmox-patch.sh"
UNINSTALL_SCRIPT="/usr/local/bin/hawcmox-uninstall.sh"
HELPER_SCRIPT="/usr/local/bin/hawcmox-helper.py"
HELPER_SERVICE="/etc/systemd/system/hawcmox-helper.service"
APT_HOOK="/etc/apt/apt.conf.d/99hawcmox-theme"

LOGO_RAW_FILE="$DATA_DIR/hawcmox_logo.raw"
LOGO_SVG_FILE="$DATA_DIR/hawcmox_logo.svg"
CSS_FILE="$DATA_DIR/hawcmox.css"
JS_FILE="$DATA_DIR/hawcmox.js"
CONFIG_FILE="$DATA_DIR/config"
TOKEN_FILE="$DATA_DIR/uninstall.token"

SUBLIB_FILE="/usr/share/javascript/proxmox-widget-toolkit/js/proxmoxlib.js"
SUBLIB_BACKUP="$DATA_DIR/proxmoxlib.js.orig"

TEMPLATE_FILE="/usr/share/pve-manager/index.html.tpl"
TEMPLATE_BACKUP="$DATA_DIR/index.html.tpl.orig"

TARGET_LOGO_PWT="/usr/share/javascript/proxmox-widget-toolkit/images/proxmox_logo.svg"
TARGET_LOGO_PWT_BACKUP="$DATA_DIR/proxmox_logo.svg.orig"

SUPPORT_HASH="v1:0:18:=pveDcSupport:::::::27"
HELPER_PORT="18443"

UNINSTALL_TOKEN=""

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

random_token() {
    if command -v openssl >/dev/null 2>&1; then
        openssl rand -hex 32
    else
        od -An -N32 -tx1 /dev/urandom | tr -d ' \n'
    fi
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

write_css() {
    cat > "$CSS_FILE" <<'EOF_CSS'
/* HAWCMOX - Safer Modern Slate Proxmox Theme */

:root {
    --hawc-bg:            #1b1f26;
    --hawc-panel:         #242a33;
    --hawc-panel-alt:     #2b323d;
    --hawc-border:        #363e4a;
    --hawc-text:          #e6e9ee;
    --hawc-text-dim:      #a4acb8;
    --hawc-accent:        #5b6472;
    --hawc-accent-hov:    #6d7788;
    --hawc-nav-hover:     #24476b;
    --hawc-nav-active:    #2f6ea1;
    --hawc-nav-active-text:#ffffff;
    --hawc-warn:          #eab308;
    --hawc-warn-text:     #1b1f26;
    --hawc-danger:        #e5484d;
    --hawc-danger-text:   #ffffff;
    --hawc-dark-btn:      #14171c;
    --hawc-dark-text:     #e6e9ee;
    --hawc-create:        #2f6f55;
    --hawc-create-border: #3f8f70;
    --hawc-create-text:   #e6e9ee;
    --hawc-radius:        10px;
    --hawc-radius-sm:     6px;
}

html, body, .x-viewport, .x-body {
    background: var(--hawc-bg) !important;
    color: var(--hawc-text) !important;
}

/* Safe panel styling: no hardcoded positioning, no overflow hacks */
.x-panel,
.x-panel-default,
.x-window,
.x-window-default {
    background: var(--hawc-panel) !important;
    background-image: none !important;
    color: var(--hawc-text) !important;
}

.x-panel-default,
.x-window-default {
    border-color: var(--hawc-border) !important;
}

.x-panel-header,
.x-window-header,
.x-panel-header-default,
.x-window-header-default {
    background: var(--hawc-panel-alt) !important;
    background-image: none !important;
    border-color: var(--hawc-border) !important;
    color: var(--hawc-text) !important;
}

.x-panel-body,
.x-panel-body-default,
.x-window-body,
.x-window-body-default {
    background: var(--hawc-panel) !important;
    color: var(--hawc-text) !important;
    border-color: var(--hawc-border) !important;
}

.x-toolbar,
.x-toolbar-default {
    background: var(--hawc-panel-alt) !important;
    background-image: none !important;
    border-color: var(--hawc-border) !important;
}

.x-btn {
    border-radius: var(--hawc-radius-sm) !important;
    transition: background-color 0.15s ease, opacity 0.15s ease !important;
}

.x-btn-default-small,
.x-btn-default-medium,
.x-btn-default-toolbar-small,
.x-btn-default-toolbar-medium {
    background: var(--hawc-panel-alt) !important;
    background-image: none !important;
    border: 1px solid var(--hawc-border) !important;
    color: var(--hawc-text) !important;
}

.x-btn-default-small .x-btn-inner,
.x-btn-default-medium .x-btn-inner,
.x-btn-default-toolbar-small .x-btn-inner,
.x-btn-default-toolbar-medium .x-btn-inner,
.x-btn-icon-el {
    color: #ffffff !important;
}

.x-btn:hover {
    opacity: 0.92 !important;
}

.x-btn-default-small.x-btn-over,
.x-btn-default-medium.x-btn-over,
.x-btn-default-toolbar-small.x-btn-over,
.x-btn-default-toolbar-medium.x-btn-over {
    background: var(--hawc-accent) !important;
    border-color: var(--hawc-accent) !important;
}

.x-btn[data-hawc-action="reboot"] {
    background: var(--hawc-warn) !important;
    border-color: var(--hawc-warn) !important;
    color: var(--hawc-warn-text) !important;
}
.x-btn[data-hawc-action="reboot"] .x-btn-inner {
    color: var(--hawc-warn-text) !important;
}

.x-btn[data-hawc-action="shutdown"],
.x-btn[data-hawc-action="stop"] {
    background: var(--hawc-danger) !important;
    border-color: var(--hawc-danger) !important;
    color: var(--hawc-danger-text) !important;
}
.x-btn[data-hawc-action="shutdown"] .x-btn-inner,
.x-btn[data-hawc-action="stop"] .x-btn-inner {
    color: var(--hawc-danger-text) !important;
}

.x-btn[data-hawc-action="shell"],
.x-btn[data-hawc-action="console"] {
    background: var(--hawc-dark-btn) !important;
    border-color: var(--hawc-dark-btn) !important;
    color: var(--hawc-dark-text) !important;
}
.x-btn[data-hawc-action="shell"] .x-btn-inner,
.x-btn[data-hawc-action="console"] .x-btn-inner {
    color: var(--hawc-dark-text) !important;
}

.x-btn[data-hawc-action="create-vm"],
.x-btn[data-hawc-action="create-ct"] {
    background: var(--hawc-create) !important;
    border-color: var(--hawc-create-border) !important;
    color: var(--hawc-create-text) !important;
}
.x-btn[data-hawc-action="create-vm"] .x-btn-inner,
.x-btn[data-hawc-action="create-ct"] .x-btn-inner {
    color: var(--hawc-create-text) !important;
}

.x-btn[data-hawc-hide="system-report"] {
    display: none !important;
}

.x-form-text,
.x-form-text-default,
.x-form-field,
.x-form-text-wrap,
.x-form-trigger-wrap,
.x-form-trigger,
.x-form-trigger-default {
    background: var(--hawc-panel-alt) !important;
    border-color: var(--hawc-border) !important;
    color: var(--hawc-text) !important;
    background-image: none !important;
}

.x-form-trigger-wrap-focus,
.x-form-text-focus {
    border-color: var(--hawc-accent) !important;
}

.x-menu,
.x-menu-body,
.x-boundlist {
    background: var(--hawc-bg) !important;
    background-image: none !important;
    border-color: var(--hawc-border) !important;
    color: var(--hawc-text) !important;
}

.x-boundlist-item,
.x-menu-item-text {
    color: var(--hawc-text) !important;
}

.x-boundlist-item-over,
.x-menu-item-active .x-menu-item-link {
    background: var(--hawc-nav-hover) !important;
    color: var(--hawc-nav-active-text) !important;
}

.x-grid-header-ct,
.x-column-header {
    background: var(--hawc-panel-alt) !important;
    color: var(--hawc-text) !important;
    border-color: var(--hawc-border) !important;
    background-image: none !important;
}

.x-grid-row-over .x-grid-cell,
.x-grid-row:hover .x-grid-cell {
    background: var(--hawc-panel-alt) !important;
}

.x-grid-row-selected .x-grid-cell,
.x-grid-item-selected .x-grid-cell {
    background: rgba(255,255,255,0.08) !important;
}

.x-tab,
.x-tab-default {
    background: var(--hawc-panel) !important;
    color: var(--hawc-text-dim) !important;
    background-image: none !important;
}

.x-tab-over,
.x-tab:hover {
    background: var(--hawc-nav-hover) !important;
    color: var(--hawc-nav-active-text) !important;
}

.x-tab-active,
.x-tab-active.x-tab-default {
    background: var(--hawc-nav-active) !important;
    color: var(--hawc-nav-active-text) !important;
}

.x-tab-active .x-tab-inner,
.x-tab-over .x-tab-inner,
.x-tab:hover .x-tab-inner {
    color: var(--hawc-nav-active-text) !important;
}

.x-treelist,
.x-treelist-root-container,
.x-treelist-container,
.x-treelist-row,
.x-treelist-item-wrap,
.x-treelist-item,
.x-treelist-toolstrip {
    background: var(--hawc-panel-alt) !important;
    color: var(--hawc-text) !important;
}

.x-treelist .x-treelist-item:hover > .x-treelist-row,
.x-treelist .x-treelist-row:hover {
    background: var(--hawc-nav-hover) !important;
    color: var(--hawc-nav-active-text) !important;
}

.x-treelist .x-treelist-item-selected > .x-treelist-row,
.x-treelist .x-treelist-item-selected > .x-treelist-row .x-treelist-item-text,
.x-treelist .x-treelist-item-selected > .x-treelist-row .x-treelist-item-icon {
    background: var(--hawc-nav-active) !important;
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
    background: var(--hawc-panel-alt) !important;
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
    min-height: 34px !important;
    padding: 8px 14px !important;
    background: var(--hawc-nav-active) !important;
    border: 1px solid var(--hawc-nav-active) !important;
    border-radius: var(--hawc-radius-sm) !important;
    color: #ffffff !important;
    text-decoration: none !important;
    cursor: pointer !important;
    box-sizing: border-box !important;
}

.hawc-contact-btn:hover {
    background: var(--hawc-nav-hover) !important;
    border-color: var(--hawc-nav-hover) !important;
    color: #ffffff !important;
}

.hawc-uninstall-link {
    font-size: 12px !important;
    color: var(--hawc-text-dim) !important;
    text-decoration: none !important;
    margin-top: -2px !important;
}

.hawc-uninstall-link:hover {
    color: #ffffff !important;
    text-decoration: underline !important;
}

img[src*="proxmox_logo"] {
    object-fit: contain !important;
    max-height: 52px !important;
    width: auto !important;
    filter: none !important;
    -webkit-filter: none !important;
    mix-blend-mode: normal !important;
    opacity: 1 !important;
}

.pmx-hint {
    display: none !important;
}
EOF_CSS
    chmod 644 "$CSS_FILE"
}

write_js() {
    cat > "$JS_FILE" <<'EOF_JS'
(function () {
    var SUPPORT_HASH = '__SUPPORT_HASH__';
    var UNINSTALL_PORT = '__HELPER_PORT__';
    var UNINSTALL_TOKEN = '__UNINSTALL_TOKEN__';
    var MANUAL_UNINSTALL_CMD = '/usr/local/bin/hawcmox-uninstall.sh';
    var throttleTimer = null;

    function buildSupportMailto() {
        return 'mailto:support@hawc.be?subject=' + encodeURIComponent('HAWCMOX Support Request') +
            '&body=' + encodeURIComponent('Hello HAWC Support,\n\nI need help with HAWCMOX.\n\nServer: \nIssue: \nPreferred contact name: \n\nThanks,');
    }

    function helperUrl() {
        var u = new URL(window.location.origin);
        u.port = UNINSTALL_PORT;
        u.pathname = '/uninstall';
        u.search = '';
        u.hash = '';
        return u.toString();
    }

    function navigateSupport() {
        try {
            if (window.Ext && Ext.util && Ext.util.History && typeof Ext.util.History.add === 'function') {
                Ext.util.History.add(SUPPORT_HASH);
            }
        } catch (e) {}

        try {
            if (window.location.hash !== '#' + SUPPORT_HASH) {
                window.location.hash = '#' + SUPPORT_HASH;
            } else {
                window.dispatchEvent(new Event('hashchange'));
            }
        } catch (e) {
            window.location.hash = '#' + SUPPORT_HASH;
        }
    }

    function showMessage(title, msg) {
        if (window.Ext && Ext.Msg && typeof Ext.Msg.alert === 'function') {
            Ext.Msg.alert(title, msg);
        } else {
            window.alert(msg);
        }
    }

    function triggerUninstall() {
        fetch(helperUrl(), {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json',
                'X-HAWCMOX-Token': UNINSTALL_TOKEN
            },
            body: '{}'
        })
        .then(function (res) {
            if (!res.ok) {
                throw new Error('HTTP ' + res.status);
            }
            return res.json().catch(function () { return {}; });
        })
        .then(function () {
            showMessage('HAWCMOX', 'Uninstall started. The original Proxmox UI will be restored and this page will stop working for a few seconds while pveproxy reloads.');
            setTimeout(function () {
                window.location.reload();
            }, 5000);
        })
        .catch(function () {
            showMessage('HAWCMOX', 'Automatic uninstall could not be reached. Run this on the node instead:\n\n' + MANUAL_UNINSTALL_CMD);
        });
    }

    function confirmUninstall() {
        var text = 'Are you sure you want to uninstall HAWCMOX Theme and restore the original Proxmox interface?';
        if (window.Ext && Ext.Msg && typeof Ext.Msg.confirm === 'function') {
            Ext.Msg.confirm('Uninstall HAWCMOX Theme', text, function (btn) {
                if (btn === 'yes') {
                    triggerUninstall();
                }
            });
        } else if (window.confirm(text)) {
            triggerUninstall();
        }
    }

    function patchVersionText() {
        var versionContainer = document.querySelector('#versioninfo .x-autocontainer-innerCt');
        if (versionContainer && !versionContainer.getAttribute('data-hawc-version')) {
            versionContainer.textContent = versionContainer.textContent.replace(/Virtual Environment\s*([\d.]+)/i, 'VE v$1');
            versionContainer.setAttribute('data-hawc-version', 'done');
        }
    }

    function tagButtons() {
        var btns = document.querySelectorAll('.x-btn');
        for (var i = 0; i < btns.length; i++) {
            var btn = btns[i];
            var text = (btn.textContent || btn.getAttribute('data-qtip') || '').replace(/\s+/g, ' ').trim().toLowerCase();

            if (text === 'create vm') btn.setAttribute('data-hawc-action', 'create-vm');
            else if (text === 'create ct') btn.setAttribute('data-hawc-action', 'create-ct');
            else if (text === 'reboot') btn.setAttribute('data-hawc-action', 'reboot');
            else if (text === 'shutdown') btn.setAttribute('data-hawc-action', 'shutdown');
            else if (text === 'stop') btn.setAttribute('data-hawc-action', 'stop');
            else if (text === 'console' || text === 'shell' || text === '>_ console') btn.setAttribute('data-hawc-action', 'console');
            else if (text === 'system report') btn.setAttribute('data-hawc-hide', 'system-report');
        }
    }

    function autoCloseSubscriptionNag() {
        var wins = document.querySelectorAll('.x-window, .x-message-box');
        for (var i = 0; i < wins.length; i++) {
            if (/no valid subscription/i.test(wins[i].textContent || '')) {
                var btn = wins[i].querySelector('.x-btn');
                if (btn) {
                    btn.click();
                }
            }
        }
    }

    function patchSupportPanel() {
        var targets = document.querySelectorAll('[id^="pveDcSupport-"] .x-autocontainer-innerCt, [id^="pveDcSupport-"] .x-panel-body');
        for (var i = 0; i < targets.length; i++) {
            var el = targets[i];
            if (el.getAttribute('data-hawc-card') === 'done') {
                continue;
            }

            if (!el.closest('[id^="pveDcSupport-"]')) {
                continue;
            }

            var txt = (el.textContent || '').replace(/\s+/g, ' ').trim();
            if (/No valid subscription/i.test(txt) || txt.length > 0) {
                el.innerHTML = '' +
                    '<div class="hawc-subscription-card">' +
                        '<div class="hawc-card-title">HAWCMOX Support</div>' +
                        '<div class="hawc-card-text">Contact info: <a class="hawc-subscription-link" href="mailto:support@hawc.be">support@hawc.be</a></div>' +
                        '<div class="hawc-card-text">Use the button below to open a prefilled HAWCMOX support email.</div>' +
                        '<a class="hawc-contact-btn" href="' + buildSupportMailto() + '">Contact now</a>' +
                        '<a class="hawc-uninstall-link" href="#" title="Uninstall HAWCMOX Theme">Uninstall HAWCMOX Theme</a>' +
                    '</div>';
                el.setAttribute('data-hawc-card', 'done');
            }
        }
    }

    function patchHeaderSupportButton() {
        var btns = document.querySelectorAll('.x-btn');
        for (var i = 0; i < btns.length; i++) {
            var btn = btns[i];
            var labelEl = btn.querySelector('.x-btn-inner');
            var label = labelEl ? (labelEl.textContent || '').replace(/\s+/g, ' ').trim() : '';
            var done = btn.getAttribute('data-hawc-support') === 'done';

            if (done || label === 'Documentation' || label === 'Support') {
                btn.setAttribute('data-hawc-support', 'done');
                btn.setAttribute('data-qtip', 'Support');

                if (labelEl) {
                    labelEl.textContent = 'Support';
                }

                var icon = btn.querySelector('.x-btn-icon-el');
                if (icon) {
                    icon.className = icon.className
                        .replace(/\bfa-[a-z0-9-]+\b/g, '')
                        .replace(/\s+/g, ' ')
                        .trim() + ' fa fa-life-ring';
                }

                if (!btn.getAttribute('data-hawc-support-bound')) {
                    btn.addEventListener('click', function (e) {
                        e.preventDefault();
                        e.stopPropagation();
                        navigateSupport();
                    }, true);

                    btn.addEventListener('mousedown', function (e) {
                        e.stopPropagation();
                    }, true);

                    btn.setAttribute('data-hawc-support-bound', 'done');
                }
                return;
            }
        }
    }

    function refreshUI() {
        patchVersionText();
        tagButtons();
        autoCloseSubscriptionNag();
        patchSupportPanel();
        patchHeaderSupportButton();
    }

    document.addEventListener('click', function (e) {
        var uninstallLink = e.target.closest('.hawc-uninstall-link');
        if (uninstallLink) {
            e.preventDefault();
            confirmUninstall();
            return;
        }

        var supportBtn = e.target.closest('.x-btn[data-hawc-support="done"]');
        if (supportBtn) {
            e.preventDefault();
            e.stopPropagation();
            navigateSupport();
        }
    }, true);

    function scheduleRefresh() {
        if (throttleTimer) return;
        throttleTimer = setTimeout(function () {
            throttleTimer = null;
            refreshUI();
        }, 60);
    }

    document.addEventListener('DOMContentLoaded', function () {
        refreshUI();
        if (document.body) {
            new MutationObserver(scheduleRefresh).observe(document.body, { childList: true, subtree: true });
        }
    });

    if (document.readyState === 'interactive' || document.readyState === 'complete') {
        refreshUI();
        if (document.body) {
            new MutationObserver(scheduleRefresh).observe(document.body, { childList: true, subtree: true });
        }
    }
})();
EOF_JS

    sed -i "s|__SUPPORT_HASH__|$SUPPORT_HASH|g" "$JS_FILE"
    sed -i "s|__HELPER_PORT__|$HELPER_PORT|g" "$JS_FILE"
    sed -i "s|__UNINSTALL_TOKEN__|$UNINSTALL_TOKEN|g" "$JS_FILE"
    chmod 644 "$JS_FILE"
}

write_helper_script() {
    cat > "$HELPER_SCRIPT" <<'EOF_PY'
#!/usr/bin/env python3
import json
import os
import ssl
import subprocess
from http.server import BaseHTTPRequestHandler, HTTPServer

PORT = int("__HELPER_PORT__")
TOKEN_FILE = "__TOKEN_FILE__"
UNINSTALL_SCRIPT = "__UNINSTALL_SCRIPT__"
CERT_FILE = "/etc/pve/local/pve-ssl.pem"
KEY_FILE = "/etc/pve/local/pve-ssl.key"

def read_token():
    try:
        with open(TOKEN_FILE, "r", encoding="utf-8") as fh:
            return fh.read().strip()
    except Exception:
        return ""

class Handler(BaseHTTPRequestHandler):
    def end_json(self, code, payload):
        body = json.dumps(payload).encode("utf-8")
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Headers", "Content-Type, X-HAWCMOX-Token")
        self.send_header("Access-Control-Allow-Methods", "POST, OPTIONS")
        self.end_headers()
        self.wfile.write(body)

    def do_OPTIONS(self):
        self.send_response(204)
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Headers", "Content-Type, X-HAWCMOX-Token")
        self.send_header("Access-Control-Allow-Methods", "POST, OPTIONS")
        self.end_headers()

    def do_POST(self):
        if self.path != "/uninstall":
            self.end_json(404, {"ok": False, "error": "not-found"})
            return

        token = self.headers.get("X-HAWCMOX-Token", "")
        if not token or token != read_token():
            self.end_json(403, {"ok": False, "error": "forbidden"})
            return

        subprocess.Popen(
            ["/bin/sh", "-c", "sleep 1; exec \"$1\"", "sh", UNINSTALL_SCRIPT],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            start_new_session=True,
        )
        self.end_json(202, {"ok": True})

    def log_message(self, fmt, *args):
        return

def main():
    if not os.path.exists(CERT_FILE) or not os.path.exists(KEY_FILE):
        raise SystemExit("missing certificate")
    httpd = HTTPServer(("0.0.0.0", PORT), Handler)
    ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
    ctx.load_cert_chain(CERT_FILE, KEY_FILE)
    httpd.socket = ctx.wrap_socket(httpd.socket, server_side=True)
    httpd.serve_forever()

if __name__ == "__main__":
    main()
EOF_PY

    sed -i "s|__HELPER_PORT__|$HELPER_PORT|g" "$HELPER_SCRIPT"
    sed -i "s|__TOKEN_FILE__|$TOKEN_FILE|g" "$HELPER_SCRIPT"
    sed -i "s|__UNINSTALL_SCRIPT__|$UNINSTALL_SCRIPT|g" "$HELPER_SCRIPT"
    chmod 755 "$HELPER_SCRIPT"
}

write_helper_service() {
    cat > "$HELPER_SERVICE" <<EOF_SERVICE
[Unit]
Description=HAWCMOX uninstall helper
After=network-online.target pveproxy.service
Wants=network-online.target

[Service]
Type=simple
ExecStart=/usr/bin/python3 $HELPER_SCRIPT
Restart=always
RestartSec=2

[Install]
WantedBy=multi-user.target
EOF_SERVICE
    chmod 644 "$HELPER_SERVICE"
}

write_patch_script() {
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

TARGET_CSS="/usr/share/pve-manager/css/hawcmox.css"
TARGET_JS="/usr/share/pve-manager/js/hawcmox.js"
TEMPLATE_FILE="/usr/share/pve-manager/index.html.tpl"
TEMPLATE_BACKUP="$DATA_DIR/index.html.tpl.orig"

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

if [ -f "$TEMPLATE_FILE" ] && [ ! -f "$TEMPLATE_BACKUP" ]; then
    cp -f "$TEMPLATE_FILE" "$TEMPLATE_BACKUP" 2>/dev/null || true
fi

if [ -f "$TEMPLATE_BACKUP" ] && [ -f "$TEMPLATE_FILE" ]; then
    cp -f "$TEMPLATE_BACKUP" "$TEMPLATE_FILE"
fi

if [ -f "$SOURCE_LOGO" ] && [ -d "$(dirname "$TARGET_LOGO_PWT")" ]; then
    cp -f "$SOURCE_LOGO" "$TARGET_LOGO_PWT"
    chmod 644 "$TARGET_LOGO_PWT"
fi

if [ -f "$SOURCE_CSS" ]; then
    cp -f "$SOURCE_CSS" "$TARGET_CSS"
    chmod 644 "$TARGET_CSS"
fi

if [ -f "$SOURCE_JS" ]; then
    cp -f "$SOURCE_JS" "$TARGET_JS"
    chmod 644 "$TARGET_JS"
fi

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
}

write_uninstall_script() {
    cat > "$UNINSTALL_SCRIPT" <<EOF_UNINSTALL
#!/bin/sh
set -eu

DATA_DIR="$DATA_DIR"
PATCH_SCRIPT="$PATCH_SCRIPT"
UNINSTALL_SCRIPT="$UNINSTALL_SCRIPT"
HELPER_SCRIPT="$HELPER_SCRIPT"
HELPER_SERVICE="$HELPER_SERVICE"
APT_HOOK="$APT_HOOK"

SUBLIB_FILE="$SUBLIB_FILE"
SUBLIB_BACKUP="$SUBLIB_BACKUP"

TEMPLATE_FILE="$TEMPLATE_FILE"
TEMPLATE_BACKUP="$TEMPLATE_BACKUP"

TARGET_LOGO_PWT="$TARGET_LOGO_PWT"
TARGET_LOGO_PWT_BACKUP="$TARGET_LOGO_PWT_BACKUP"

TARGET_CSS="/usr/share/pve-manager/css/hawcmox.css"
TARGET_JS="/usr/share/pve-manager/js/hawcmox.js"

if [ -f "\$SUBLIB_BACKUP" ] && [ -f "\$SUBLIB_FILE" ]; then
    cp -f "\$SUBLIB_BACKUP" "\$SUBLIB_FILE" 2>/dev/null || true
fi

if [ -f "\$TEMPLATE_BACKUP" ] && [ -f "\$TEMPLATE_FILE" ]; then
    cp -f "\$TEMPLATE_BACKUP" "\$TEMPLATE_FILE" 2>/dev/null || true
fi

if [ -f "\$TARGET_LOGO_PWT_BACKUP" ] && [ -f "\$TARGET_LOGO_PWT" ]; then
    cp -f "\$TARGET_LOGO_PWT_BACKUP" "\$TARGET_LOGO_PWT" 2>/dev/null || true
fi

rm -f "\$APT_HOOK"
rm -f "\$TARGET_CSS"
rm -f "\$TARGET_JS"

if command -v systemctl >/dev/null 2>&1; then
    systemctl disable --now "$(basename "$HELPER_SERVICE")" >/dev/null 2>&1 || true
fi

rm -f "$HELPER_SERVICE"
rm -f "$HELPER_SCRIPT"

export DEBIAN_FRONTEND=noninteractive
apt-get install --reinstall pve-manager proxmox-widget-toolkit -y >/dev/null 2>&1 || true

if command -v systemctl >/dev/null 2>&1; then
    systemctl daemon-reload >/dev/null 2>&1 || true
    systemctl restart pveproxy.service >/dev/null 2>&1 || true
fi

rm -f "$PATCH_SCRIPT"
rm -f "$UNINSTALL_SCRIPT"
rm -rf "$DATA_DIR"
EOF_UNINSTALL
    chmod 755 "$UNINSTALL_SCRIPT"
}

install_theme() {
    printf '\n============================================================\n'
    printf ' HAWCMOX INSTALLER\n'
    printf '============================================================\n'

    BRAND_TITLE="HAWCMOX"
    LOGO_URL="https://raw.githubusercontent.com/HeyvaertSeppe/hawcmox-theme/main/proxmox_logo.png"
    INSTALL_APT_HOOK="yes"
    HIDE_NAG="yes"

    if ! command -v python3 >/dev/null 2>&1; then
        printf '%s\n' "ERROR: python3 is required for the GUI uninstall helper."
        exit 1
    fi

    printf '\n[1/8] Creating directories...\n'
    mkdir -p "$DATA_DIR"
    chmod 755 "$DATA_DIR"

    printf '[2/8] Generating uninstall token...\n'
    UNINSTALL_TOKEN="$(random_token)"
    printf '%s\n' "$UNINSTALL_TOKEN" > "$TOKEN_FILE"
    chmod 600 "$TOKEN_FILE"

    printf '[3/8] Downloading and preparing custom logo...\n'
    download_file "$LOGO_URL" "$LOGO_RAW_FILE"
    prepare_logo_svg "$LOGO_RAW_FILE" "$LOGO_SVG_FILE"
    rm -f "$LOGO_RAW_FILE"
    chmod 644 "$LOGO_SVG_FILE"

    printf '[4/8] Generating safe CSS theme...\n'
    write_css

    printf '[5/8] Generating UI patcher assets...\n'
    write_js
    printf '%s\n%s\n' "$BRAND_TITLE" "$HIDE_NAG" > "$CONFIG_FILE"
    chmod 644 "$CONFIG_FILE"

    printf '[6/8] Generating patch, uninstall and helper services...\n'
    write_patch_script
    write_uninstall_script
    write_helper_script
    write_helper_service

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

    if command -v systemctl >/dev/null 2>&1; then
        systemctl daemon-reload >/dev/null 2>&1 || true
        systemctl enable --now "$(basename "$HELPER_SERVICE")" >/dev/null 2>&1 || true
    fi

    printf '[8/8] Done.\n'
    printf '\n============================================================\n'
    printf ' HAWCMOX INSTALLATION COMPLETE\n'
    printf '============================================================\n\n'
    printf 'IMPORTANT: Open Proxmox in a brand new Incognito/Private window to bypass cache.\n'
    printf 'The Support button now routes to: #%s\n' "$SUPPORT_HASH"
    printf 'GUI uninstall helper listens on HTTPS port %s.\n' "$HELPER_PORT"
}

uninstall_theme() {
    printf '\n============================================================\n'
    printf ' HAWCMOX UNINSTALLER\n'
    printf '============================================================\n'
    "$UNINSTALL_SCRIPT"
    printf '\n============================================================\n'
    printf ' REVERT COMPLETE\n'
    printf '============================================================\n\n'
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
    2)
        if [ -x "$UNINSTALL_SCRIPT" ]; then
            uninstall_theme
        else
            printf '%s\n' "ERROR: No installed HAWCMOX uninstall script found."
            exit 1
        fi
        ;;
    3) exit 0 ;;
    *) printf 'Invalid choice. Exiting.\n'; exit 1 ;;
esac
