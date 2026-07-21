#!/bin/sh
#
# HAWCMOX Proxmox UI Manager v6.5
# Safe theme customisation for Proxmox VE 8+ / 9+
#
# Important design rules:
# - Do not override ExtJS border-layout, splitter, x-box, or panel geometry.
# - Do not replace ExtJS-managed header buttons with unmanaged HTML.
# - Do not modify package-owned proxmoxlib.js.
#

set -eu

DATA_DIR="/usr/local/share/hawcmox"
PATCH_SCRIPT="/usr/local/bin/hawcmox-patch.sh"
APT_HOOK="/etc/apt/apt.conf.d/99hawcmox-theme"

LOGO_RAW_FILE="$DATA_DIR/hawcmox_logo.raw"
LOGO_SVG_FILE="$DATA_DIR/hawcmox_logo.svg"
CSS_FILE="$DATA_DIR/hawcmox.css"
JS_FILE="$DATA_DIR/hawcmox.js"
CONFIG_FILE="$DATA_DIR/config"

TARGET_CSS="/usr/share/pve-manager/css/hawcmox.css"
TARGET_JS="/usr/share/pve-manager/js/hawcmox.js"
TEMPLATE_FILE="/usr/share/pve-manager/index.html.tpl"

TARGET_LOGO_PWT="/usr/share/javascript/proxmox-widget-toolkit/images/proxmox_logo.svg"
TARGET_LOGO_PWT_BACKUP="$DATA_DIR/proxmox_logo.svg.orig"

BRAND_TITLE="HAWCMOX"
LOGO_URL="https://raw.githubusercontent.com/HeyvaertSeppe/hawcmox-theme/main/proxmox_logo.png"
SUPPORT_HASH="#v1:0:18:=pveDcSupport:::::::27"

if [ "$(id -u)" -ne 0 ]; then
    printf '%s\n' "ERROR: Run this script as root."
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
        if ! curl -4 --fail --location --silent --show-error --retry 3 \
            "$url" --output "$temporary_file"; then
            rm -f "$temporary_file"
            printf '%s\n' "ERROR: Download failed: $url"
            exit 1
        fi
    elif command -v wget >/dev/null 2>&1; then
        if ! wget -4 --quiet --tries=3 --output-document="$temporary_file" "$url"; then
            rm -f "$temporary_file"
            printf '%s\n' "ERROR: Download failed: $url"
            exit 1
        fi
    else
        printf '%s\n' "ERROR: curl or wget is required."
        exit 1
    fi

    if [ ! -s "$temporary_file" ]; then
        rm -f "$temporary_file"
        printf '%s\n' "ERROR: Downloaded logo is empty."
        exit 1
    fi

    mv -f "$temporary_file" "$destination"
}

prepare_logo_svg() {
    raw_file="$1"
    output_file="$2"

    if head -c 512 "$raw_file" 2>/dev/null | grep -qi '<svg'; then
        cp -f "$raw_file" "$output_file"
        return 0
    fi

    signature="$(head -c 8 "$raw_file" | od -An -tx1 | tr -d ' \n')"

    if [ "$signature" = "89504e470d0a1a0a" ]; then
        width="$(od -An -tu4 -j 16 -N 4 --endian=big "$raw_file" | tr -d ' ')"
        height="$(od -An -tu4 -j 20 -N 4 --endian=big "$raw_file" | tr -d ' ')"
        mime="image/png"
    else
        width="200"
        height="60"
        mime="image/*"
    fi

    base64_data="$(base64 -w0 "$raw_file" 2>/dev/null || base64 "$raw_file" | tr -d '\n')"

    cat > "$output_file" <<EOF_SVG
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 ${width} ${height}" width="${width}" height="${height}">
  <image width="${width}" height="${height}" preserveAspectRatio="xMidYMid meet" href="data:${mime};base64,${base64_data}"/>
</svg>
EOF_SVG
}

