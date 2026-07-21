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

# proxmoxlib.js is the shared widget-toolkit file that shows the
# "No valid subscription" popup on login. We back it up before patching
# it so uninstall (or re-running with the nag re-enabled) can restore it.
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
    if ask_yes_no "Hide the 'No valid subscription' popup and subscription-tab warning?" "y"; then
        HIDE_NAG="yes"
    else
        HIDE_NAG="no"
    fi

    printf '\n'
    if ! ask_yes_no "Apply these changes now?" "y"; then
        printf '%s\n' "Installation cancelled."
        exit 0
    fi

    printf '\n[1/7] Creating directories...\n'
    mkdir -p "$DATA_DIR"
    chmod 755 "$DATA_DIR"

    printf '[2/7] Downloading and preparing custom logo...\n'
    download_file "$LOGO_URL" "$LOGO_RAW_FILE"
    prepare_logo_svg "$LOGO_RAW_FILE" "$LOGO_SVG_FILE"
    rm -f "$LOGO_RAW_FILE"
    chmod 644 "$LOGO_SVG_FILE"

    printf '[3/7] Generating modern slate CSS theme...\n'
    cat > "$CSS_FILE" <<'EOF_CSS'
/* HAWCMOX - Modern Slate Proxmox Theme */

:root {
    --hawc-bg:          #1b1f26;
    --hawc-panel:        #242a33;
    --hawc-panel-alt:    #2b323d;
    --hawc-border:       #363e4a;
    --hawc-text:         #e6e9ee;
    --hawc-text-dim:     #a4acb8;
    --hawc-accent:       #5b8def;
    --hawc-accent-hov:   #7aa3f2;
    --hawc-radius:       10px;
    --hawc-radius-sm:    6px;

    /* Action-button colors */
    --hawc-warn:         #eab308; /* reboot            */
    --hawc-warn-text:    #1b1f26;
    --hawc-danger:       #e5484d; /* shutdown / stop    */
    --hawc-danger-text:  #ffffff;
    --hawc-dark-btn:     #14171c; /* console / shell    */
    --hawc-dark-text:    #e6e9ee;
    --hawc-create:       #2f6f55; /* create vm/ct - subtle */
    --hawc-create-border:#3f8f70;
    --hawc-create-text:  #e6e9ee;
}

html, body, .x-viewport, .x-body {
    background: var(--hawc-bg) !important;
}

/* --- Panels / windows: single radius owner, clipped children ---
   Putting border-radius on BOTH a panel and its header separately is
   what caused corners to look "bugged" in some spots (mismatched or
   square corners poking out). Instead the outer panel/window owns the
   radius and clips everything inside it with overflow:hidden.
   This is also what keeps the left VM/CT tree panel and the center
   content panel a consistent grey - they're both just `.x-panel`. */
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

/* --- Buttons (default/neutral) --- */
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

/* --- Action buttons ---
   hawcmox.js tags Start/Stop/Shutdown/Reboot/Console/Shell/Create VM/
   Create CT buttons with a data-hawc-action attribute (matched by
   their visible text or tooltip, since Proxmox's own icon/CSS classes
   shift between versions). These selectors are more specific than the
   plain .x-btn-default-* rule above, so they win over the grey default
   without needing to touch anything else. */
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

