#!/bin/sh

# HAWCMOX Proxmox UI Manager - For Proxmox 9.2.2+
# Unified script to Install or Remove the custom theme.

set -eu

DEFAULT_TITLE="HAWCMOX"
DEFAULT_LOGO_URL="https://raw.githubusercontent.com/HeyvaertSeppe/hawcmox-theme/main/proxmox_logo.png"

DATA_DIR="/usr/local/share/hawcmox"
PATCH_SCRIPT="/usr/local/bin/hawcmox-patch.sh"
APT_HOOK="/etc/apt/apt.conf.d/99hawcmox-theme"
LOGO_RAW_FILE="$DATA_DIR/hawcmox_logo.raw"
LOGO_SVG_FILE="$DATA_DIR/hawcmox_logo.svg"
CSS_FILE="$DATA_DIR/hawcmox.css"
JS_FILE="$DATA_DIR/hawcmox.js"
CONFIG_FILE="$DATA_DIR/config"

if [ "$(id -u)" -ne 0 ]; then
    printf '%s\n' "ERROR: This script must be run as root."
    exit 1
fi

if [ ! -d "/usr/share/pve-manager" ]; then
    printf '%s\n' "ERROR: This does not appear to be a Proxmox VE node."
    exit 1
fi

ask_value() {
    prompt="$1"
    default_value="$2"
    # The prompt must go to stderr, not stdout. Callers capture this
    # function's output with $(...), which only captures stdout - if the
    # prompt were printed on stdout too, it would get silently mixed
    # into the returned value.
    printf '%s [%s]: ' "$prompt" "$default_value" >&2
    read -r answer || answer=""
    [ -z "$answer" ] && answer="$default_value"
    printf '%s' "$answer"
}

ask_yes_no() {
    prompt="$1"
    default_answer="$2"
    while :; do
        if [ "$default_answer" = "y" ]; then
            printf '%s [Y/n]: ' "$prompt"
        else
            printf '%s [y/N]: ' "$prompt"
        fi

        read -r answer || answer=""
        [ -z "$answer" ] && answer="$default_answer"

        case "$answer" in
            y|Y|yes|YES|Yes) return 0 ;;
            n|N|no|NO|No) return 1 ;;
            *) printf '%s\n' "Please answer yes or no." ;;
        esac
    done
}

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

