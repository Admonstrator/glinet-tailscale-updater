#!/bin/sh
# shellcheck shell=ash
# shellcheck disable=SC3036
# Description: This script updates tailscale on GL.iNet routers
# Thread: https://forum.gl-inet.com/t/how-to-update-tailscale-on-arm64/37582
# Author: Admon
SCRIPT_VERSION="2026.02.02.01"
SCRIPT_NAME="update-tailscale.sh"
UPDATE_URL="https://get.admon.me/tailscale-update"
TAILSCALE_TINY_URL="https://github.com/Admonstrator/glinet-tailscale-updater/releases/latest/download/"

# ==============================================================================
# Variables & Constants
# ==============================================================================

# User Preferences (Defaults)
IGNORE_FREE_SPACE=0
FORCE=0
FORCE_UPGRADE=0
RESTORE=0
UPX_ERROR=0
NO_UPX=0
NO_DOWNLOAD=0
NO_TINY=0
SELECT_RELEASE=0
SHOW_LOG=0
ASCII_MODE=0
TESTING=0
ENABLE_SSH=0
SKIP_CONFIG=0

# Runtime Variables
USER_WANTS_UPX=""
USER_WANTS_SSH=""
USER_WANTS_PERSISTENCE=""

# Constants - Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
INFO='\033[0m' # No Color

# ==============================================================================
# Helper Functions
# ==============================================================================

log() {
    local level=$1
    local message=$2
    local timestamp
    timestamp=$(date +"%Y-%m-%d %H:%M:%S")
    local color=$INFO # Default to no color
    local symbol=""

    # Assign color and symbol based on level
    case "$level" in
    ERROR)
        color=$RED
        if [ "$ASCII_MODE" -eq 1 ]; then
            symbol="[X] "
        else
            symbol="❌ "
        fi
        ;;
    WARNING)
        color=$YELLOW
        if [ "$ASCII_MODE" -eq 1 ]; then
            symbol="[!] "
        else
            symbol="⚠️  "
        fi
        ;;
    SUCCESS)
        color=$GREEN
        if [ "$ASCII_MODE" -eq 1 ]; then
            symbol="[OK] "
        else
            symbol="✅ "
        fi
        ;;
    INFO)
        if [ "$ASCII_MODE" -eq 1 ]; then
            symbol="[->] "
        else
            symbol="ℹ️  "
        fi
        ;;
    esac

    # Build output with or without timestamp
    if [ "$SHOW_LOG" -eq 1 ]; then
        printf "${color}[$timestamp] $symbol$message${INFO}\n"
    else
        printf "${color}$symbol$message${INFO}\n"
    fi
}

# ==============================================================================
# System Checks & Pre-flight
# ==============================================================================

preflight_check() {
    AVAILABLE_SPACE=$(df -P -k / | tail -n 1 | awk '{print $4/1024}')
    AVAILABLE_SPACE=$(printf "%.0f" "$AVAILABLE_SPACE")
    ARCH=$(uname -m)
    # Check if this is a GL.iNet router or regular OpenWrt
    if [ -f "/etc/glversion" ]; then
        FIRMWARE_VERSION=$(cut -c1 </etc/glversion)
        IS_GLINET=1
    else
        FIRMWARE_VERSION=0
        IS_GLINET=0
    fi
    PREFLIGHT=0
    TINY_ARCH=""

    log "INFO" "Checking if prerequisites are met"
    if [ "$IS_GLINET" -eq 1 ] && [ "${FIRMWARE_VERSION}" -lt 4 ]; then
        log "ERROR" "This script only works on GL.iNet firmware version 4 or higher."
        PREFLIGHT=1
    elif [ "$IS_GLINET" -eq 1 ]; then
        log "SUCCESS" "GL.iNet firmware version: $FIRMWARE_VERSION"
    else
        log "SUCCESS" "OpenWrt system detected"
    fi
    if [ "$ARCH" = "aarch64" ]; then
        TINY_ARCH="arm64"
        log "SUCCESS" "Architecture: arm64"
    elif [ "$ARCH" = "armv7l" ]; then
        TINY_ARCH="arm"
        log "SUCCESS" "Architecture: armv7"
    elif [ "$ARCH" = "x86_64" ]; then
        TINY_ARCH="amd64"
        log "SUCCESS" "Architecture: x86_64"
    elif [ "$ARCH" = "mips" ]; then
        # Determine from OpenWrt release info if devices uses mipsle architecture
        MIPS_ARCH=$(sed -n "s/^DISTRIB_ARCH='\(.*\)_.*'$/\1/p" /etc/openwrt_release)
        case "$MIPS_ARCH" in
            "mipsel" | "mips_24kc")
                TINY_ARCH="mipsle"
                log "SUCCESS" "Architecture: mipsle"
                ;;
            *)
                TINY_ARCH="mips"
                log "SUCCESS" "Architecture: mips"
                ;;
        esac
    else
        log "ERROR" "This script only works on arm64, armv7, x86_64, mips and mipsle"
        PREFLIGHT=1
    fi
    if [ "$AVAILABLE_SPACE" -lt 15 ]; then
        log "ERROR" "Not enough space available. Please free up some space and try again."
        log "ERROR" "The script needs at least 15 MB of free space. Available space: $AVAILABLE_SPACE MB"
        log "ERROR" "If you want to continue, you can use --ignore-free-space to ignore this check."
        if [ "$IGNORE_FREE_SPACE" -eq 1 ]; then
            log "WARNING" "--ignore-free-space flag is used. Continuing without enough space"
            log "WARNING" "Current available space: $AVAILABLE_SPACE MB"
        else
            PREFLIGHT=1
        fi
    else
        log "SUCCESS" "Available space: $AVAILABLE_SPACE MB"
    fi
    # Check if xz is present
    if ! command -v xz >/dev/null; then
        log "WARNING" "xz is not installed. We can install it for you later."
    else
        log "SUCCESS" "xz is installed."
    fi
    # Check if wget is present
    if ! command -v wget >/dev/null; then
        log "ERROR" "wget is not installed. Exiting"
        PREFLIGHT=1
    else
        log "SUCCESS" "wget is installed."
    fi

    if [ "$PREFLIGHT" -eq "1" ]; then
        log "ERROR" "Prerequisites are not met. Exiting"
        exit 1
    else
        log "SUCCESS" "Prerequisites are met."
    fi
}

