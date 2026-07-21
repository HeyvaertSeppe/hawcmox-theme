#!/bin/sh

# HAWCMOX Proxmox UI customization installer
# Visual customization only.
# Does not modify licensing, subscriptions, or repositories.

set -eu

DEFAULT_TITLE="HAWCMOX"
DEFAULT_LOGO_URL="https://raw.githubusercontent.com/HeyvaertSeppe/hawcmox-theme/main/proxmox_logo.png"

DATA_DIR="/usr/local/share/hawcmox"
PATCH_SCRIPT="/usr/local/bin/hawcmox-patch.sh"
APT_HOOK="/etc/apt/apt.conf.d/99hawcmox-theme"

LOGO_FILE="$DATA_DIR/proxmox_logo.png"
CSS_FILE="$DATA_DIR/hawcmox.css"
CONFIG_FILE="$DATA_DIR/config"

print_header() {
    printf '\n' >&2
    printf '%s\n' "============================================================" >&2
    printf '%s\n' " HAWCMOX Proxmox UI Customization Installer" >&2
    printf '%s\n' "============================================================" >&2
    printf '%s\n' "This script changes only the Proxmox title, logo, and theme." >&2
    printf '%s\n' "It does not modify licensing, subscriptions, or repositories." >&2
    printf '\n' >&2
}

ask_value() {
    prompt="$1"
    default_value="$2"
    
    printf '%s [%s]: ' "$prompt" "$default_value" >&2
    
    # Gracefully handle piped execution in Proxmox shell
    if [ -r /dev/tty ]; then
        IFS= read -r answer < /dev/tty || answer=""
    else
        answer=""
    fi

    if [ -z "$answer" ]; then
        answer="$default_value"
    fi

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

        if [ -z "$answer" ]; then
            answer="$default_answer"
        fi

        case "$answer" in
            y|Y|yes|YES|Yes)
                return 0
                ;;
            n|N|no|NO|No)
                return 1
                ;;
            *)
                printf '%s\n' "Please answer yes or no." >&2
                ;;
        esac
    done
}

download_file() {
    url="$1"
    destination="$2"
    temporary_file="${destination}.download"

    rm -f "$temporary_file"

    # Added -4 to force IPv4 and --retry to prevent "connection closed" drops on Proxmox nodes
    if command -v curl >/dev/null 2>&1; then
        curl -4 \
            --fail \
            --location \
            --silent \
            --show-error \
            --retry 3 \
            "$url" \
            --output "$temporary_file"
    elif command -v wget >/dev/null 2>&1; then
        wget -4 \
            --quiet \
            --tries=3 \
            --output-document="$temporary_file" \
            "$url"
    else
        printf '%s\n' "ERROR: Neither curl nor wget is installed."
        exit 1
    fi

    if [ ! -s "$temporary_file" ]; then
        rm -f "$temporary_file"
        printf '%s\n' "ERROR: The downloaded logo file is empty. Check your URL."
        exit 1
    fi

    mv "$temporary_file" "$destination"
}

print_header

if [ "$(id -u)" -ne 0 ]; then
    printf '%s\n' "ERROR: This script must be run as root."
    exit 1
fi

if [ ! -d "/usr/share/pve-manager" ]; then
    printf '%s\n' "ERROR: This does not appear to be a Proxmox VE node."
    exit 1
fi

BRAND_TITLE="$(ask_value "Browser title/brand name" "$DEFAULT_TITLE")"
LOGO_URL="$(ask_value "Direct URL of the PNG logo" "$DEFAULT_LOGO_URL")"

printf '\n' >&2
if ask_yes_no "Reapply the customization automatically after package updates?" "y"; then
    INSTALL_APT_HOOK="yes"
else
    INSTALL_APT_HOOK="no"
fi

printf '\n' >&2
printf '%s\n' "Customization summary:" >&2
printf '  Title:           %s\n' "$BRAND_TITLE" >&2
printf '  Logo URL:        %s\n' "$LOGO_URL" >&2
printf '  Persistent hook: %s\n' "$INSTALL_APT_HOOK" >&2
printf '\n' >&2

if ! ask_yes_no "Apply these changes now?" "y"; then
    printf '%s\n' "Installation cancelled."
    exit 0
fi

printf '\n'
printf '%s\n' "[1/5] Creating the HAWCMOX data directory..."
mkdir -p "$DATA_DIR"
chmod 755 "$DATA_DIR"

