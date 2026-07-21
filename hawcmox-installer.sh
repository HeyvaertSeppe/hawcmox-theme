#!/bin/sh

# HAWCMOX Proxmox UI Customization Installer (Modern Grey)
# Visual customization only. Replaces logo, hides version text, modernizes CSS.

set -eu

DEFAULT_TITLE="HAWCMOX"
DEFAULT_LOGO_URL="https://raw.githubusercontent.com/HeyvaertSeppe/hawcmox-theme/main/proxmox_logo.png"

DATA_DIR="/usr/local/share/hawcmox"
PATCH_SCRIPT="/usr/local/bin/hawcmox-patch.sh"
APT_HOOK="/etc/apt/apt.conf.d/99hawcmox-theme"

LOGO_FILE="$DATA_DIR/hawcmox_logo.png"
CSS_FILE="$DATA_DIR/hawcmox.css"
CONFIG_FILE="$DATA_DIR/config"

ask_value() {
    prompt="$1"
    default_value="$2"
    printf '%s [%s]: ' "$prompt" "$default_value" >&2
    if [ -r /dev/tty ]; then
        IFS= read -r answer < /dev/tty || answer=""
    else
        answer=""
    fi
    [ -z "$answer" ] && answer="$default_value"
    printf '%s' "$answer"
}

ask_yes_no() {
    prompt="$1"
    default_answer="$2"
    while :; do
        if [ "$default_answer" = "y" ]; then
            printf '%s [Y/n]: ' "$prompt" >&2
        else
            printf '%s [y/N]: ' "$prompt" >&2
        fi

        if [ -r /dev/tty ]; then
            IFS= read -r answer < /dev/tty || answer=""
        else
            answer="$default_answer"
        fi
        [ -z "$answer" ] && answer="$default_answer"

        case "$answer" in
            y|Y|yes|YES|Yes) return 0 ;;
            n|N|no|NO|No) return 1 ;;
            *) printf '%s\n' "Please answer yes or no." >&2 ;;
        esac
    done
}

download_file() {
    url="$1"
    destination="$2"
    temporary_file="${destination}.download"
    rm -f "$temporary_file"

    if command -v curl >/dev/null 2>&1; then
        curl -4 --fail --location --silent --show-error --retry 3 "$url" --output "$temporary_file"
    elif command -v wget >/dev/null 2>&1; then
        wget -4 --quiet --tries=3 --output-document="$temporary_file" "$url"
    else
        printf '%s\n' "ERROR: Neither curl nor wget is installed."
        exit 1
    fi

    if [ ! -s "$temporary_file" ]; then
        rm -f "$temporary_file"
        printf '%s\n' "ERROR: The downloaded file is empty. Check your URL."
        exit 1
    fi
    mv "$temporary_file" "$destination"
}

if [ "$(id -u)" -ne 0 ]; then
    printf '%s\n' "ERROR: This script must be run as root."
    exit 1
fi

if [ ! -d "/usr/share/pve-manager" ]; then
    printf '%s\n' "ERROR: This does not appear to be a Proxmox VE node."
    exit 1
fi

printf '\n============================================================\n' >&2
printf ' HAWCMOX Proxmox UI Installer\n' >&2
printf '============================================================\n' >&2

BRAND_TITLE="$(ask_value "Browser title/brand name" "$DEFAULT_TITLE")"
LOGO_URL="$(ask_value "Direct URL of the PNG logo" "$DEFAULT_LOGO_URL")"

printf '\n' >&2
if ask_yes_no "Reapply automatically after package updates?" "y"; then
    INSTALL_APT_HOOK="yes"
else
    INSTALL_APT_HOOK="no"
fi

if ! ask_yes_no "Apply these changes now?" "y"; then
    printf '%s\n' "Installation cancelled."
    exit 0
fi

printf '\n[1/5] Creating directories...\n'
mkdir -p "$DATA_DIR"
chmod 755 "$DATA_DIR"

printf '[2/5] Downloading custom logo...\n'
download_file "$LOGO_URL" "$LOGO_FILE"
chmod 644 "$LOGO_FILE"

printf '[3/5] Generating modern grey CSS theme...\n'
cat > "$CSS_FILE" <<'EOF_CSS'
/* HAWCMOX - Modern Slate Proxmox Theme */

/* Modern rounded corners and subtle shadows for windows */
.x-panel, .x-window, .x-panel-default, .x-window-default {
    border-radius: 8px !important;
    box-shadow: 0 4px 12px rgba(0, 0, 0, 0.15) !important;
    border: none !important;
}

