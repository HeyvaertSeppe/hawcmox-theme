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
    printf '\n'
    printf '%s\n' "============================================================"
    printf '%s\n' " HAWCMOX Proxmox UI Customization Installer"
    printf '%s\n' "============================================================"
    printf '%s\n' "This script changes only the Proxmox title, logo, and theme."
    printf '%s\n' "It does not modify licensing, subscriptions, or repositories."
    printf '\n'
}

ask_value() {
    prompt="$1"
    default_value="$2"

    # Send the prompt to stderr so command substitution captures only
    # the value returned by this function.
    printf '%s [%s]: ' "$prompt" "$default_value" >&2
    IFS= read -r answer || answer=""

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

        IFS= read -r answer || answer=""

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

    case "$url" in
        http://*|https://*)
            ;;
        *)
            printf '%s\n' "ERROR: The logo URL must start with http:// or https://"
            exit 1
            ;;
    esac

    if command -v curl >/dev/null 2>&1; then
        curl \
            --fail \
            --location \
            --silent \
            --show-error \
            "$url" \
            --output "$temporary_file"
    elif command -v wget >/dev/null 2>&1; then
        wget \
            --quiet \
            --output-document="$temporary_file" \
            "$url"
    else
        printf '%s\n' "ERROR: Neither curl nor wget is installed."
        printf '%s\n' "Install curl or wget and run this script again."
        exit 1
    fi

    if [ ! -s "$temporary_file" ]; then
        rm -f "$temporary_file"
        printf '%s\n' "ERROR: The downloaded logo file is empty."
        exit 1
    fi

    mv "$temporary_file" "$destination"
}

print_header

if [ "$(id -u)" -ne 0 ]; then
    printf '%s\n' "ERROR: This script must be run as root."
    printf '%s\n' "Example: sudo ./hawcmox-installer.sh"
    exit 1
fi

if [ ! -d "/usr/share/pve-manager" ]; then
    printf '%s\n' "ERROR: This does not appear to be a Proxmox VE node."
    printf '%s\n' "The directory /usr/share/pve-manager was not found."
    exit 1
fi

printf '%s\n' "Enter the desired customization settings."
printf '%s\n' "Press Enter to accept a value shown between brackets."
printf '\n'

BRAND_TITLE="$(ask_value "Browser title/brand name" "$DEFAULT_TITLE")"
printf '\n'

LOGO_URL="$(ask_value "Direct URL of the PNG logo" "$DEFAULT_LOGO_URL")"
printf '\n\n'

if ask_yes_no \
    "Reapply the customization automatically after package updates?" \
    "y"
then
    INSTALL_APT_HOOK="yes"
else
    INSTALL_APT_HOOK="no"
fi

printf '\n'
printf '%s\n' "Customization summary:"
printf '  Title:           %s\n' "$BRAND_TITLE"
printf '  Logo URL:        %s\n' "$LOGO_URL"
printf '  Persistent hook: %s\n' "$INSTALL_APT_HOOK"
printf '\n'

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

cat > "$CSS_FILE" <<'EOF_CSS'
/* HAWCMOX - Dark Blue and Rounded Proxmox Theme */

.x-body,
.x-viewport,
.x-panel-body,
.x-layout-container {
    background-color: #0b1325 !important;
    color: #e2e8f0 !important;
}

.x-panel,
.x-window,
.x-panel-default,
.x-window-default {
    background-color: #152238 !important;
    border: 1px solid #1e3a5f !important;
    border-radius: 12px !important;
    overflow: hidden !important;
}

.x-panel-header,
.x-window-header {
    background-color: #1e3a5f !important;
    border: none !important;
    border-radius: 12px 12px 0 0 !important;
}

.x-title-text,
.x-panel-header-text {
    color: #ffffff !important;
    font-weight: bold !important;
}

.x-btn {
    background-color: #2563eb !important;
    border: none !important;
    border-radius: 8px !important;
}

.x-btn-inner,
.x-btn-icon-el {
    color: #ffffff !important;
}