printf '%s\n' "[2/5] Downloading the custom logo..."
download_file "$LOGO_URL" "$LOGO_FILE"
chmod 644 "$LOGO_FILE"

printf '%s\n' "[3/5] Generating the custom CSS theme..."
# Stripped all colors, keeping only border-radius for the original grey theme
cat > "$CSS_FILE" <<'EOF_CSS'
/* HAWCMOX - Rounded Proxmox Theme (Original Grey Colors) */

.x-panel,
.x-window,
.x-panel-default,
.x-window-default {
    border-radius: 8px !important;
}

.x-panel-header,
.x-window-header {
    border-radius: 8px 8px 0 0 !important;
}

.x-btn {
    border-radius: 6px !important;
}

.x-form-text,
.x-form-text-default {
    border-radius: 4px !important;
}
EOF_CSS

chmod 644 "$CSS_FILE"
printf '%s\n' "$BRAND_TITLE" > "$CONFIG_FILE"
chmod 644 "$CONFIG_FILE"

printf '%s\n' "[4/5] Creating the persistent customization patcher..."
cat > "$PATCH_SCRIPT" <<'EOF_PATCH'
#!/bin/sh
set -eu

DATA_DIR="/usr/local/share/hawcmox"
CONFIG_FILE="$DATA_DIR/config"
SOURCE_LOGO="$DATA_DIR/proxmox_logo.png"
SOURCE_CSS="$DATA_DIR/hawcmox.css"
TARGET_LOGO="/usr/share/pve-manager/images/proxmox_logo.png"
TARGET_CSS="/usr/share/pve-manager/css/hawcmox.css"
TEMPLATE_FILE="/usr/share/pve-manager/index.html.tpl"

BRAND_TITLE="HAWCMOX"

if [ -s "$CONFIG_FILE" ]; then
    configured_title="$(head -n 1 "$CONFIG_FILE")"
    [ -n "$configured_title" ] && BRAND_TITLE="$configured_title"
fi

escape_sed_replacement() {
    printf '%s' "$1" | sed 's/[\/&|\\]/\\&/g'
}

if [ -f "$SOURCE_LOGO" ] && [ -d "$(dirname "$TARGET_LOGO")" ]; then
    cp -f "$SOURCE_LOGO" "$TARGET_LOGO"
    chmod 644 "$TARGET_LOGO"
fi

if [ -f "$SOURCE_CSS" ] && [ -d "$(dirname "$TARGET_CSS")" ]; then
    cp -f "$SOURCE_CSS" "$TARGET_CSS"
    chmod 644 "$TARGET_CSS"
fi

if [ -f "$TEMPLATE_FILE" ]; then
    escaped_title="$(escape_sed_replacement "$BRAND_TITLE")"
    sed -i "s|<title>[^<]*</title>|<title>${escaped_title}</title>|" "$TEMPLATE_FILE"
    
    if ! grep -q 'css/hawcmox.css' "$TEMPLATE_FILE"; then
        sed -i 's|</head>|    <link rel="stylesheet" type="text/css" href="/pve2/css/hawcmox.css">\n</head>|' "$TEMPLATE_FILE"
    fi
fi

# Force restart to guarantee the backend serves the new files immediately
if command -v systemctl >/dev/null 2>&1; then
    systemctl restart pveproxy.service >/dev/null 2>&1 || true
fi
EOF_PATCH

chmod 755 "$PATCH_SCRIPT"

printf '%s\n' "[5/5] Applying the customization..."

if [ "$INSTALL_APT_HOOK" = "yes" ]; then
    cat > "$APT_HOOK" <<'EOF_HOOK'
DPkg::Post-Invoke { "/usr/local/bin/hawcmox-patch.sh || true"; };
EOF_HOOK
    chmod 644 "$APT_HOOK"
else
    rm -f "$APT_HOOK"
fi

"$PATCH_SCRIPT"

printf '\n'
printf '%s\n' "============================================================"
printf '%s\n' " HAWCMOX CUSTOMIZATION COMPLETE"
printf '%s\n' "============================================================"
printf '\n'
printf '%s\n' "IMPORTANT: The backend service has been reloaded."
printf '%s\n' "To see the changes, you MUST clear your browser cache or perform a hard refresh:"
printf '%s\n' "  Windows/Linux: Ctrl + F5"
printf '%s\n' "  macOS:         Cmd + Shift + R"
printf '\n'
