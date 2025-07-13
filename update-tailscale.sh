#!/bin/sh
# shellcheck shell=dash
# NOTE: 'echo $SHELL' reports '/bin/ash' on the routers, see:
# - https://en.wikipedia.org/wiki/Almquist_shell#Embedded_Linux
# - https://github.com/koalaman/shellcheck/issues/1841
#
#
# Description: This script updates tailscale on GL.iNet routers
# Thread: https://forum.gl-inet.com/t/how-to-update-tailscale-on-arm64/37582
# Author: Admon
# Contributor: lwbt
# Date: 2024-01-24
SCRIPT_VERSION="2025.07.13.01"
SCRIPT_NAME="update-tailscale.sh"
UPDATE_URL="https://raw.githubusercontent.com/Admonstrator/glinet-tailscale-updater/main/update-tailscale.sh"
TAILSCALE_TINY_URL="https://github.com/Admonstrator/glinet-tailscale-updater/releases/latest/download/"
#
# Usage: ./update-tailscale.sh [--ignore-free-space] [--force] [--restore] [--no-upx] [--no-download] [--no-tiny] [--help]
# Warning: This script might potentially harm your router. Use it at your own risk.
#
# Variables
IGNORE_FREE_SPACE=0
FORCE=0
RESTORE=0
UPX_ERROR=0
NO_UPX=0
NO_DOWNLOAD=0
NO_TINY=0
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
INFO='\033[0m' # No Color

# Functions
invoke_intro() {
    echo "┌────────────────────────────────────────────────────────────────────────┐"
    echo "│ OpenWrt/GL.iNet Tailscale updater by Admon 🦭                          │"
    echo "| Version: $SCRIPT_VERSION                                                 |"
    echo "├────────────────────────────────────────────────────────────────────────┤"
    echo "│ WARNING: THIS SCRIPT MIGHT POTENTIALLY HARM YOUR ROUTER!               │"
    echo "│ It's only recommended to use this script if you know what you're doing.│"
    echo "├────────────────────────────────────────────────────────────────────────┤"
    echo "│ This script will update Tailscale on your router.                      │"
    echo "│                                                                        │"
    echo "│ Prerequisites:                                                         │"
    echo "│ 1. At least 15 MB of free space.                                       │"
    echo "│ 2. GL.iNet: Firmware version 4+ | OpenWrt: Any version                 │"
    echo "│ 3. Architecture: arm64, armv7, x86_64, mips or mipsle                  │"
    echo "└────────────────────────────────────────────────────────────────────────┘"
}

preflight_check() {
    AVAILABLE_SPACE=$(df -k / | tail -n 1 | awk '{print $4/1024}')
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
    # Check for specific models that use mipsle architecture
    if [ "$IS_GLINET" -eq 1 ]; then
        MODEL=$(grep 'machine' /proc/cpuinfo | awk -F ': ' '{print $2}')
        case "$MODEL" in
            "GL.iNet GL-MT1300" | "GL-MT300N-V2" | "GL-SFT1200")
                TINY_ARCH="mipsle"
                log "SUCCESS" "Architecture: mipsle"
                ;;
            *)
                TINY_ARCH="mips"
                log "SUCCESS" "Architecture: mips"
                ;;
        esac
    else
        TINY_ARCH="mips"
        log "SUCCESS" "Architecture: mips"
    fi
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
    # Check if curl is present
    if ! command -v curl >/dev/null; then
        log "ERROR" "curl is not installed. Exiting"
        PREFLIGHT=1
    else
        log "SUCCESS" "curl is installed."
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