# Turns whatever image was downloaded (SVG, PNG, or anything else) into
# a single .svg file at $2, because the real Proxmox logo asset is an
# SVG file (/pwt/images/proxmox_logo.svg) and must stay one for the
# browser to load it.
prepare_logo_svg() {
    raw_file="$1"
    out_svg="$2"

    # Already SVG? Just use it as-is.
    if head -c 512 "$raw_file" 2>/dev/null | grep -qi '<svg'; then
        cp -f "$raw_file" "$out_svg"
        return 0
    fi

    sig="$(head -c 8 "$raw_file" | od -An -tx1 | tr -d ' \n')"

    if [ "$sig" = "89504e470d0a1a0a" ]; then
        # PNG: read real width/height straight out of the IHDR chunk
        # (bytes 16-19 / 20-23, big-endian) so the wrapped SVG keeps
        # the correct aspect ratio instead of stretching.
        width="$(od -An -tu4 -j 16 -N 4 --endian=big "$raw_file" | tr -d ' ')"
        height="$(od -An -tu4 -j 20 -N 4 --endian=big "$raw_file" | tr -d ' ')"
        mime="image/png"
    else
        # Unknown/other raster format (e.g. JPEG). Dimensions aren't
        # parsed for these, so it falls back to a generic wide-logo
        # box; a PNG or SVG source will look more precise.
        width="200"
        height="60"
        mime="image/*"
        printf '%s\n' "NOTE: logo isn't SVG or PNG - using a generic aspect ratio. For a pixel-perfect fit, use a .svg or .png source image."
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
    printf ' HAWCMOX INSTALLER (Proxmox 9.2.2+)\n'
    printf '============================================================\n'

    BRAND_TITLE="$(ask_value "Browser title/brand name" "$DEFAULT_TITLE")"
    printf '\n'
    LOGO_URL="$(ask_value "Direct URL of the logo (SVG or PNG)" "$DEFAULT_LOGO_URL")"
    printf '\n'

    if ask_yes_no "Reapply automatically after package updates?" "y"; then
        INSTALL_APT_HOOK="yes"
    else
        INSTALL_APT_HOOK="no"
    fi

    printf '\n'
    if ! ask_yes_no "Apply these changes now?" "y"; then
        printf '%s\n' "Installation cancelled."
        exit 0
    fi

    printf '\n[1/6] Creating directories...\n'
    mkdir -p "$DATA_DIR"
    chmod 755 "$DATA_DIR"

    printf '[2/6] Downloading and preparing custom logo...\n'
    download_file "$LOGO_URL" "$LOGO_RAW_FILE"
    prepare_logo_svg "$LOGO_RAW_FILE" "$LOGO_SVG_FILE"
    rm -f "$LOGO_RAW_FILE"
    chmod 644 "$LOGO_SVG_FILE"

    printf '[3/6] Generating modern slate CSS theme...\n'
    cat > "$CSS_FILE" <<'EOF_CSS'
/* HAWCMOX - Modern Slate Proxmox Theme */

:root {
    --hawc-bg:        #1b1f26;
    --hawc-panel:      #242a33;
    --hawc-panel-alt:  #2b323d;
    --hawc-border:     #363e4a;
    --hawc-text:       #e6e9ee;
    --hawc-text-dim:   #a4acb8;
    --hawc-accent:     #5b8def;
    --hawc-accent-hov: #7aa3f2;
    --hawc-radius:     10px;
    --hawc-radius-sm:  6px;
}

html, body, .x-viewport, .x-body {
    background: var(--hawc-bg) !important;
}

/* --- Panels / windows: single radius owner, clipped children ---
   Putting border-radius on BOTH a panel and its header separately is
   what caused corners to look "bugged" in some spots (mismatched or
   square corners poking out). Instead the outer panel/window owns the
   radius and clips everything inside it with overflow:hidden. */
.x-panel, .x-window, .x-panel-default, .x-window-default {
    background: var(--hawc-panel) !important;
    border: 1px solid var(--hawc-border) !important;
    border-radius: var(--hawc-radius) !important;
    box-shadow: 0 4px 16px rgba(0, 0, 0, 0.35) !important;
    overflow: hidden !important;
}

.x-panel-header, .x-window-header,
.x-panel-header-default, .x-window-header-default {
    background: var(--hawc-panel-alt) !important;
    border: none !important;
    border-radius: 0 !important; /* clipped by parent overflow:hidden */
    color: var(--hawc-text) !important;
}

.x-panel-body, .x-window-body {
    background: var(--hawc-panel) !important;
    border-radius: 0 !important;
    color: var(--hawc-text) !important;
}

.x-toolbar {
    background: var(--hawc-panel-alt) !important;
    border: none !important;
    border-bottom: 1px solid var(--hawc-border) !important;
}

/* --- Buttons --- */
.x-btn {
    border-radius: var(--hawc-radius-sm) !important;
    transition: background-color 0.15s ease, opacity 0.15s ease !important;
}

.x-btn-default-small, .x-btn-default-medium {
    background: var(--hawc-panel-alt) !important;
    border: 1px solid var(--hawc-border) !important;
    color: var(--hawc-text) !important;
}

.x-btn:hover {
    opacity: 0.88 !important;
}

.x-btn-default-small.x-btn-over,
.x-btn-default-medium.x-btn-over {
    background: var(--hawc-accent) !important;
    border-color: var(--hawc-accent) !important;
}

/* --- Inputs --- */
.x-form-text, .x-form-text-default, .x-form-field {
    background: var(--hawc-panel-alt) !important;
    border: 1px solid var(--hawc-border) !important;
    border-radius: var(--hawc-radius-sm) !important;
    color: var(--hawc-text) !important;
}

.x-form-trigger-wrap-focus .x-form-text,
.x-form-text-focus {
    border-color: var(--hawc-accent) !important;
}

/* --- Tabs --- */
.x-tab {
    border-radius: var(--hawc-radius-sm) var(--hawc-radius-sm) 0 0 !important;
    background: var(--hawc-panel) !important;
    color: var(--hawc-text-dim) !important;
}

.x-tab-active {
    background: var(--hawc-panel-alt) !important;
    color: var(--hawc-text) !important;
}

/* --- Grids / trees --- */
.x-grid-header-ct, .x-column-header {
    background: var(--hawc-panel-alt) !important;
    color: var(--hawc-text) !important;
    border-color: var(--hawc-border) !important;
}

.x-grid-row:hover .x-grid-cell,
.x-grid-row-over .x-grid-cell {
    background: var(--hawc-panel-alt) !important;
}

.x-grid-row-selected .x-grid-cell {
    background: rgba(91, 141, 239, 0.18) !important;
}

/* --- Dropdown menus / autocomplete lists --- */
.x-menu, .x-boundlist {
    background: var(--hawc-panel-alt) !important;
    border: 1px solid var(--hawc-border) !important;
    border-radius: var(--hawc-radius-sm) !important;
    box-shadow: 0 4px 16px rgba(0, 0, 0, 0.35) !important;
    overflow: hidden !important;
}

.x-boundlist-item-over {
    background: var(--hawc-accent) !important;
}

/* --- Scrollbars (WebKit/Chromium/Edge) --- */
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

/*
 * The logo image itself is replaced by overwriting the real SVG asset
 * on disk (/pwt/images/proxmox_logo.svg via hawcmox-patch.sh), so no
 * CSS override/selector-matching hack is needed for the image itself.
 * This rule just keeps sizing consistent regardless of your custom
 * logo's native dimensions.
 */
img[src*="proxmox_logo"] {
    object-fit: contain !important;
    height: 30px !important;
    max-width: 160px !important;
}
EOF_CSS
    chmod 644 "$CSS_FILE"

    printf '[4/6] Generating text-removal patcher script...\n'
    cat > "$JS_FILE" <<'EOF_JS'
/* HAWCMOX - removes "Virtual Environment <version>" next to the logo.
 * Uses a MutationObserver over ALL text nodes (not just <span>) so it
 * keeps working no matter which element ExtJS renders the title into,
 * and no matter when (it doesn't rely on running once at page load). */
(function () {
    function stripNode(node) {
        if (node.nodeType === 3 && node.data.indexOf('Virtual Environment') !== -1) {
            node.data = node.data.replace(/Virtual Environment\s*[\d.]*\s*/g, '').trim();
        }
    }

    function walk(root) {
        if (!root) return;
        if (root.nodeType === 3) {
            stripNode(root);
            return;
        }
        if (root.nodeType !== 1 && root.nodeType !== 11) return;
        var tw = document.createTreeWalker(root, NodeFilter.SHOW_TEXT, null, false);
        var n;
        while ((n = tw.nextNode())) stripNode(n);
    }

    function init() {
        walk(document.body);
        var observer = new MutationObserver(function (mutations) {
            for (var i = 0; i < mutations.length; i++) {
                var m = mutations[i];
                if (m.type === 'characterData') {
                    stripNode(m.target);
                } else if (m.addedNodes) {
                    for (var j = 0; j < m.addedNodes.length; j++) {
                        walk(m.addedNodes[j]);
                    }
                }
            }
        });
        observer.observe(document.body, {
            childList: true,
            subtree: true,
            characterData: true
        });
    }

    if (document.body) {
        init();
    } else {
        document.addEventListener('DOMContentLoaded', init);
    }
})();
EOF_JS
    chmod 644 "$JS_FILE"
    printf '%s\n' "$BRAND_TITLE" > "$CONFIG_FILE"

    printf '[5/6] Creating persistent patcher...\n'
    cat > "$PATCH_SCRIPT" <<'EOF_PATCH'
#!/bin/sh
set -eu

DATA_DIR="/usr/local/share/hawcmox"
CONFIG_FILE="$DATA_DIR/config"
SOURCE_LOGO="$DATA_DIR/hawcmox_logo.svg"
SOURCE_CSS="$DATA_DIR/hawcmox.css"
SOURCE_JS="$DATA_DIR/hawcmox.js"

# This is the file the browser actually loads for the top-left logo
# (confirm on your own install via right-click -> "Open image in new
# tab" on the logo; it should be /pwt/images/proxmox_logo.svg).
TARGET_LOGO_PWT="/usr/share/javascript/proxmox-widget-toolkit/images/proxmox_logo.svg"
TARGET_LOGO_PWT_BACKUP="$DATA_DIR/proxmox_logo.svg.orig"

# Some Proxmox versions/products also ship a copy under pve-manager;
# harmless to keep in sync too if it exists.
TARGET_LOGO_PVE="/usr/share/pve-manager/images/proxmox_logo.png"

TARGET_CSS="/usr/share/pve-manager/css/hawcmox.css"
TARGET_JS="/usr/share/pve-manager/js/hawcmox.js"
TEMPLATE_FILE="/usr/share/pve-manager/index.html.tpl"

BRAND_TITLE="HAWCMOX"
[ -s "$CONFIG_FILE" ] && BRAND_TITLE="$(head -n 1 "$CONFIG_FILE")"

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
    # Only touch the pve-manager copy if it already exists on this install.
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

if command -v systemctl >/dev/null 2>&1; then
    systemctl restart pveproxy.service >/dev/null 2>&1 || true
fi
EOF_PATCH
    chmod 755 "$PATCH_SCRIPT"

    printf '[6/6] Applying customization...\n'
    if [ "$INSTALL_APT_HOOK" = "yes" ]; then
        cat > "$APT_HOOK" <<'EOF_HOOK'
DPkg::Post-Invoke { "/usr/local/bin/hawcmox-patch.sh || true"; };
EOF_HOOK
        chmod 644 "$APT_HOOK"
    else
        rm -f "$APT_HOOK"
    fi

    "$PATCH_SCRIPT"

    printf '\n============================================================\n'
    printf ' HAWCMOX INSTALLATION COMPLETE\n'
    printf '============================================================\n\n'
    printf 'IMPORTANT: The backend service has been reloaded.\n'
    printf 'Open Proxmox in a brand new Incognito/Private window to bypass your cache and see the changes.\n'
    printf 'If the logo still looks wrong, right-click it -> "Open image in new tab" and\n'
    printf 'send me that exact URL so the target path can be double-checked against your install.\n'
}