backup() {
    log "INFO" "Creating backup of tailscale config"
    TIMESTAMP=$(date +"%Y-%m-%d_%H-%M-%S")
    if [ ! -d "/root/tailscale_config_backup" ]; then
        mkdir "/root/tailscale_config_backup"
    fi
    tar czf "/root/tailscale_config_backup/$TIMESTAMP.tar.gz" -C "/" "etc/config/tailscale"
    log "SUCCESS" "Backup created: /root/tailscale_config_backup/$TIMESTAMP.tar.gz"
    log "INFO" "The binaries will not be backed up, you can restore them by using the --restore flag."
}

# ==============================================================================
# Update Logic (Download, Compress, Install)
# ==============================================================================

get_latest_tailscale_version_tiny() {
    # Will attempt to download the latest version of tailscale from the updater repository
    # This is the default behavior
    log "INFO" "Detecting latest tiny tailscale version"
    TAILSCALE_VERSION_NEW=$(wget -qO- "$TAILSCALE_TINY_URL/version.txt")
    if [ -z "$TAILSCALE_VERSION_NEW" ]; then
        log "ERROR" "Could not get latest tailscale version. Please check your internet connection."
        exit 1
    fi
    TAILSCALE_VERSION_OLD="$(tailscale --version | head -1)"
    if [ "$TAILSCALE_VERSION_NEW" = "$TAILSCALE_VERSION_OLD" ] && [ "$FORCE_UPGRADE" -eq 0 ]; then
        log "SUCCESS" "You already on the latest version: $TAILSCALE_VERSION_OLD"
        log "INFO" "You can force reinstall with the --force-upgrade flag."
        log "INFO" "If you encounter issues while using the tiny version, please use the normal version."
        log "INFO" "You can do this by using the --no-tiny flag."
        log "INFO" "Make sure to have enough space available. The normal version needs at least 50 MB."
        exit 0
    elif [ "$TAILSCALE_VERSION_NEW" = "$TAILSCALE_VERSION_OLD" ] && [ "$FORCE_UPGRADE" -eq 1 ]; then
        log "WARNING" "--force-upgrade flag is used. Continuing with reinstallation"
    fi
    log "INFO" "The latest tailscale version is: $TAILSCALE_VERSION_NEW"
    log "INFO" "Downloading latest tailscale version"
    wget -q -O "/tmp/tailscaled-linux-$TINY_ARCH" "$TAILSCALE_TINY_URL/tailscaled-linux-$TINY_ARCH"
    # Check if download was successful
    if [ ! -f "/tmp/tailscaled-linux-$TINY_ARCH" ]; then
        log "ERROR" "Could not download tailscale. Exiting"
        log "ERROR" "File not found: /tmp/tailscaled-linux-$TINY_ARCH"
        exit 1
    fi
}