get_latest_tailscale_version_tiny() {
    # Will attempt to download the latest version of tailscale from the updater repository
    # This is the default behavior
    log "INFO" "Detecting latest tiny tailscale version"
    TAILSCALE_VERSION_NEW=$(curl -L -s $TAILSCALE_TINY_URL/version.txt | grep -o '[0-9]*\.[0-9]*\.[0-9]')
    if [ -z "$TAILSCALE_VERSION_NEW" ]; then
        log "ERROR" "Could not get latest tailscale version. Please check your internet connection."
        exit 1
    fi
    TAILSCALE_VERSION_OLD="$(tailscale --version | head -1)"
    if [ "$TAILSCALE_VERSION_NEW" == "$TAILSCALE_VERSION_OLD" ]; then
        log "SUCCESS" "You already have the latest version."
        log "INFO" "If you encounter issues while using the tiny version, please use the normal version."
        log "INFO" "You can do this by using the --no-tiny flag."
        log "INFO" "Make sure to have enough space available. The normal version needs at least 50 MB."
        log "INFO" "This issue is because not every release will be published in the official repository."
        exit 0
    fi
    log "INFO" "The latest tailscale version is: $TAILSCALE_VERSION_NEW"
    log "INFO" "Downloading latest tailscale version"
    curl -L -s --output /tmp/tailscaled-linux-$TINY_ARCH "$TAILSCALE_TINY_URL/tailscaled-linux-$TINY_ARCH"
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
            TAILSCALE_VERSION_NEW=$(curl -s https://pkgs.tailscale.com/stable/ | grep -o 'tailscale_[0-9]*\.[0-9]*\.[0-9]*_arm64\.tgz' | head -n 1)
        elif [ "$ARCH" = "armv7l" ]; then
            TAILSCALE_VERSION_NEW=$(curl -s https://pkgs.tailscale.com/stable/ | grep -o 'tailscale_[0-9]*\.[0-9]*\.[0-9]*_arm\.tgz' | head -n 1)
        elif [ "$ARCH" = "x86_64" ]; then
            TAILSCALE_VERSION_NEW=$(curl -s https://pkgs.tailscale.com/stable/ | grep -o 'tailscale_[0-9]*\.[0-9]*\.[0-9]*_amd64\.tgz' | head -n 1)
        elif [ "$ARCH" = "mips" ]; then
            TAILSCALE_VERSION_NEW=$(curl -s https://pkgs.tailscale.com/stable/ | grep -o 'tailscale_[0-9]*\.[0-9]*\.[0-9]*_mips\.tgz' | head -n 1)
        fi
        if [ -z "$TAILSCALE_VERSION_NEW" ]; then
            log "ERROR" "Could not get latest tailscale version. Please check your internet connection."
            exit 1
        fi
        TAILSCALE_VERSION_OLD="$(tailscale --version | head -1)"
        if [ "$TAILSCALE_VERSION_NEW" == "$TAILSCALE_VERSION_OLD" ]; then
            log "SUCCESS" "You already have the latest version."
            exit 0
        fi
        log "INFO" "The latest tailscale version is: $TAILSCALE_VERSION_NEW"
        log "INFO" "Downloading latest tailscale version"
        curl -L -s --output /tmp/tailscale.tar.gz "https://pkgs.tailscale.com/stable/$TAILSCALE_VERSION_NEW"
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
    # Ask if the user wants to compress the binaries with UPX to save space
    if [ "$NO_UPX" -eq 1 ]; then
        log "WARNING" "--no-upx flag is used. Skipping compression"
        answer_compress_binaries="n"
    elif [ "$FORCE" -eq 1 ]; then
        log "WARNING" "--force flag is used. Continuing with upx compression"
        answer_compress_binaries="y"
    else
        echo -e -n "> \033[36mDo you want to compress the binaries with UPX to save space?\033[0m (y/N) " && read -r answer_compress_binaries
    fi
    # Extract tailscale

    if [ "$answer_compress_binaries" != "${answer_compress_binaries#[Yy]}" ]; then
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
        curl -s "https://api.github.com/repos/upx/upx/releases/latest" |
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

     curl -L -s --output "/tmp/upx.tar.xz" \
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
    log "INFO" "Stopping tailscale"
    /etc/init.d/tailscale stop 2>/dev/null
    sleep 5
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
    # Restart tailscale
}

install_tiny_tailscale() {
    # Stop tailscale
    log "INFO" "Stopping tailscale"
    /etc/init.d/tailscale stop 2>/dev/null
    sleep 5
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
}

upgrade_persistance() {
    if [ "$IS_GLINET" -eq 1 ]; then
        echo "┌────────────────────────────────────────────────────────────────────────────────┐"
        echo "| The update was successful. Do you want to make the installation permanent?     |"
        echo "| This will make your tailscale installation persistent over firmware upgrades.  |"
        echo "| Please note that this is not officially supported by GL.iNet.                  |"
        echo "| It could lead to issues, even if not likely. Just keep that in mind.           |"
        echo "| In worst case, you might need to remove the config from /etc/sysupgrade.conf   |"
        echo "└────────────────────────────────────────────────────────────────────────────────┘"
        echo -e "> \033[36mDo you want to make the installation permanent?\033[0m (y/N)"
        if [ "$FORCE" -eq 1 ]; then
            log "WARNING" "--force flag is used. Continuing"
            answer_create_persistance="y"
        else
            read -r answer_create_persistance
        fi
        if [ "$answer_create_persistance" != "${answer_create_persistance#[Yy]}" ]; then
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

restore() {
    echo -e "\033[31mWARNING: This will restore the tailscale to factory default!\033[0m"
    echo -e "\033[31mDowngrading tailscale is not officially supported. It could lead to issues.\033[0m"
    echo -e "\033[93m┌──────────────────────────────────────────────────┐\033[0m"
    echo -e "\033[93m| Are you sure you want to continue? (y/N)         |\033[0m"
    echo -e "\033[93m└──────────────────────────────────────────────────┘\033[0m"
    if [ "$FORCE" -eq 1 ]; then
        log "WARNING" "--force flag is used. Continuing"
        answer_restore="y"
    else
        read -r answer_restore
    fi
    if [ "$answer_restore" != "${answer_restore#[Yy]}" ]; then
        log "INFO" "Restoring tailscale"
        /etc/init.d/tailscale stop 2>/dev/null
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
        else
            log "ERROR" "tailscale binary not found in /rom. Exiting"
        fi
        log "INFO" "Restoring tailscaled binary from rom"
        if [ -f "/rom/usr/sbin/tailscaled" ]; then
            cp /rom/usr/sbin/tailscaled /usr/sbin/tailscaled
        else
            log "ERROR" "tailscaled binary not found in /rom. Exiting"
        fi
        if [ "$IS_GLINET" -eq 1 ] && [ -f "/rom/usr/bin/gl_tailscale" ]; then
            cp /rom/usr/bin/gl_tailscale /usr/bin/gl_tailscale
            log "SUCCESS" "gl_tailscale script restored"
        elif [ "$IS_GLINET" -eq 1 ]; then
            log "WARNING" "gl_tailscale script not found in /rom"
        fi
        log "INFO" "Restarting tailscale Might or might not work"
        /etc/init.d/tailscale start 2>/dev/null
        # Remove from /etc/sysupgrade.conf
        log "INFO" "Removing entries from /etc/sysupgrade.conf"
        sed -i '/\/usr\/sbin\/tailscale/d' /etc/sysupgrade.conf
        sed -i '/\/usr\/sbin\/tailscaled/d' /etc/sysupgrade.conf
        sed -i '/\/etc\/config\/tailscale/d' /etc/sysupgrade.conf
        sed -i '/\/root\/tailscale_config_backup\//d' /etc/sysupgrade.conf
        log "SUCCESS" "Tailscale restored to factory default."
    else
        log "SUCCESS" "Ok, see you next time!"
        exit 1
    fi
}

invoke_outro() {
    log "SUCCESS" "Script finished successfully. The new tailscale version (software, daemon) is:"
    tailscale version
    tailscaled --version
}

invoke_help() {
    echo -e "\033[1mUsage:\033[0m \033[92m./update-tailscale.sh\033[0m [\033[93m--ignore-free-space\033[0m] [\033[93m--force\033[0m] [\033[93m--restore\033[0m] [\033[93m--no-upx\033[0m] [\033[93m--help\033[0m]"
    echo -e "\033[1mOptions:\033[0m"
    echo -e "  \033[93m--ignore-free-space\033[0m  \033[97mIgnore free space check\033[0m"
    echo -e "  \033[93m--force\033[0m              \033[97mDo not ask for confirmation\033[0m"
    echo -e "  \033[93m--restore\033[0m            \033[97mRestore tailscale to factory default\033[0m"
    echo -e "  \033[93m--no-upx\033[0m             \033[97mDo not compress tailscale with UPX\033[0m"
    echo -e "  \033[93m--no-download\033[0m        \033[97mDo not download tailscale\033[0m"
    echo -e "  \033[93m--no-tiny\033[0m            \033[97mDo not use the tiny version of tailscale\033[0m"
    echo -e "  \033[93m--help\033[0m               \033[97mShow this help\033[0m"
}

invoke_update() {
    log "INFO" "Checking for script updates"
    SCRIPT_VERSION_NEW=$(curl -s "$UPDATE_URL" | grep -o 'SCRIPT_VERSION="[0-9]\{4\}\.[0-9]\{2\}\.[0-9]\{2\}\.[0-9]\{2\}"' | cut -d '"' -f 2 || echo "Failed to retrieve scriptversion")
    if [ -n "$SCRIPT_VERSION_NEW" ] && [ "$SCRIPT_VERSION_NEW" != "$SCRIPT_VERSION" ]; then
        log "WARNING" "A new version of the script is available: $SCRIPT_VERSION_NEW"
        log "INFO" "Updating the script ..."
        curl -L -s --output /tmp/$SCRIPT_NAME "$UPDATE_URL"
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

invoke_modify_script() {
    if [ "$IS_GLINET" -eq 1 ] && [ -f "/usr/bin/gl_tailscale" ]; then
        log "INFO" "Modifying gl_tailscale script to work with the new tailscale version"
        # Search for param="--advertise-routes=$routes" and add --stateful-filtering=false
        sed -i 's|param="--advertise-routes=$routes"|param="--advertise-routes=$routes --stateful-filtering=false"|' /usr/bin/gl_tailscale
        log "SUCCESS" "gl_tailscale script modified successfully"
    else
        log "INFO" "Not a GL.iNet router or gl_tailscale script not found, skipping GL-specific modifications"
    fi
}

restart_tailscale() {
    log "INFO" "Restarting tailscale"
    /etc/init.d/tailscale restart 2>/dev/null
}

log() {
    local level=$1
    local message=$2
    local timestamp=$(date +"%Y-%m-%d %H:%M:%S")
    local color=$INFO # Default to no color

    # Assign color based on level
    case "$level" in
    ERROR)
        level="x"
        color=$RED
        ;;
    WARNING)
        level="!"
        color=$YELLOW
        ;;
    SUCCESS)
        level="✓"
        color=$GREEN
        ;;
    INFO)
        level="→"
        ;;
    esac

    echo -e "${color}[$timestamp] [$level] $message${INFO}"
}

# Read arguments
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
    *)
        echo "Unknown argument: $arg"
        invoke_help
        exit 1
        ;;
    esac
done

# Main
# Check if --restore flag is used, if yes, restore tailscale
if [ "$RESTORE" -eq 1 ]; then
    restore
    exit 0
fi

# Check if the script is up to date
invoke_update "$@"
# Start the script
invoke_intro
preflight_check
echo -e "\033[93m┌──────────────────────────────────────────────────┐\033[0m"
echo -e "\033[93m| Are you sure you want to continue? (y/N)         |\033[0m"
echo -e "\033[93m└──────────────────────────────────────────────────┘\033[0m"
if [ "$FORCE" -eq 1 ]; then
    log "WARNING" "--force flag is used. Continuing"
    answer="y"
else
    read -r answer
fi
if [ "$answer" != "${answer#[Yy]}" ]; then
    if [ "$IGNORE_FREE_SPACE" -eq 1 ]; then
        echo -e "\033[31m┌────────────────────────────────────────────────────────────────────────┐\033[0m"
        echo -e "\033[31m│ WARNING: --ignore-free-space flag is used. This might potentially harm │\033[0m"
        echo -e "\033[31m│ your router. Use it at your own risk.                                  │\033[0m"
        echo -e "\033[31m│ You might need to reset your router to factory settings if something   │\033[0m"
        echo -e "\033[31m│ goes wrong.                                                            │\033[0m"
        echo -e "\033[31m└────────────────────────────────────────────────────────────────────────┘\033[0m"
        echo -e "\033[93m┌──────────────────────────────────────────────────┐\033[0m"
        echo -e "\033[93m| Are you sure you want to continue? (y/N)         |\033[0m"
        echo -e "\033[93m└──────────────────────────────────────────────────┘\033[0m"
        if [ "$FORCE" -eq 1 ]; then
            log "WARNING" "--force flag is used. Continuing"
            answer="y"
        else
            read -r answer
        fi
        if [ "$answer" != "${answer#[Yy]}" ]; then
            log "INFO" "Ok, continuing"
        else
            log "SUCCESS" "Ok, see you next time!"
            exit 1
        fi
    fi

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
else
    log "SUCCESS" "Ok, see you next time!"
    exit 1
fi