.x-grid-body {
    background-color: #152238 !important;
}

.x-grid-item {
    background-color: #152238 !important;
    color: #cbd5e1 !important;
}

.x-grid-item-alt {
    background-color: #1a2942 !important;
}

.x-grid-header-ct {
    background-color: #1e3a5f !important;
}

.x-form-text,
.x-form-text-default {
    background-color: #0b1325 !important;
    border: 1px solid #3b82f6 !important;
    border-radius: 6px !important;
    color: #ffffff !important;
}

.x-treelist-nav {
    background-color: #0b1325 !important;
}
EOF_CSS

chmod 644 "$CSS_FILE"

# Save the selected browser title.
printf '%s\n' "$BRAND_TITLE" > "$CONFIG_FILE"
chmod 644 "$CONFIG_FILE"

printf '%s\n' "[4/5] Creating the persistent customization patcher..."

cat > "$PATCH_SCRIPT" <<'EOF_PATCH'
#!/bin/sh

# Reapplies the HAWCMOX visual customization after Proxmox updates.

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

    if [ -n "$configured_title" ]; then
        BRAND_TITLE="$configured_title"
    fi
fi

escape_sed_replacement() {
    printf '%s' "$1" | sed 's/[\/&|\\]/\\&/g'
}

if [ ! -d "/usr/share/pve-manager" ]; then
    printf '%s\n' "HAWCMOX: Proxmox UI directory was not found."
    exit 0
fi

if [ -f "$SOURCE_LOGO" ]; then
    if [ -d "$(dirname "$TARGET_LOGO")" ]; then
        cp -f "$SOURCE_LOGO" "$TARGET_LOGO"
        chmod 644 "$TARGET_LOGO"
    else
        printf '%s\n' "HAWCMOX: Proxmox image directory was not found."
    fi
else
    printf '%s\n' "HAWCMOX: Source logo was not found."
fi

if [ -f "$SOURCE_CSS" ]; then
    if [ -d "$(dirname "$TARGET_CSS")" ]; then
        cp -f "$SOURCE_CSS" "$TARGET_CSS"
        chmod 644 "$TARGET_CSS"
    else
        printf '%s\n' "HAWCMOX: Proxmox CSS directory was not found."
    fi
else
    printf '%s\n' "HAWCMOX: Source CSS file was not found."
fi

if [ -f "$TEMPLATE_FILE" ]; then
    escaped_title="$(escape_sed_replacement "$BRAND_TITLE")"

    if grep -q '<title>[^<]*</title>' "$TEMPLATE_FILE"; then
        sed -i \
            "s|<title>[^<]*</title>|<title>${escaped_title}</title>|" \
            "$TEMPLATE_FILE"
    else
        printf '%s\n' "HAWCMOX: No HTML title element was found."
    fi

    if ! grep -q 'css/hawcmox.css' "$TEMPLATE_FILE"; then
        if grep -q '</head>' "$TEMPLATE_FILE"; then
            sed -i \
                's|</head>|    <link rel="stylesheet" type="text/css" href="/pve2/css/hawcmox.css">\n</head>|' \
                "$TEMPLATE_FILE"
        else
            printf '%s\n' "HAWCMOX: No closing HTML head element was found."
        fi
    fi
else
    printf '%s\n' "HAWCMOX: Proxmox HTML template was not found."
fi

if command -v systemctl >/dev/null 2>&1; then
    systemctl try-restart pveproxy.service >/dev/null 2>&1 || true
fi

printf '%s\n' "HAWCMOX: UI customization applied."
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
printf '%s\n' "No licensing or subscription files were modified."
printf '%s\n' "No APT repositories were modified."
printf '\n'
printf '%s\n' "Clear your browser cache or perform a hard refresh:"
printf '%s\n' "  Windows/Linux: Ctrl+F5"
printf '%s\n' "  macOS:         Cmd+Shift+R"
printf '\n'
printf '%s\n' "To reapply the theme manually, run:"
printf '%s\n' "  /usr/local/bin/hawcmox-patch.sh"