get_latest_tailscale_version() {
    if [ -d "/tmp/tailscale" ]; then
        rm -rf /tmp/tailscale
    fi
    mkdir /tmp/tailscale
    if [ "$NO_DOWNLOAD" -eq 1 ]; then
        log "INFO" "--no-download flag is used. Skipping download of tailscale"
        log "INFO" "Please download the tailscale archive manually and place it in /tmp/tailscale.tar.gz"
        TAILSCALE_VERSION_NEW="manually"
    else
        log "INFO" "Detecting latest tailscale version"
        if [ "$ARCH" = "aarch64" ]; then
            TAILSCALE_VERSION_NEW=$(wget -qO- https://pkgs.tailscale.com/stable/ | grep -o 'tailscale_[0-9]*\.[0-9]*\.[0-9]*_arm64\.tgz' | head -n 1)
        elif [ "$ARCH" = "armv7l" ]; then
            TAILSCALE_VERSION_NEW=$(wget -qO- https://pkgs.tailscale.com/stable/ | grep -o 'tailscale_[0-9]*\.[0-9]*\.[0-9]*_arm\.tgz' | head -n 1)
        elif [ "$ARCH" = "x86_64" ]; then
            TAILSCALE_VERSION_NEW=$(wget -qO- https://pkgs.tailscale.com/stable/ | grep -o 'tailscale_[0-9]*\.[0-9]*\.[0-9]*_amd64\.tgz' | head -n 1)
        elif [ "$ARCH" = "mips" ]; then
            MIPS_ARCH=$(sed -n "s/^DISTRIB_ARCH='\(.*\)_.*'$/\1/p" /etc/openwrt_release)
            case "$MIPS_ARCH" in
                "mipsel" | "mips_24kc")
                    TAILSCALE_VERSION_NEW=$(wget -qO- https://pkgs.tailscale.com/stable/ | grep -o 'tailscale_[0-9]*\.[0-9]*\.[0-9]*_mipsle\.tgz' | head -n 1)
                    ;;
                *)
                    TAILSCALE_VERSION_NEW=$(wget -qO- https://pkgs.tailscale.com/stable/ | grep -o 'tailscale_[0-9]*\.[0-9]*\.[0-9]*_mips\.tgz' | head -n 1)
                    ;;
            esac
        fi
        if [ -z "$TAILSCALE_VERSION_NEW" ]; then
            log "ERROR" "Could not get latest tailscale version. Please check your internet connection."
            exit 1
        fi
        TAILSCALE_VERSION_OLD="$(tailscale --version | head -1)"
        if [ "$TAILSCALE_VERSION_NEW" = "$TAILSCALE_VERSION_OLD" ] && [ "$FORCE_UPGRADE" -eq 0 ]; then
            log "SUCCESS" "You already have the latest version."
            exit 0
        elif [ "$TAILSCALE_VERSION_NEW" = "$TAILSCALE_VERSION_OLD" ] && [ "$FORCE_UPGRADE" -eq 1 ]; then
            log "WARNING" "--force-upgrade flag is used. Continuing with reinstallation"
        fi
        log "INFO" "The latest tailscale version is: $TAILSCALE_VERSION_NEW"
        log "INFO" "Downloading latest tailscale version"
        wget -q -O /tmp/tailscale.tar.gz "https://pkgs.tailscale.com/stable/$TAILSCALE_VERSION_NEW"
        # Check if download was successful
    fi
    if [ ! -f "/tmp/tailscale.tar.gz" ]; then
        log "ERROR" "Could not download tailscale. Exiting"
        log "ERROR" "File not found: /tmp/tailscale.tar.gz"
        exit 1
    fi

    log "INFO" "Finding tailscale binaries in archive"
    TAILSCALE_SUBDIR_IN_TAR=$(tar tzf /tmp/tailscale.tar.gz | grep /$ | head -n 1)
    TAILSCALE_SUBDIR_IN_TAR=${TAILSCALE_SUBDIR_IN_TAR%/}
    if [ -z "$TAILSCALE_SUBDIR_IN_TAR" ]; then
        log "ERROR" "Could not find tailscale binaries in archive. Exiting"
        exit 1
    fi
    log "SUCCESS" "Found tailscale binaries in: $TAILSCALE_SUBDIR_IN_TAR"
    # Use the pre-collected user preference for UPX compression
    if [ "$USER_WANTS_UPX" != "${USER_WANTS_UPX#[y]}" ]; then
        log "INFO" "Compressing binaries with UPX as requested"
        compress_binaries
        if [ "$UPX_ERROR" -eq 1 ]; then
            log "ERROR" "Could not compress tailscale with UPX. Continuing without compression"
            tar xzf /tmp/tailscale.tar.gz -C /tmp/tailscale
        fi
    else
        log "INFO" "Extracting tailscale without compression"
        tar xzf /tmp/tailscale.tar.gz -C /tmp/tailscale
    fi

    # Removing archive
    rm /tmp/tailscale.tar.gz
}

compress_binaries() {
    log "INFO" "Ensuring xz is present and installing if necessary"
    opkg update --verbosity=0
    opkg install --verbosity=0 xz
    if command -v xz >/dev/null; then
        log "SUCCESS" "xz is installed."
    else
        log "ERROR" "xz is not installed. Skipping compression"
        UPX_ERROR=1
        return 1
    fi
    log "INFO" "Getting UPX"
    upx_version="$(
        wget -qO- "https://api.github.com/repos/upx/upx/releases/latest" |
            grep 'tag_name' |
            cut -d : -f 2 |
            tr -d '"v, '
    )"

    if [ "$ARCH" = "aarch64" ]; then
        UPX_ARCH="arm64"
    elif [ "$ARCH" = "armv7l" ]; then
        UPX_ARCH="arm"
    elif [ "$ARCH" = "x86_64" ]; then
        UPX_ARCH="amd64"
    elif [ "$ARCH" = "mips" ]; then
        UPX_ARCH="$ARCH"
    fi

    wget -q -O "/tmp/upx.tar.xz" \
        "https://github.com/upx/upx/releases/download/v${upx_version}/upx-${upx_version}-${UPX_ARCH}_linux.tar.xz"

    # If download fails, skip compression
    if [ ! -f "/tmp/upx.tar.xz" ]; then
        log "ERROR" "Could not download UPX. Skipping compression"
        log "WARNING" "Extracting tailscale without compression"
        UPX_ERROR=1
    else
        # Extract only the upx binary
        unxz --decompress --stdout "/tmp/upx.tar.xz" |
            tar x -C "/tmp/" "upx-${upx_version}-${UPX_ARCH}_linux/upx"
        mv "/tmp/upx-${upx_version}-${UPX_ARCH}_linux/upx" "/tmp/upx"
        rmdir "/tmp/upx-${upx_version}-${UPX_ARCH}_linux"
        rm "/tmp/upx.tar.xz"
        # Check if the upx binary is present
        if [ ! -f "/tmp/upx" ]; then
            log "ERROR" "Could not find UPX binary. Skipping compression"
            UPX_ERROR=1
        fi
        tar xzf "/tmp/tailscale.tar.gz" "$TAILSCALE_SUBDIR_IN_TAR/tailscale" \
            -C "/tmp/tailscale"
        log "INFO" "Compressing tailscale with UPX"
        log "INFO" "This might take 2-3 minutes, depending on your router."
        /usr/bin/time -f %e /tmp/upx --lzma "/tmp/tailscale/$TAILSCALE_SUBDIR_IN_TAR/tailscale"

        tar xzf "/tmp/tailscale.tar.gz" "$TAILSCALE_SUBDIR_IN_TAR/tailscaled" \
            -C "/tmp/tailscale"
        # Takes 107.92s on GL-AXT1800
        log "INFO" "Compressing tailscaled with UPX"
        log "INFO" "This might take 2-3 minutes, depending on your router."
        /usr/bin/time -f %e /tmp/upx --lzma "/tmp/tailscale/$TAILSCALE_SUBDIR_IN_TAR/tailscaled"
        # Clean up
        if [ -f "/tmp/upx" ]; then
            rm "/tmp/upx"
        fi
    fi
}

install_tailscale() {
    # Stop tailscale
    stop_tailscale
    # Moving tailscale to /usr/sbin
    log "INFO" "Moving tailscale to /usr/sbin"
    # Check if tailscale binary is present
    if [ ! -f "/tmp/tailscale/$TAILSCALE_SUBDIR_IN_TAR/tailscale" ]; then
        log "ERROR" "Tailscale binary not found. Exiting"
        exit 1
    fi
    if [ ! -f "/tmp/tailscale/$TAILSCALE_SUBDIR_IN_TAR/tailscaled" ]; then
        log "ERROR" "Tailscaled binary not found. Exiting"
        exit 1
    fi
    mv /tmp/tailscale/$TAILSCALE_SUBDIR_IN_TAR/tailscale /usr/sbin/tailscale
    mv /tmp/tailscale/$TAILSCALE_SUBDIR_IN_TAR/tailscaled /usr/sbin/tailscaled
    # Remove temporary files
    log "INFO" "Removing temporary files"
    rm -rf /tmp/tailscale
}

install_tiny_tailscale() {
    # Stop tailscale
    stop_tailscale
    # Moving tailscale to /usr/sbin
    log "INFO" "Moving tailscale to /usr/sbin"
    # Check if tailscale binary is present
    if [ ! -f "/tmp/tailscaled-linux-$TINY_ARCH" ]; then
        log "ERROR" "Tailscaled binary not found. Exiting"
        exit 1
    fi
    mv /tmp/tailscaled-linux-$TINY_ARCH /usr/sbin/tailscaled
    # Create symlink for tailscale
    ln -sf /usr/sbin/tailscaled /usr/sbin/tailscale
    # Make the binary executable
    chmod +x /usr/sbin/tailscaled
    # Remove temporary files
    log "INFO" "Removing temporary files"
    rm -rf /tmp/tailscaled-linux-$TINY_ARCH
    # Restart tailscale
    start_tailscale
}

# ==============================================================================
# Configuration & Persistence
# ==============================================================================

upgrade_persistance() {
    if [ "$IS_GLINET" -eq 1 ]; then
        # Use the pre-collected user preference for persistence
        if [ "$USER_WANTS_PERSISTENCE" != "${USER_WANTS_PERSISTENCE#[y]}" ]; then
            log "INFO" "Making installation permanent"
            log "INFO" "Modifying /etc/sysupgrade.conf"
            if grep -q "/root/tailscale_config_backup/" /etc/sysupgrade.conf; then
                sed -i '/\/root\/tailscale_config_backup\//d' /etc/sysupgrade.conf
            fi
            if ! grep -q "/root/tailscale_config_backup/$TIMESTAMP.tar.gz" /etc/sysupgrade.conf; then
                echo "/root/tailscale_config_backup/$TIMESTAMP.tar.gz" >>/etc/sysupgrade.conf
            fi
            if ! grep -q "/usr/sbin/tailscale" /etc/sysupgrade.conf; then
                echo "/usr/sbin/tailscale" >>/etc/sysupgrade.conf
            fi
            if ! grep -q "/usr/sbin/tailscaled" /etc/sysupgrade.conf; then
                echo "/usr/sbin/tailscaled" >>/etc/sysupgrade.conf
            fi
            if ! grep -q "/etc/config/tailscale" /etc/sysupgrade.conf; then
                echo "/etc/config/tailscale" >>/etc/sysupgrade.conf
            fi
            if ! grep -q "/usr/bin/gl_tailscale" /etc/sysupgrade.conf; then
                echo "/usr/bin/gl_tailscale" >>/etc/sysupgrade.conf
            fi
        fi
    else
        log "INFO" "OpenWrt detected - installation is already persistent"
        log "INFO" "No additional steps needed for persistence on OpenWrt"
    fi
}

invoke_modify_script() {
    if [ "$IS_GLINET" -eq 1 ] && [ -f "/usr/bin/gl_tailscale" ]; then
        if [ "$SKIP_CONFIG" -eq 1 ]; then
            log "WARNING" "Skipping automatic modification of gl_tailscale script as requested."
            log "INFO" "Please manually apply the following changes:"
            echo ""
            echo "1. Edit /usr/bin/gl_tailscale and find the line starting with 'param=\"--advertise-routes=\$routes\"'"
            echo "   Change it to: param=\"--advertise-routes=\$routes --stateful-filtering=false\""
            echo ""
            if [ "$USER_WANTS_SSH" != "${USER_WANTS_SSH#[y]}" ]; then
                echo "2. To enable SSH, run the following commands:"
                echo "   uci set tailscale.settings.ssh_enabled=1"
                echo "   uci commit tailscale"
                echo ""
                echo "3. Add the following block to /usr/bin/gl_tailscale after the function 'add_guest_policy_route':"
                echo '        ssh_enabled=$(uci -q get tailscale.settings.ssh_enabled)'
                echo '        if [ "$ssh_enabled" = "1" ]; then'
                echo '            param="$param --ssh"'
                echo '        fi'
            fi
            return 0
        fi

        log "INFO" "Modifying gl_tailscale script to work with the new tailscale version"
        # Restore original gl_tailscale script from rom first
        if [ -f "/rom/usr/bin/gl_tailscale" ]; then
            cp /rom/usr/bin/gl_tailscale /usr/bin/gl_tailscale
            log "SUCCESS" "gl_tailscale script restored from /rom"
        else
            log "WARNING" "gl_tailscale script not found in /rom, proceeding with existing script"
        fi
        # Search for param="--advertise-routes=$routes" and add --stateful-filtering=false 
        sed -i 's|param="--advertise-routes=$routes"|param="--advertise-routes=$routes --stateful-filtering=false"|g' /usr/bin/gl_tailscale

        # Use the pre-collected user preference for SSH
        if [ "$USER_WANTS_SSH" != "${USER_WANTS_SSH#[y]}" ]; then
            log "INFO" "Enabling Tailscale SSH support"
            # Check if the pattern to insert after exists
            if ! grep -q "add_guest_policy_route" /usr/bin/gl_tailscale; then
                log "ERROR" "Could not find 'add_guest_policy_route' in gl_tailscale script"
                log "ERROR" "SSH support cannot be enabled automatically"
                log "INFO" "You may need to add it manually"
            else
                # Set UCI config value
                uci set tailscale.settings.ssh_enabled=1
                uci commit tailscale
                # Insert SSH check snippet before the tailscale up command
                sed -i '/add_guest_policy_route/a\\n        ssh_enabled=$(uci -q get tailscale.settings.ssh_enabled)\n        if [ "$ssh_enabled" = "1" ]; then\n            param="$param --ssh"\n        fi' /usr/bin/gl_tailscale
                # Verify that the snippet was inserted successfully
                if grep -q "ssh_enabled=\$(uci -q get tailscale.settings.ssh_enabled)" /usr/bin/gl_tailscale; then
                    log "SUCCESS" "SSH support enabled in gl_tailscale script"
                else
                    log "ERROR" "Failed to insert SSH snippet into gl_tailscale script"
                    log "INFO" "You may need to add it manually"
                fi
            fi
        else
            log "INFO" "SSH support not enabled"
            uci set tailscale.settings.ssh_enabled=0
            uci commit tailscale
        fi

        log "SUCCESS" "gl_tailscale script modified successfully"
    else
        log "INFO" "Not a GL.iNet router or gl_tailscale script not found, skipping GL-specific modifications"
    fi
}

# ==============================================================================
# Service Management
# ==============================================================================

restart_tailscale() {
    stop_tailscale
    start_tailscale
}

start_tailscale() {
    log "INFO" "Starting tailscale"
    # Only on GL.iNet routers, use gl_tailscale to start
    if [ -f "/usr/bin/gl_tailscale" ]; then
        /usr/bin/gl_tailscale restart 2>/dev/null
        sleep 3
        return
    else
        /etc/init.d/tailscale start 2>/dev/null
        sleep 3
        return
    fi
}

stop_tailscale() {
    log "INFO" "Stopping tailscale"
    # Only on GL.iNet routers, use gl_tailscale to stop
    if [ -f "/usr/bin/gl_tailscale" ]; then
        /usr/bin/gl_tailscale stop 2>/dev/null
        sleep 3
        return
    else
        /etc/init.d/tailscale stop 2>/dev/null
        sleep 3
        return
    fi
}

# ==============================================================================
# User Interaction & Special Modes
# ==============================================================================

invoke_help() {
    printf "\033[1mUsage:\033[0m \033[92m./update-tailscale.sh\033[0m [\033[93mOPTIONS\033[0m]\n"
    printf "\033[1mOptions:\033[0m\n"
    printf "  \033[93m--ignore-free-space\033[0m  \033[97mIgnore free space check\033[0m\n"
    printf "  \033[93m--force\033[0m              \033[97mDo not ask for confirmation\033[0m\n"
    printf "  \033[93m--force-upgrade\033[0m      \033[97mForce upgrade even if already up to date\033[0m\n"
    printf "  \033[93m--restore\033[0m            \033[97mRestore tailscale to factory default\033[0m\n"
    printf "  \033[93m--no-upx\033[0m             \033[97mDo not compress tailscale with UPX\033[0m\n"
    printf "  \033[93m--no-download\033[0m        \033[97mDo not download tailscale\033[0m\n"
    printf "  \033[93m--no-tiny\033[0m            \033[97mDo not use the tiny version of tailscale\033[0m\n"
    printf "  \033[93m--select-release\033[0m     \033[97mSelect a specific release version\033[0m\n"
    printf "  \033[93m--ssh\033[0m                \033[97mEnable Tailscale SSH support automatically\033[0m\n"
    printf "  \033[93m--skip-config\033[0m        \033[97mSkip automatic configuration and show manual steps instead\033[0m\n"
    printf "  \033[93m--testing\033[0m            \033[97mUse testing/prerelease versions from testing branch\033[0m\n"
    printf "  \033[93m--log\033[0m                \033[97mShow timestamps in log messages\033[0m\n"
    printf "  \033[93m--ascii\033[0m              \033[97mUse ASCII characters instead of emojis\033[0m\n"
    printf "  \033[93m--help\033[0m               \033[97mShow this help\033[0m\n"
}

invoke_intro() {
    echo "============================================================"
    echo ""
    echo "  OpenWrt/GL.iNet Tailscale Updater by Admon"
    echo "  Version: $SCRIPT_VERSION"
    echo ""
    echo "============================================================"
    echo ""
    echo "  WARNING: THIS SCRIPT MIGHT HARM YOUR ROUTER!"
    echo "  Use at your own risk. Only proceed if you know"
    echo "  what you're doing."
    echo ""
    echo "============================================================"
    echo ""
    echo "  Support this project:"
    echo "    - GitHub: github.com/sponsors/admonstrator"
    echo "    - Ko-fi: ko-fi.com/admon"
    echo "    - Buy Me a Coffee: buymeacoffee.com/admon"
    echo ""
    echo "============================================================"
    echo ""
}

collect_user_preferences() {
    log "INFO" "Collecting user preferences before starting the update process"
    echo ""

    # Ask about UPX compression (only if not using tiny version and no flags set)
    if [ "$NO_TINY" -eq 1 ]; then
        if [ "$NO_UPX" -eq 1 ]; then
            USER_WANTS_UPX="n"
            log "INFO" "--no-upx flag is used. Skipping UPX compression"
        elif [ "$FORCE" -eq 1 ]; then
            USER_WANTS_UPX="y"
            log "INFO" "--force flag is used. UPX compression enabled"
        else
            echo "┌────────────────────────────────────────────────────────────────────────────────┐"
            echo "| UPX Compression                                                                |"
            echo "| Compressing the binaries will save space but takes 2-3 minutes per binary.     |"
            echo "| Recommended if you have limited storage space.                                 |"
            echo "└────────────────────────────────────────────────────────────────────────────────┘"
            printf "> \033[36mDo you want to compress the binaries with UPX to save space?\033[0m (y/N) "
            read -r USER_WANTS_UPX
            USER_WANTS_UPX=$(echo "$USER_WANTS_UPX" | tr 'ABCDEFGHIJKLMNOPQRSTUVWXYZ' 'abcdefghijklmnopqrstuvwxyz')
            echo ""
        fi
    else
        # Tiny version doesn't need UPX compression
        USER_WANTS_UPX="n"
    fi

    # Ask about SSH (only for GL.iNet routers)
    if [ "$IS_GLINET" -eq 1 ] && [ -f "/usr/bin/gl_tailscale" ]; then
        if [ "$ENABLE_SSH" -eq 1 ]; then
            USER_WANTS_SSH="y"
            log "INFO" "--ssh flag is used. Tailscale SSH will be enabled"
        elif [ "$FORCE" -eq 1 ]; then
            USER_WANTS_SSH="n"
            log "INFO" "--force flag is used. Tailscale SSH will be skipped"
        else
            echo "┌────────────────────────────────────────────────────────────────────────────────┐"
            echo "| Tailscale SSH                                                                  |"
            echo "| This enables SSH access to your router through Tailscale.                      |"
            echo "| You can then SSH to your router using the Tailscale web interface.             |"
            echo "| See https://tailscale.com/kb/1193/tailscale-ssh/ for more information.         |"
            echo "| This setting can be changed later via UCI config.                              |"
            echo "└────────────────────────────────────────────────────────────────────────────────┘"
            printf "> \033[36mDo you want to enable Tailscale SSH?\033[0m (y/N) "
            read -r USER_WANTS_SSH
            USER_WANTS_SSH=$(echo "$USER_WANTS_SSH" | tr 'ABCDEFGHIJKLMNOPQRSTUVWXYZ' 'abcdefghijklmnopqrstuvwxyz')
            echo ""
        fi
    fi

    # Ask about persistence (only for GL.iNet routers)
    if [ "$IS_GLINET" -eq 1 ]; then
        if [ "$FORCE" -eq 1 ]; then
            USER_WANTS_PERSISTENCE="y"
            log "INFO" "--force flag is used. Installation will be made permanent"
        else
            echo "┌────────────────────────────────────────────────────────────────────────────────┐"
            echo "| Make Installation Permanent                                                    |"
            echo "| This will make your tailscale installation persistent over firmware upgrades.  |"
            echo "| Please note that this is not officially supported by GL.iNet.                  |"
            echo "| It could lead to issues, even if not likely. Just keep that in mind.           |"
            echo "| In worst case, you might need to remove the config from /etc/sysupgrade.conf   |"
            echo "└────────────────────────────────────────────────────────────────────────────────┘"
            printf "> \033[36mDo you want to make the installation permanent?\033[0m (y/N) "
            read -r USER_WANTS_PERSISTENCE
            USER_WANTS_PERSISTENCE=$(echo "$USER_WANTS_PERSISTENCE" | tr 'ABCDEFGHIJKLMNOPQRSTUVWXYZ' 'abcdefghijklmnopqrstuvwxyz')
            echo ""
        fi
    fi

    # Final confirmation unless --force is used
    if [ "$FORCE" -eq 0 ]; then
        printf "\033[93m┌──────────────────────────────────────────────────┐\033[0m\n"
        printf "\033[93m| Are you sure you want to continue? (y/N)         |\033[0m\n"
        printf "\033[93m└──────────────────────────────────────────────────┘\033[0m\n"
        read -r answer
        answer_lower=$(echo "$answer" | tr 'ABCDEFGHIJKLMNOPQRSTUVWXYZ' 'abcdefghijklmnopqrstuvwxyz')
        if [ "$answer_lower" != "${answer_lower#[y]}" ]; then
            log "INFO" "Starting update process..."
            echo ""
        else
            log "SUCCESS" "Ok, see you next time!"
            exit 0
        fi
    else
        log "WARNING" "--force flag is used. Continuing without final confirmation"
        echo ""
    fi
}

choose_release_label() {
    log "INFO" "Fetching available release labels..."
    available_labels=$(wget -qO- "https://api.github.com/repos/Admonstrator/glinet-tailscale-updater/releases" | grep -o '"tag_name":"[^"]*' | sed 's/"tag_name":"//g')
    
    if [ -z "$available_labels" ]; then
        log "ERROR" "Could not retrieve release labels. Please check your internet connection."
        exit 1
    fi

    log "INFO" "Available release labels:"
    
    # Display labels with numbered options
    i=1
    for label in $available_labels; do
        printf "\033[93m %d) %s\033[0m\n" "$i" "$label"
        i=$((i + 1))
    done

    printf "\033[93m Select a release by entering the corresponding number: \033[0m"
    read -r label_choice
    selected_label=$(echo "$available_labels" | sed -n "${label_choice}p")
    
    if [ -z "$selected_label" ]; then
        log "ERROR" "Invalid choice. Exiting..."
        exit 1
    else
        log "INFO" "You selected release label: $selected_label"
        TAILSCALE_TINY_URL="https://github.com/Admonstrator/glinet-tailscale-updater/releases/download/$selected_label"
        log "WARNING" "Downgrading is not officially supported by Tailscale!"
        log "WARNING" "It could lead to issues and unexpected behavior!"
        log "WARNING" "Do you want to continue? (y/N)"
        read -r answer
        answer_lower=$(echo "$answer" | tr 'ABCDEFGHIJKLMNOPQRSTUVWXYZ' 'abcdefghijklmnopqrstuvwxyz')
        if [ "$answer_lower" != "${answer_lower#[y]}" ]; then
            log "INFO" "Ok, continuing ..."
        else
            log "ERROR" "Ok, see you next time!"
            exit 0
        fi
    fi
}

invoke_update() {
    log "INFO" "Checking for script updates"
    local update_url="$UPDATE_URL"
    if [ "$TESTING" -eq 1 ]; then
        update_url="https://raw.githubusercontent.com/Admonstrator/glinet-tailscale-updater/testing/update-tailscale.sh"
        log "INFO" "Testing mode: Using testing branch for script updates"
    fi
    SCRIPT_VERSION_NEW=$(wget -qO- "$update_url" | grep -o 'SCRIPT_VERSION="[0-9]\{4\}\.[0-9]\{2\}\.[0-9]\{2\}\.[0-9]\{2\}"' | cut -d '"' -f 2 || echo "Failed to retrieve scriptversion")
    if [ -n "$SCRIPT_VERSION_NEW" ] && [ "$SCRIPT_VERSION_NEW" != "$SCRIPT_VERSION" ]; then
        log "WARNING" "A new version of the script is available: $SCRIPT_VERSION_NEW"
        log "INFO" "Updating the script ..."
        wget -q -O "/tmp/$SCRIPT_NAME" "$update_url"
        # Get current script path
        SCRIPT_PATH=$(readlink -f "$0")
        # Replace current script with updated script
        rm "$SCRIPT_PATH"
        mv /tmp/$SCRIPT_NAME "$SCRIPT_PATH"
        chmod +x "$SCRIPT_PATH"
        log "INFO" "The script has been updated. It will now restart ..."
        sleep 3
        exec "$SCRIPT_PATH" "$@"
    else
        log "SUCCESS" "The script is up to date"
    fi
}

invoke_outro() {
    log "SUCCESS" "Script finished successfully. The current tailscale version (software, daemon) is:"
    tailscale version
    tailscaled --version
    echo ""
    echo ""
    echo "If you like this script, please consider supporting the project:"
    echo "  - GitHub: github.com/sponsors/admonstrator"
    echo "  - Ko-fi: ko-fi.com/admon"
    echo "  - Buy Me a Coffee: buymeacoffee.com/admon"
    
    # Show a warning that SSH will disconnect if you are conected via Tailscale SSH
    # Continue to enable Tailscale SSH if requested
    if [ "$USER_WANTS_SSH" != "${USER_WANTS_SSH#[y]}" ]; then
        log "INFO" "Enabling Tailscale SSH support as requested"
        log "WARNING" "If you are connected to your router via Tailscale SSH, you will be disconnected now."
        tailscale set --ssh --accept-risk=lose-ssh
        log "SUCCESS" "Tailscale SSH support enabled."
    fi

    # Check if Tailscale is enabled in GL.iNet GUI
    if [ "$IS_GLINET" -eq 1 ]; then
        TAILSCALE_ENABLED=$(uci -q get tailscale.settings.enabled)
        if [ "$TAILSCALE_ENABLED" = "0" ]; then
            echo ""
            echo ""
            log "WARNING" "Tailscale is not enabled in GL.iNet GUI"
            log "WARNING" "Make sure to enable it after the update"
            log "INFO" "See https://glinet.admon.me/tse for instructions"
        fi
    fi
}

restore() {
    if [ ! -f "/rom/usr/sbin/tailscale" ] || [ ! -f "/rom/usr/sbin/tailscaled" ]; then
        log "ERROR" "Cannot restore to factory default!"
        log "ERROR" "tailscale binaries (tailscale, tailscaled) not found in /rom."
        log "ERROR" "This happens if you are not using GL.iNet firmware or running the script on a non-GL.iNet device."
        log "ERROR" "You might need to use --force --select-release to install a specific version."
        exit 1
    fi
    printf "\033[31mWARNING: This will restore the tailscale binary to factory default!\033[0m\n"
    printf "\033[31mDowngrading tailscale is not officially supported. It could lead to issues.\033[0m\n"
    printf "\033[93m┌──────────────────────────────────────────────────┐\033[0m\n"
    printf "\033[93m| Are you sure you want to continue? (y/N)         |\033[0m\n"
    printf "\033[93m└──────────────────────────────────────────────────┘\033[0m\n"
    if [ "$FORCE" -eq 1 ]; then
        log "WARNING" "--force flag is used. Continuing"
        answer_restore="y"
    else
        read -r answer_restore
    fi
    answer_restore_lower=$(echo "$answer_restore" | tr 'ABCDEFGHIJKLMNOPQRSTUVWXYZ' 'abcdefghijklmnopqrstuvwxyz')
    if [ "$answer_restore_lower" != "${answer_restore_lower#[y]}" ]; then
        stop_tailscale
        sleep 5
        if [ -f "/usr/sbin/tailscale" ]; then
            rm /usr/sbin/tailscale
        fi
        if [ -f "/usr/sbin/tailscaled" ]; then
            rm /usr/sbin/tailscaled
        fi
        log "INFO" "Restoring tailscale binary from rom"
        if [ -f "/rom/usr/sbin/tailscale" ]; then
            cp /rom/usr/sbin/tailscale /usr/sbin/tailscale
            log "SUCCESS" "tailscale binary restored"
        fi
        log "INFO" "Restoring tailscaled binary from rom"
        if [ -f "/rom/usr/sbin/tailscaled" ]; then
            cp /rom/usr/sbin/tailscaled /usr/sbin/tailscaled
            log "SUCCESS" "tailscaled binary restored"
        fi
        if [ -f "/rom/usr/bin/gl_tailscale" ]; then
            rm /usr/bin/gl_tailscale
            cp /rom/usr/bin/gl_tailscale /usr/bin/gl_tailscale
            log "SUCCESS" "gl_tailscale script restored"
        else
            log "WARNING" "gl_tailscale script not found in /rom"
        fi
        # Remove from /etc/sysupgrade.conf
        log "INFO" "Removing entries from /etc/sysupgrade.conf"
        sed -i '/\/usr\/sbin\/tailscale/d' /etc/sysupgrade.conf
        sed -i '/\/usr\/sbin\/tailscaled/d' /etc/sysupgrade.conf
        sed -i '/\/etc\/config\/tailscale/d' /etc/sysupgrade.conf
        sed -i '/\/root\/tailscale_config_backup\//d' /etc/sysupgrade.conf
        log "SUCCESS" "Tailscale restored to factory default."
        log "WARNING" "Restarting tailscale might or might not work"
        log "WARNING" "You might need to re-authenticate your device"
        start_tailscale
        invoke_outro
    else
        log "SUCCESS" "Ok, see you next time!"
        exit 1
    fi
}

# ==============================================================================
# Main Execution Flow
# ==============================================================================

parse_arguments() {
    for arg in "$@"; do
        case $arg in
        --help)
            invoke_help
            exit 0
            ;;
        --force)
            FORCE=1
            ;;
        --ignore-free-space)
            IGNORE_FREE_SPACE=1
            ;;
        --restore)
            RESTORE=1
            ;;
        --no-upx)
            NO_UPX=1
            ;;
        --no-download)
            NO_DOWNLOAD=1
            ;;
        --no-tiny)
            NO_TINY=1
            ;;
        --select-release)
            SELECT_RELEASE=1
            ;;
        --testing)
            TESTING=1
            ;;
        --log)
            SHOW_LOG=1
            ;;
        --ascii)
            ASCII_MODE=1
            ;;
        --force-upgrade)
            FORCE_UPGRADE=1
            ;;
        --ssh)
            ENABLE_SSH=1
            ;;
        --skip-config)
            SKIP_CONFIG=1
            ;;
        *)
            echo "Unknown argument: $arg"
            invoke_help
            exit 1
            ;;
        esac
    done
}