.x-panel-header, .x-window-header {
    border-radius: 8px 8px 0 0 !important;
}

/* Softer buttons with smooth transitions */
.x-btn {
    border-radius: 6px !important;
    transition: opacity 0.2s ease-in-out !important;
}

.x-btn:hover {
    opacity: 0.85 !important;
}

.x-form-text, .x-form-text-default {
    border-radius: 4px !important;
}

/* Force custom logo via CSS to bypass SVG file format conflicts */
.proxmox-logo {
    background-image: url('/pve2/images/hawcmox_logo.png') !important;
    background-size: contain !important;
    background-repeat: no-repeat !important;
    background-position: left center !important;
    width: 150px !important; 
}
EOF_CSS
chmod 644 "$CSS_FILE"
printf '%s\n' "$BRAND_TITLE" > "$CONFIG_FILE"

printf '[4/5] Creating persistent patcher...\n'
cat > "$PATCH_SCRIPT" <<'EOF_PATCH'
#!/bin/sh
set -eu

DATA_DIR="/usr/local/share/hawcmox"
CONFIG_FILE="$DATA_DIR/config"
SOURCE_LOGO="$DATA_DIR/hawcmox_logo.png"
SOURCE_CSS="$DATA_DIR/hawcmox.css"
TARGET_LOGO="/usr/share/pve-manager/images/hawcmox_logo.png"
TARGET_CSS="/usr/share/pve-manager/css/hawcmox.css"
TEMPLATE_FILE="/usr/share/pve-manager/index.html.tpl"

BRAND_TITLE="HAWCMOX"
[ -s "$CONFIG_FILE" ] && BRAND_TITLE="$(head -n 1 "$CONFIG_FILE")"

escape_sed_replacement() {
    printf '%s' "$1" | sed 's/[\/&|\\]/\\&/g'
}

[ -f "$SOURCE_LOGO" ] && cp -f "$SOURCE_LOGO" "$TARGET_LOGO" && chmod 644 "$TARGET_LOGO"
[ -f "$SOURCE_CSS" ] && cp -f "$SOURCE_CSS" "$TARGET_CSS" && chmod 644 "$TARGET_CSS"

if [ -f "$TEMPLATE_FILE" ]; then
    escaped_title="$(escape_sed_replacement "$BRAND_TITLE")"
    sed -i "s|<title>[^<]*</title>|<title>${escaped_title}</title>|" "$TEMPLATE_FILE"
    
    # Inject CSS
    if ! grep -q 'css/hawcmox.css' "$TEMPLATE_FILE"; then
        sed -i 's|</head>|    <link rel="stylesheet" type="text/css" href="/pve2/css/hawcmox.css">\n</head>|' "$TEMPLATE_FILE"
    fi

    # Inject JavaScript Observer to instantly hide "Virtual Environment X.X.X"
    if ! grep -q 'HAWCMOX_TEXT_REMOVAL' "$TEMPLATE_FILE"; then
        cat << 'EOF_JS' >> "$TEMPLATE_FILE"

<!-- HAWCMOX_TEXT_REMOVAL -->
<script type="text/javascript">
document.addEventListener("DOMContentLoaded", function() {
    const observer = new MutationObserver(function(mutations) {
        document.querySelectorAll('.x-title-text').forEach(function(title) {
            if (title.innerHTML.includes('Virtual Environment')) {
                title.innerHTML = title.innerHTML.replace(/Virtual Environment \d+\.\d+\.\d+/g, '');
            }
        });
    });
    observer.observe(document.body, { childList: true, subtree: true });
});
</script>
EOF_JS
    fi
fi

if command -v systemctl >/dev/null 2>&1; then
    systemctl restart pveproxy.service >/dev/null 2>&1 || true
fi
EOF_PATCH
chmod 755 "$PATCH_SCRIPT"

printf '[5/5] Applying customization...\n'
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
printf ' HAWCMOX CUSTOMIZATION COMPLETE\n'
printf '============================================================\n\n'
printf 'IMPORTANT: The backend service has been reloaded.\n'
printf 'To see the changes, you MUST clear your browser cache or perform a hard refresh:\n'
printf '  Windows/Linux: Ctrl + F5\n'
printf '  macOS:         Cmd + Shift + R\n'
printf '\nOr open the Proxmox UI in a Private/Incognito window to verify.\n'