.x-btn[data-hawc-action]:hover {
    filter: brightness(1.12) !important;
    opacity: 1 !important;
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

/* --- Grids / trees (this is what keeps the left VM/CT tree and the
   center resource grid a consistent grey) --- */
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
 * Sizing is bumped up from stock, and `filter`/`mix-blend-mode` are
 * explicitly reset to none - Proxmox's built-in dark theme applies an
 * invert-style filter to some header images, which is what was
 * washing out / recoloring the custom logo.
 */
img[src*="proxmox_logo"],
.x-panel-header img,
.x-toolbar img {
    object-fit: contain !important;
    height: 42px !important;
    max-width: 240px !important;
    filter: none !important;
    -webkit-filter: none !important;
    mix-blend-mode: normal !important;
    opacity: 1 !important;
}

/* --- Subscription nag banner in the Subscription tab.
   Class names vary a bit by Proxmox version - this targets the most
   common wrapper (`.pmx-hint`/warning message boxes) used for the
   "you do not have a valid subscription" banner. If it doesn't hide
   on your version, inspect the element and send the class name. */
.pmx-hint {
    display: none !important;
}
EOF_CSS
    chmod 644 "$CSS_FILE"

    printf '[4/7] Generating UI patcher script (title/logo cleanup, button colors, subscription text)...\n'
    cat > "$JS_FILE" <<'EOF_JS'
/* HAWCMOX client-side patcher.
 * - Removes "Virtual Environment <version>" text next to the logo.
 * - Tags action buttons (Start/Stop/Shutdown/Reboot/Console/Shell/
 *   Create VM/Create CT) with data-hawc-action so hawcmox.css can
 *   color just those buttons without touching everything else.
 * - Rewrites subscription-status text and auto-dismisses the
 *   "No valid subscription" popup, if enabled during install.
 * Runs via a MutationObserver over the whole document body so it
 * keeps working regardless of when/where ExtJS renders things. */
(function () {
    var TEXT_REPLACEMENTS = [
        { re: /Virtual Environment\s*[\d.]*\s*/g, to: '' },
        { re: /There is no subscription key/gi, to: 'Subscription managed by HAWC BV' },
        { re: /\bnotfound\b/gi, to: 'active' }
    ];

    var ACTION_MAP = [
        { re: /^create\s*vm$/i, action: 'create-vm' },
        { re: /^create\s*ct$/i, action: 'create-ct' },
        { re: /^reboot$/i, action: 'reboot' },
        { re: /^shutdown$/i, action: 'shutdown' },
        { re: /^stop$/i, action: 'stop' },
        { re: /^console$/i, action: 'console' },
        { re: /^shell$/i, action: 'shell' },
        { re: /^>_\s*console$/i, action: 'console' }
    ];

    function processTextNode(node) {
        var data = node.data;
        var changed = false;
        for (var i = 0; i < TEXT_REPLACEMENTS.length; i++) {
            if (TEXT_REPLACEMENTS[i].re.test(data)) {
                data = data.replace(TEXT_REPLACEMENTS[i].re, TEXT_REPLACEMENTS[i].to);
                changed = true;
            }
        }
        if (changed) {
            node.data = data.trim();
        }
    }

    function walkText(root) {
        if (!root) return;
        if (root.nodeType === 3) {
            processTextNode(root);
            return;
        }
        if (root.nodeType !== 1 && root.nodeType !== 11) return;
        var tw = document.createTreeWalker(root, NodeFilter.SHOW_TEXT, null, false);
        var n;
        while ((n = tw.nextNode())) processTextNode(n);
    }

    function buttonText(btn) {
        var inner = btn.querySelector('.x-btn-inner');
        var t = inner ? inner.textContent : '';
        if (!t) {
            t = btn.getAttribute('data-qtip') || btn.getAttribute('title') ||
                btn.getAttribute('aria-label') || '';
        }
        return (t || '').trim();
    }

    function tagButton(btn) {
        var text = buttonText(btn);
        if (!text) return;
        for (var i = 0; i < ACTION_MAP.length; i++) {
            if (ACTION_MAP[i].re.test(text)) {
                if (btn.getAttribute('data-hawc-action') !== ACTION_MAP[i].action) {
                    btn.setAttribute('data-hawc-action', ACTION_MAP[i].action);
                }
                return;
            }
        }
    }

    function tagAllButtons(root) {
        if (!root) return;
        if (root.nodeType === 1 && root.classList && root.classList.contains('x-btn')) {
            tagButton(root);
        }
        if (root.querySelectorAll) {
            var btns = root.querySelectorAll('.x-btn');
            for (var i = 0; i < btns.length; i++) tagButton(btns[i]);
        }
    }

    // Auto-dismiss the "No valid subscription" modal if it appears.
    // This is a client-side backup for when the server-side
    // proxmoxlib.js patch (applied by hawcmox-patch.sh) isn't present
    // or hasn't taken effect yet after an update.
    function dismissSubscriptionNag(root) {
        if (!root || !root.querySelectorAll) return;
        var wins = root.querySelectorAll('.x-window, .x-message-box');
        for (var i = 0; i < wins.length; i++) {
            var w = wins[i];
            var txt = w.textContent || '';
            if (/no valid subscription/i.test(txt)) {
                var btns = w.querySelectorAll('.x-btn');
                if (btns.length) {
                    btns[0].click();
                } else if (w.parentNode) {
                    w.parentNode.removeChild(w);
                }
            }
        }
    }

    function processRoot(root) {
        walkText(root);
        tagAllButtons(root);
        dismissSubscriptionNag(root);
    }

    function init() {
        processRoot(document.body);
        var observer = new MutationObserver(function (mutations) {
            for (var i = 0; i < mutations.length; i++) {
                var m = mutations[i];
                if (m.type === 'characterData') {
                    processTextNode(m.target);
                } else if (m.addedNodes) {
                    for (var j = 0; j < m.addedNodes.length; j++) {
                        processRoot(m.addedNodes[j]);
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

    printf '%s\n%s\n' "$BRAND_TITLE" "$HIDE_NAG" > "$CONFIG_FILE"

    printf '[5/7] Creating persistent patcher...\n'
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

SUBLIB_FILE="/usr/share/javascript/proxmox-widget-toolkit/js/proxmoxlib.js"
SUBLIB_BACKUP="$DATA_DIR/proxmoxlib.js.orig"

BRAND_TITLE="HAWCMOX"
HIDE_NAG="no"
if [ -s "$CONFIG_FILE" ]; then
    BRAND_TITLE="$(sed -n '1p' "$CONFIG_FILE")"
    HIDE_NAG="$(sed -n '2p' "$CONFIG_FILE")"
    [ -z "$BRAND_TITLE" ] && BRAND_TITLE="HAWCMOX"
    [ -z "$HIDE_NAG" ] && HIDE_NAG="no"
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

# Subscription nag popup: proxmoxlib.js runs a check that pops an
# Ext.Msg dialog when there's no active subscription. The standard
# fix (widely used in the Proxmox homelab community) is to force that
# specific condition to false so the dialog never fires. Backed up
# first so it can be restored via uninstall or by re-running the
# installer with this option turned off.
if [ -f "$SUBLIB_FILE" ]; then
    if [ ! -f "$SUBLIB_BACKUP" ]; then
        cp -f "$SUBLIB_FILE" "$SUBLIB_BACKUP" 2>/dev/null || true
    fi

    if [ "$HIDE_NAG" = "yes" ]; then
        if [ -f "$SUBLIB_BACKUP" ]; then
            cp -f "$SUBLIB_BACKUP" "$SUBLIB_FILE"
        fi
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

    printf '[6/7] Applying customization...\n'
    if [ "$INSTALL_APT_HOOK" = "yes" ]; then
        cat > "$APT_HOOK" <<'EOF_HOOK'
DPkg::Post-Invoke { "/usr/local/bin/hawcmox-patch.sh || true"; };
EOF_HOOK
        chmod 644 "$APT_HOOK"
    else
        rm -f "$APT_HOOK"
    fi

    "$PATCH_SCRIPT"

    printf '[7/7] Done.\n'
    printf '\n============================================================\n'
    printf ' HAWCMOX INSTALLATION COMPLETE\n'
    printf '============================================================\n\n'
    printf 'IMPORTANT: The backend service has been reloaded.\n'
    printf 'Open Proxmox in a brand new Incognito/Private window to bypass your cache and see the changes.\n'
    printf 'If the logo still looks wrong, right-click it -> "Open image in new tab" and\n'
    printf 'send me that exact URL so the target path can be double-checked against your install.\n'
    printf 'If any action button (reboot/shutdown/shell/create) does not pick up its color,\n'
    printf 'right-click it -> Inspect, and send me its visible text/tooltip so the JS matcher can be tuned.\n'
}

uninstall_theme() {
    printf '\n============================================================\n'
    printf ' HAWCMOX UNINSTALLER\n'
    printf '============================================================\n'

    printf '[1/4] Restoring proxmoxlib.js (subscription check) if patched...\n'
    if [ -f "$SUBLIB_BACKUP" ] && [ -f "$SUBLIB_FILE" ]; then
        cp -f "$SUBLIB_BACKUP" "$SUBLIB_FILE" 2>/dev/null || true
    fi

    printf '[2/4] Removing HAWCMOX files and APT hooks...\n'
    rm -rf "/usr/local/share/hawcmox"
    rm -f "/usr/local/bin/hawcmox-patch.sh"
    rm -f "/etc/apt/apt.conf.d/99hawcmox-theme"
    rm -f "/usr/share/pve-manager/css/hawcmox.css"
    rm -f "/usr/share/pve-manager/js/hawcmox.js"

    printf '[3/4] Restoring original Proxmox HTML templates, logo and widget toolkit...\n'
    export DEBIAN_FRONTEND=noninteractive
    apt-get install --reinstall pve-manager proxmox-widget-toolkit -y >/dev/null 2>&1

    printf '[4/4] Restarting Proxmox web interface...\n'
    if command -v systemctl >/dev/null 2>&1; then
        systemctl restart pveproxy.service >/dev/null 2>&1 || true
    fi

    printf '\n============================================================\n'
    printf ' REVERT COMPLETE\n'
    printf '============================================================\n\n'
    printf 'The server is now back to stock Proxmox defaults (including the stock\n'
    printf 'subscription check, if it had been patched).\n'
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