main() {
    parse_arguments "$@"

    # Check if --restore flag is used, if yes, restore tailscale
    if [ "$RESTORE" -eq 1 ]; then
        restore
        exit 0
    fi

    # Set URLs based on --testing flag
    if [ "$TESTING" -eq 1 ]; then
        log "INFO" "Testing mode enabled: Using prerelease versions"
        TAILSCALE_TINY_URL="https://github.com/Admonstrator/glinet-tailscale-updater/releases/download/prerelease/"
        UPDATE_URL="https://raw.githubusercontent.com/Admonstrator/glinet-tailscale-updater/testing/update-tailscale.sh"
    fi

    # Check if the script is up to date
    invoke_update "$@"
    
    # Start the script
    invoke_intro
    preflight_check

    # Check if user wants to select a specific release
    if [ "$SELECT_RELEASE" -eq 1 ]; then
        choose_release_label
    fi

    # Show warning if ignore-free-space is used
    if [ "$IGNORE_FREE_SPACE" -eq 1 ]; then
        printf "\033[31m┌────────────────────────────────────────────────────────────────────────┐\033[0m\n"
        printf "\033[31m│ WARNING: --ignore-free-space flag is used. This might potentially harm │\033[0m\n"
        printf "\033[31m│ your router. Use it at your own risk.                                  │\033[0m\n"
        printf "\033[31m│ You might need to reset your router to factory settings if something   │\033[0m\n"
        printf "\033[31m│ goes wrong.                                                            │\033[0m\n"
        printf "\033[31m└────────────────────────────────────────────────────────────────────────┘\033[0m\n"
        echo ""
    fi

    # Collect all user preferences before starting the update
    collect_user_preferences

    if [ "$NO_TINY" -eq 1 ]; then
        # Load the original tailscale
        get_latest_tailscale_version
        backup
        install_tailscale
        invoke_modify_script
        restart_tailscale
        upgrade_persistance
        invoke_outro
        exit 0
    else
        # Load the tiny tailscale
        get_latest_tailscale_version_tiny
        backup
        install_tiny_tailscale
        invoke_modify_script
        restart_tailscale
        upgrade_persistance
        invoke_outro
        exit 0
    fi
}

# Execute Main
main "$@"