write_css() {
    cat > "$CSS_FILE" <<'EOF_CSS'
/* HAWCMOX v6.5 - Safe Proxmox / ExtJS styling
 *
 * Deliberately excluded:
 * - .x-border-layout-ct changes
 * - .x-splitter changes
 * - .x-box-inner / .x-box-target geometry changes
 * - fixed widths/heights of the resource tree
 * - global panel overflow changes
 * - absolute positioning of header/search controls
 */

:root {
    --hawc-bg: #1b1f26;
    --hawc-panel: #242a33;
    --hawc-panel-alt: #2b323d;
    --hawc-border: #363e4a;
    --hawc-text: #e6e9ee;
    --hawc-text-dim: #a4acb8;
    --hawc-accent: #5b6472;
    --hawc-nav-hover: #24476b;
    --hawc-nav-active: #2f6ea1;
    --hawc-success: #22c55e;
    --hawc-warn: #eab308;
    --hawc-danger: #e5484d;
    --hawc-dark-btn: #14171c;
    --hawc-create: #2f6f55;
    --hawc-create-border: #3f8f70;
    --hawc-radius: 10px;
    --hawc-radius-sm: 6px;
}

html,
body,
.x-viewport,
.x-body {
    background: var(--hawc-bg) !important;
    color: var(--hawc-text) !important;
}

.x-panel,
.x-panel-default {
    background-color: var(--hawc-panel) !important;
    background-image: none !important;
    border-color: var(--hawc-border) !important;
    color: var(--hawc-text) !important;
}

.x-panel-header,
.x-panel-header-default,
.x-window-header,
.x-window-header-default {
    background-color: var(--hawc-panel-alt) !important;
    background-image: none !important;
    border-color: var(--hawc-border) !important;
    color: var(--hawc-text) !important;
}

.x-panel-body,
.x-panel-body-default,
.x-window-body,
.x-window-body-default {
    background-color: var(--hawc-panel) !important;
    color: var(--hawc-text) !important;
}

.x-window,
.x-window-default,
.x-message-box {
    background-color: var(--hawc-panel) !important;
    border-color: var(--hawc-border) !important;
    box-shadow: 0 10px 30px rgba(0, 0, 0, 0.42) !important;
}

/*
 * Do not set overflow here.
 * Task Viewer and wizard windows rely on their generated overflow rules.
 */

.x-toolbar,
.x-toolbar-default,
.x-toolbar-default-docked-top {
    background-color: var(--hawc-panel-alt) !important;
    background-image: none !important;
    border-color: var(--hawc-border) !important;
}

.x-btn {
    border-radius: var(--hawc-radius-sm) !important;
    transition: background-color 0.15s ease, border-color 0.15s ease !important;
}

.x-btn-default-small,
.x-btn-default-medium,
.x-btn-default-toolbar-small,
.x-btn-default-toolbar-medium {
    background-color: var(--hawc-panel-alt) !important;
    border-color: var(--hawc-border) !important;
}

.x-btn-inner,
.x-btn-default-small .x-btn-inner,
.x-btn-default-medium .x-btn-inner,
.x-btn-default-toolbar-small .x-btn-inner,
.x-btn-default-toolbar-medium .x-btn-inner {
    color: var(--hawc-text) !important;
}

.x-btn-over,
.x-btn:hover {
    background-color: var(--hawc-accent) !important;
    border-color: var(--hawc-accent) !important;
}

.x-btn[data-hawc-action="create-vm"],
.x-btn[data-hawc-action="create-ct"] {
    background-color: var(--hawc-create) !important;
    border-color: var(--hawc-create-border) !important;
}

.x-btn[data-hawc-action="reboot"] {
    background-color: var(--hawc-warn) !important;
    border-color: var(--hawc-warn) !important;
}

.x-btn[data-hawc-action="reboot"] .x-btn-inner {
    color: #1b1f26 !important;
}

.x-btn[data-hawc-action="shutdown"],
.x-btn[data-hawc-action="stop"] {
    background-color: var(--hawc-danger) !important;
    border-color: var(--hawc-danger) !important;
}

.x-btn[data-hawc-action="shutdown"] .x-btn-inner,
.x-btn[data-hawc-action="stop"] .x-btn-inner {
    color: #ffffff !important;
}

.x-btn[data-hawc-action="console"],
.x-btn[data-hawc-action="shell"] {
    background-color: var(--hawc-dark-btn) !important;
    border-color: var(--hawc-dark-btn) !important;
}

/*
 * The original Documentation button remains an ExtJS button.
 * No margins are imposed: ExtJS retains the exact same native gap
 * between Support, Create VM and Create CT.
 */
.x-btn[data-hawc-support="true"] {
    background-color: var(--hawc-nav-active) !important;
    border-color: var(--hawc-nav-active) !important;
}

.x-btn[data-hawc-support="true"] .x-btn-inner,
.x-btn[data-hawc-support="true"] .x-btn-icon-el {
    color: #ffffff !important;
}

.x-form-text,
.x-form-text-default,
.x-form-field,
.x-form-trigger-wrap,
.x-form-text-wrap {
    background-color: var(--hawc-panel-alt) !important;
    border-color: var(--hawc-border) !important;
    color: var(--hawc-text) !important;
}

.x-form-trigger-wrap-focus,
.x-form-text-focus {
    border-color: var(--hawc-accent) !important;
}

.x-menu,
.x-menu-body,
.x-boundlist {
    background-color: var(--hawc-panel-alt) !important;
    border-color: var(--hawc-border) !important;
    background-image: none !important;
}

.x-menu-item-active .x-menu-item-link,
.x-menu-item-focus .x-menu-item-link,
.x-boundlist-item-over,
.x-grid-row-over .x-grid-cell,
.x-grid-row:hover .x-grid-cell {
    background-color: var(--hawc-nav-hover) !important;
    color: #ffffff !important;
}

.x-boundlist-selected,
.x-grid-row-selected .x-grid-cell,
.x-grid-item-selected .x-grid-cell {
    background-color: var(--hawc-nav-active) !important;
    color: #ffffff !important;
}

.x-grid-header-ct,
.x-column-header {
    background-color: var(--hawc-panel-alt) !important;
    border-color: var(--hawc-border) !important;
    color: var(--hawc-text) !important;
}

.x-tab {
    background-color: var(--hawc-panel) !important;
    color: var(--hawc-text-dim) !important;
}

.x-tab-over,
.x-tab:hover {
    background-color: var(--hawc-nav-hover) !important;
}

.x-tab-active,
.x-tab-active.x-tab-default {
    background-color: var(--hawc-nav-active) !important;
}

.x-tab-active .x-tab-inner,
.x-tab-over .x-tab-inner,
.x-tab:hover .x-tab-inner {
    color: #ffffff !important;
}

[id^="pveResourceTree-"] .x-grid-row-over .x-grid-cell,
[id^="pveResourceTree-"] .x-grid-row:hover .x-grid-cell {
    background-color: var(--hawc-nav-hover) !important;
    color: #ffffff !important;
}

[id^="pveResourceTree-"] .x-grid-row-selected .x-grid-cell,
[id^="pveResourceTree-"] .x-grid-item-selected .x-grid-cell {
    background-color: var(--hawc-nav-active) !important;
    color: #ffffff !important;
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

/* Logo is constrained without removing it from the normal ExtJS header flow. */
img[src*="proxmox_logo"] {
    object-fit: contain !important;
    max-width: 220px !important;
    max-height: 52px !important;
    filter: none !important;
    -webkit-filter: none !important;
    opacity: 1 !important;
}

.hawc-subscription-card {
    box-sizing: border-box;
    margin: 12px;
    padding: 18px;
    border: 1px solid var(--hawc-border);
    border-radius: var(--hawc-radius);
    background: var(--hawc-panel-alt);
    color: var(--hawc-text);
}

.hawc-card-title {
    margin-bottom: 10px;
    color: #ffffff;
    font-size: 18px;
    font-weight: 600;
}

.hawc-card-text {
    margin-top: 8px;
    color: var(--hawc-text-dim);
    line-height: 1.45;
}

.hawc-subscription-link {
    color: #93c5fd;
}

.hawc-contact-btn {
    display: inline-block;
    margin-top: 14px;
    padding: 8px 14px;
    border: 1px solid var(--hawc-nav-active);
    border-radius: var(--hawc-radius-sm);
    background: var(--hawc-nav-active);
    color: #ffffff;
    text-decoration: none;
}

.hawc-contact-btn:hover {
    background: var(--hawc-nav-hover);
    border-color: var(--hawc-nav-hover);
}
EOF_CSS

    chmod 644 "$CSS_FILE"
}

write_js() {
    cat > "$JS_FILE" <<'EOF_JS'
(function () {
    'use strict';

    var SUPPORT_HASH = '#v1:0:18:=pveDcSupport:::::::27';
    var pending = false;

    function supportMailto() {
        return 'mailto:support@hawc.be?subject=' +
            encodeURIComponent('HAWCMOX Support Request') +
            '&body=' +
            encodeURIComponent(
                'Hello HAWC Support,\n\n' +
                'I need help with HAWCMOX.\n\n' +
                'Server: \n' +
                'Issue: \n' +
                'Preferred contact name: \n\n' +
                'Thanks,'
            );
    }

    function classifyButtons() {
        var buttons = document.querySelectorAll('.x-btn:not([data-hawc-action])');

        for (var i = 0; i < buttons.length; i++) {
            var button = buttons[i];
            var label = (
                button.textContent ||
                button.getAttribute('data-qtip') ||
                ''
            ).replace(/\s+/g, ' ').trim().toLowerCase();

            if (label === 'create vm') {
                button.setAttribute('data-hawc-action', 'create-vm');
            } else if (label === 'create ct') {
                button.setAttribute('data-hawc-action', 'create-ct');
            } else if (label === 'reboot') {
                button.setAttribute('data-hawc-action', 'reboot');
            } else if (label === 'shutdown' || label === 'stop') {
                button.setAttribute('data-hawc-action', 'shutdown');
            } else if (
                label === 'console' ||
                label === 'shell' ||
                label === '>_ console'
            ) {
                button.setAttribute('data-hawc-action', 'console');
            } else {
                button.setAttribute('data-hawc-action', 'none');
            }
        }
    }

    function patchVersionText() {
        var version = document.querySelector(
            '#versioninfo .x-autocontainer-innerCt'
        );

        if (!version || version.getAttribute('data-hawc-version') === 'true') {
            return;
        }

        version.textContent = version.textContent.replace(
            /Virtual Environment\s*([\d.]+)/i,
            'VE v$1'
        );
        version.setAttribute('data-hawc-version', 'true');
    }

    function routeToSupport(event) {
        event.preventDefault();
        event.stopPropagation();

        if (typeof event.stopImmediatePropagation === 'function') {
            event.stopImmediatePropagation();
        }

        if (window.location.hash === SUPPORT_HASH) {
            window.dispatchEvent(new HashChangeEvent('hashchange'));
        } else {
            window.location.hash = SUPPORT_HASH;
        }

        return false;
    }

    function patchDocumentationButton() {
        var labels = document.querySelectorAll('.x-btn-inner');

        for (var i = 0; i < labels.length; i++) {
            var label = labels[i];
            var text = (label.textContent || '').replace(/\s+/g, ' ').trim();

            if (text !== 'Documentation' && text !== 'Support') {
                continue;
            }

            var button = label.closest('.x-btn');

            if (!button) {
                continue;
            }

            /*
             * Keep the original ExtJS button in the header layout.
             * Replacing it with an <a> breaks ExtJS sizing and button gaps.
             */
            if (button.getAttribute('data-hawc-support') !== 'true') {
                button.setAttribute('data-hawc-support', 'true');
                button.setAttribute('aria-label', 'Support');
                button.setAttribute('data-qtip', 'Open HAWCMOX Support');

                button.addEventListener('click', routeToSupport, true);
                button.addEventListener('mousedown', function (event) {
                    event.stopPropagation();
                }, true);
            }

            label.textContent = 'Support';

            var icon = button.querySelector('.x-btn-icon-el');
            if (icon) {
                icon.classList.remove('fa-book', 'fa-question', 'fa-question-circle');
                icon.classList.add('fa-life-ring');
            }

            return;
        }
    }

    function patchSupportPanel() {
        var panels = document.querySelectorAll(
            '[id^="pveDcSupport-"] .x-panel-body:not([data-hawc-card])'
        );

        for (var i = 0; i < panels.length; i++) {
            var panel = panels[i];
            var text = (panel.textContent || '').replace(/\s+/g, ' ').trim();

            if (!/no valid subscription/i.test(text)) {
                continue;
            }

            panel.setAttribute('data-hawc-card', 'true');
            panel.innerHTML =
                '<div class="hawc-subscription-card">' +
                    '<div class="hawc-card-title">HAWCMOX Support</div>' +
                    '<div class="hawc-card-text">' +
                        'Contact: <a class="hawc-subscription-link" ' +
                        'href="mailto:support@hawc.be">support@hawc.be</a>' +
                    '</div>' +
                    '<div class="hawc-card-text">' +
                        'Use this form to contact HAWCMOX support.' +
                    '</div>' +
                    '<a class="hawc-contact-btn" href="' + supportMailto() + '">' +
                        'Contact now' +
                    '</a>' +
                '</div>';
        }
    }

    function updateUI() {
        pending = false;
        patchVersionText();
        classifyButtons();
        patchDocumentationButton();
        patchSupportPanel();
    }

    function scheduleUpdate() {
        if (pending) {
            return;
        }

        pending = true;
        window.setTimeout(updateUI, 80);
    }

    function start() {
        updateUI();

        var observer = new MutationObserver(scheduleUpdate);
        observer.observe(document.body, {
            childList: true,
            subtree: true
        });
    }

    if (document.readyState === 'loading') {
        document.addEventListener('DOMContentLoaded', start, { once: true });
    } else {
        start();
    }
}());
EOF_JS

    chmod 644 "$JS_FILE"
}

write_patcher() {
    cat > "$PATCH_SCRIPT" <<'EOF_PATCH'
#!/bin/sh
set -eu

DATA_DIR="/usr/local/share/hawcmox"
CONFIG_FILE="$DATA_DIR/config"

SOURCE_LOGO="$DATA_DIR/hawcmox_logo.svg"
SOURCE_CSS="$DATA_DIR/hawcmox.css"
SOURCE_JS="$DATA_DIR/hawcmox.js"

TARGET_LOGO="/usr/share/javascript/proxmox-widget-toolkit/images/proxmox_logo.svg"
TARGET_LOGO_BACKUP="$DATA_DIR/proxmox_logo.svg.orig"

TARGET_CSS="/usr/share/pve-manager/css/hawcmox.css"
TARGET_JS="/usr/share/pve-manager/js/hawcmox.js"
TEMPLATE_FILE="/usr/share/pve-manager/index.html.tpl"

BRAND_TITLE="HAWCMOX"

if [ -s "$CONFIG_FILE" ]; then
    BRAND_TITLE="$(sed -n '1p' "$CONFIG_FILE")"
fi

if [ -z "$BRAND_TITLE" ]; then
    BRAND_TITLE="HAWCMOX"
fi

escape_sed_replacement() {
    printf '%s' "$1" | sed 's/[\/&|\\]/\\&/g'
}

if [ -f "$TARGET_LOGO" ] && [ ! -f "$TARGET_LOGO_BACKUP" ]; then
    cp -f "$TARGET_LOGO" "$TARGET_LOGO_BACKUP"
fi

if [ -f "$SOURCE_LOGO" ] && [ -d "$(dirname "$TARGET_LOGO")" ]; then
    cp -f "$SOURCE_LOGO" "$TARGET_LOGO"
    chmod 644 "$TARGET_LOGO"
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

    sed -i \
        "s|<title>[^<]*</title>|<title>${escaped_title}</title>|" \
        "$TEMPLATE_FILE"

    if ! grep -qF '/pve2/css/hawcmox.css' "$TEMPLATE_FILE"; then
        sed -i \
            's|</head>|    <link rel="stylesheet" type="text/css" href="/pve2/css/hawcmox.css">\n</head>|' \
            "$TEMPLATE_FILE"
    fi

    if ! grep -qF '/pve2/js/hawcmox.js' "$TEMPLATE_FILE"; then
        sed -i \
            's|</head>|    <script type="text/javascript" src="/pve2/js/hawcmox.js"></script>\n</head>|' \
            "$TEMPLATE_FILE"
    fi
fi

if command -v systemctl >/dev/null 2>&1; then
    systemctl restart pveproxy.service >/dev/null 2>&1 || true
fi
EOF_PATCH

    chmod 755 "$PATCH_SCRIPT"
}

install_theme() {
    printf '\n============================================================\n'
    printf ' HAWCMOX INSTALLER v6.5\n'
    printf '============================================================\n'

    printf '[1/7] Creating data directory...\n'
    mkdir -p "$DATA_DIR"
    chmod 755 "$DATA_DIR"

    printf '[2/7] Downloading logo...\n'
    download_file "$LOGO_URL" "$LOGO_RAW_FILE"
    prepare_logo_svg "$LOGO_RAW_FILE" "$LOGO_SVG_FILE"
    rm -f "$LOGO_RAW_FILE"
    chmod 644 "$LOGO_SVG_FILE"

    printf '[3/7] Writing safe CSS theme...\n'
    write_css

    printf '[4/7] Writing header support-button patch...\n'
    write_js

    printf '[5/7] Saving configuration...\n'
    printf '%s\n' "$BRAND_TITLE" > "$CONFIG_FILE"
    chmod 644 "$CONFIG_FILE"

    printf '[6/7] Creating persistent update patcher...\n'
    write_patcher

    printf '[7/7] Applying theme...\n'
    cat > "$APT_HOOK" <<'EOF_HOOK'
DPkg::Post-Invoke { "/usr/local/bin/hawcmox-patch.sh || true"; };
EOF_HOOK
    chmod 644 "$APT_HOOK"

    "$PATCH_SCRIPT"

    printf '\n============================================================\n'
    printf ' HAWCMOX INSTALLATION COMPLETE\n'
    printf '============================================================\n'
    printf 'Use a private/incognito browser window or hard-refresh the UI.\n'
}

uninstall_theme() {
    printf '\n============================================================\n'
    printf ' HAWCMOX UNINSTALLER\n'
    printf '============================================================\n'

    printf '[1/3] Removing theme files and APT hook...\n'
    rm -f "$APT_HOOK"
    rm -f "$PATCH_SCRIPT"
    rm -f "$TARGET_CSS"
    rm -f "$TARGET_JS"

    printf '[2/3] Reinstalling original Proxmox web assets...\n'
    export DEBIAN_FRONTEND=noninteractive
    apt-get update >/dev/null 2>&1 || true
    apt-get install --reinstall -y pve-manager proxmox-widget-toolkit >/dev/null 2>&1

    printf '[3/3] Removing HAWCMOX data and restarting pveproxy...\n'
    rm -rf "$DATA_DIR"

    if command -v systemctl >/dev/null 2>&1; then
        systemctl restart pveproxy.service >/dev/null 2>&1 || true
    fi

    printf '\n============================================================\n'
    printf ' HAWCMOX REMOVED\n'
    printf '============================================================\n'
}

printf '\n============================================================\n'
printf ' HAWCMOX UI MANAGER v6.5\n'
printf '============================================================\n'
printf ' 1) Install / Update HAWCMOX Theme\n'
printf ' 2) Remove HAWCMOX Theme (Restore Default)\n'
printf ' 3) Exit\n'
printf '============================================================\n'
printf 'Select an option [1-3]: '

read -r choice || choice=""

case "$choice" in
    1|'') install_theme ;;
    2) uninstall_theme ;;
    3) exit 0 ;;
    *)
        printf '%s\n' 'Invalid choice. Exiting.'
        exit 1
        ;;
esac