uninstall_theme() {
    printf '\n============================================================\n'
    printf ' HAWCMOX UNINSTALLER\n'
    printf '============================================================\n'

    printf '[1/3] Removing HAWCMOX files and APT hooks...\n'
    rm -rf "/usr/local/share/hawcmox"
    rm -f "/usr/local/bin/hawcmox-patch.sh"
    rm -f "/etc/apt/apt.conf.d/99hawcmox-theme"
    rm -f "/usr/share/pve-manager/css/hawcmox.css"
    rm -f "/usr/share/pve-manager/js/hawcmox.js"

    printf '[2/3] Restoring original Proxmox HTML templates and logo...\n'
    export DEBIAN_FRONTEND=noninteractive
    apt-get install --reinstall pve-manager proxmox-widget-toolkit -y >/dev/null 2>&1

    printf '[3/3] Restarting Proxmox web interface...\n'
    if command -v systemctl >/dev/null 2>&1; then
        systemctl restart pveproxy.service >/dev/null 2>&1 || true
    fi

    printf '\n============================================================\n'
    printf ' REVERT COMPLETE\n'
    printf '============================================================\n\n'
    printf 'The server is now back to stock Proxmox defaults.\n'
    printf 'Open Proxmox in an Incognito/Private window to verify.\n'
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
