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
# Updated: 2024-03-16
# Date: 2024-01-24
# Version: 2024.03.17.01
#
# Usage: ./update-tailscale.sh [--ignore-free-space] [--force] [--restore]
# Warning: This script might potentially harm your router. Use it at your own risk.
#

# Functions
invoke_intro() {
    echo "┌────────────────────────────────────────────────────────────────────────┐"
    echo "│ GL.iNet router script by Admon 🦭 for the GL.iNet community            │"
    echo "| Version 2024.03.17.01                                                  │"
    echo "├────────────────────────────────────────────────────────────────────────┤"
    echo "│ WARNING: THIS SCRIPT MIGHT POTENTIALLY HARM YOUR ROUTER!               │"
    echo "│ It's only recommended to use this script if you know what you're doing.│"
    echo "├────────────────────────────────────────────────────────────────────────┤"
    echo "│ This script will update Tailscale on your router.                      │"
    echo "│                                                                        │"
    echo "│ Prerequisites:                                                         │"
    echo "│ 1. At least 50 MB of free space.                                       │"
    echo "│ 2. Firmware version 4 or higher.                                       │"
    echo "│ 3. Architecture arm64, armv7 or mips.                                  │"
    echo "└────────────────────────────────────────────────────────────────────────┘"
}

preflight_check() {
    AVAILABLE_SPACE=$(df -k / | tail -n 1 | awk '{print $4/1024}')
    AVAILABLE_SPACE=$(printf "%.0f" "$AVAILABLE_SPACE")
    ARCH=$(uname -m)
    FIRMWARE_VERSION=$(cut -c1 </etc/glversion)
    PREFLIGHT=0

    echo "Checking if prerequisites are met ..."
    if [ "${FIRMWARE_VERSION}" -lt 4 ]; then
        echo -e "\033[31mx\033[0m ERROR: This script only works on firmware version 4 or higher."
        PREFLIGHT=1
    else
        echo -e "\033[32m✓\033[0m Firmware version: $FIRMWARE_VERSION"
    fi
    if [ "$ARCH" = "aarch64" ]; then
        echo -e "\033[32m✓\033[0m Architecture: arm64"
    elif [ "$ARCH" = "armv7l" ]; then
        echo -e "\033[32m✓\033[0m Architecture: armv7"
    elif [ "$ARCH" = "mips" ]; then
        echo -e "\033[32m✓\033[0m Architecture: mips"
    else
        echo -e "\033[31mx\033[0m ERROR: This script only works on arm64, armv7 and mips."
        PREFLIGHT=1
    fi
    if [ "$AVAILABLE_SPACE" -lt 50 ]; then
        echo -e "\033[31mx\033[0m ERROR: Not enough space available. Please free up some space and try again."
        echo "The script needs at least 50 MB of free space. Available space: $AVAILABLE_SPACE MB"
        echo "If you want to continue, you can use --ignore-free-space to ignore this check."
        if [ "$IGNORE_FREE_SPACE" -eq 1 ]; then
            echo -e "\033[31mWARNING: --ignore-free-space flag is used. Continuing without enough space ...\033[0m"
            echo -e "\033[31mCurrent available space: $AVAILABLE_SPACE MB\033[0m"
        else
            PREFLIGHT=1
        fi
    else
        echo -e "\033[32m✓\033[0m Available space: $AVAILABLE_SPACE MB"
    fi
    # Check if xz is present
    if ! command -v xz >/dev/null; then
        echo -e "\033[33m!\033[0m xz is not installed. We can install it for you later."
    else
        echo -e "\033[32m✓\033[0m xz is installed."
    fi
    if [ "$PREFLIGHT" -eq "1" ]; then
        echo -e "\033[31mERROR: Prerequisites are not met. Exiting ...\033[0m"
        exit 1
    else
        echo -e "\033[32m✓\033[0m Prerequisites are met."
    fi
}

backup() {
    echo "┌────────────────────────────────────────────────────────────────────────┐"
    echo "│ C R E A T I N G   B A C K U P   O F   T A I L S C A L E                │"
    echo "└────────────────────────────────────────────────────────────────────────┘"
    echo "Creating backup of tailscale config ..."
    TIMESTAMP=$(date +"%Y-%m-%d_%H-%M-%S")
    if [ ! -d "/root/tailscale_config_backup" ]; then
        mkdir "/root/tailscale_config_backup"
    fi
    tar czf "/root/tailscale_config_backup/$TIMESTAMP.tar.gz" -C "/" "etc/config/tailscale"
    echo "Backup created: /root/tailscale_config_backup/$TIMESTAMP.tar.gz"
    echo "The binaries will not be backed up, you can restore them by using the --restore flag."
}

get_latest_tailscale_version() {
    echo "┌────────────────────────────────────────────────────────────────────────┐"
    echo "│ G E T T I N G   N E W E S T   T A I L S C A L E   V E R S I O N        │"
    echo "└────────────────────────────────────────────────────────────────────────┘"
    echo "Detecting latest tailscale version ..."
    if [ "$ARCH" = "aarch64" ]; then
        TAILSCALE_VERSION_NEW=$(curl -s https://pkgs.tailscale.com/stable/ | grep -o 'tailscale_[0-9]*\.[0-9]*\.[0-9]*_arm64\.tgz' | head -n 1)
    elif [ "$ARCH" = "armv7l" ]; then
        TAILSCALE_VERSION_NEW=$(curl -s https://pkgs.tailscale.com/stable/ | grep -o 'tailscale_[0-9]*\.[0-9]*\.[0-9]*_arm\.tgz' | head -n 1)
    elif [ "$ARCH" = "mips" ]; then
        TAILSCALE_VERSION_NEW=$(curl -s https://pkgs.tailscale.com/stable/ | grep -o 'tailscale_[0-9]*\.[0-9]*\.[0-9]*_mips\.tgz' | head -n 1)
    fi
    if [ -z "$TAILSCALE_VERSION_NEW" ]; then
        echo -e "\033[31mx\033[0m ERROR: Could not get latest tailscale version. Please check your internet connection."
        exit 1
    fi
    echo "The latest tailscale version is: $TAILSCALE_VERSION_NEW"
    echo "Downloading latest tailscale version ..."
    wget -qO /tmp/tailscale.tar.gz "https://pkgs.tailscale.com/stable/$TAILSCALE_VERSION_NEW"
    if [ -d "/tmp/tailscale" ]; then
        rm -rf /tmp/tailscale
    fi
    mkdir /tmp/tailscale

    # Ask if the user wants to compress the binaries with UPX to save space
    echo "┌────────────────────────────────────────────────────────────────────────┐"
    echo "│ C O M P R E S S   B I N A R I E S   W I T H   U P X                    │"
    echo "└────────────────────────────────────────────────────────────────────────┘"
    if [ "$NO_UPX" -eq 1 ]; then
        echo "--no-upx flag is used. Skipping compression ..."
        answer_compress_binaries="n"
    elif [ "$FORCE" -eq 1 ]; then
        echo "--force flag is used. Continuing with upx compression ..."
        answer_compress_binaries="y"
    else
        echo -e -n "> \033[36mDo you want to compress the binaries with UPX to save space?\033[0m (y/N) " && read -r answer_compress_binaries
    fi
    # Extract tailscale

    if [ "$answer_compress_binaries" != "${answer_compress_binaries#[Yy]}" ]; then
        compress_binaries
        if [ "$UPX_ERROR" -eq 1 ]; then
            echo -e "\033[31mERROR: Could not compress tailscale with UPX. Continuing without compression ...\033[0m"
            tar xzf /tmp/tailscale.tar.gz -C /tmp/tailscale
        fi
    else
        echo "Extracting tailscale without compression ..."
        tar xzf /tmp/tailscale.tar.gz -C /tmp/tailscale
    fi

    # Removing archive
    rm /tmp/tailscale.tar.gz
}

compress_binaries() {
    echo "Ensuring xz is present ..."
    opkg update --verbosity=0
    opkg install --verbosity=0 xz

    echo "Getting UPX ..."
    upx_version="$(
        curl -s "https://api.github.com/repos/upx/upx/releases/latest" \
            | grep 'tag_name' \
            | cut -d : -f 2 \
            | tr -d '"v, '
    )"

    if [ "$ARCH" = "aarch64" ]; then
        UPX_ARCH="arm64"
    elif [ "$ARCH" = "armv7l" ]; then
        UPX_ARCH="arm"
    elif [ "$ARCH" = "mips" ]; then
        UPX_ARCH="$ARCH"
    fi

    wget -qO "/tmp/upx.tar.xz" \
        "https://github.com/upx/upx/releases/download/v${upx_version}/upx-${upx_version}-${UPX_ARCH}_linux.tar.xz"

    # If download fails, skip compression
    if [ ! -f "/tmp/upx.tar.xz" ]; then
        echo -e "\033[31mERROR: Could not download UPX. Skipping compression ...\033[0m"
                echo "Extracting tailscale without compression ..."
        UPX_ERROR=1
    else
        # Extract only the upx binary
        unxz --decompress --stdout "/tmp/upx.tar.xz" \
            | tar x -C "/tmp/" "upx-${upx_version}-${UPX_ARCH}_linux/upx"
        mv "/tmp/upx-${upx_version}-${UPX_ARCH}_linux/upx" "/tmp/upx"
        rmdir "/tmp/upx-${upx_version}-${UPX_ARCH}_linux"
        rm "/tmp/upx.tar.xz"
        # Check if the upx binary is present
        if [ ! -f "/tmp/upx" ]; then
            echo -e "\033[31mERROR: Could not find UPX binary. Skipping compression ...\033[0m"
            UPX_ERROR=1
        fi

        tar xzf "/tmp/tailscale.tar.gz" "${TAILSCALE_VERSION_NEW%.tgz}/tailscale" \
            -C "/tmp/tailscale"
        echo -e "\033[33mCompressing tailscale with UPX ...\033[0m"
        echo -e "\033[33mThis might take 2-3 minutes, depending on your router.\033[0m"
        /usr/bin/time -f %e /tmp/upx --lzma "/tmp/tailscale/"*"/tailscale"

        tar xzf "/tmp/tailscale.tar.gz" "${TAILSCALE_VERSION_NEW%.tgz}/tailscaled" \
            -C "/tmp/tailscale"
        # Takes 107.92s on GL-AXT1800
        echo -e "\033[33mCompressing tailscaled with UPX ...\033[0m"
        echo -e "\033[33mThis might take 2-3 minutes, depending on your router.\033[0m"
        /usr/bin/time -f %e /tmp/upx --lzma "/tmp/tailscale/"*"/tailscaled"
        # Clean up
        if [ -f "/tmp/upx" ]; then
            rm "/tmp/upx"
        fi
    fi
}

install_tailscale() {
    echo "┌────────────────────────────────────────────────────────────────────────┐"
    echo "│ I N S T A L L I N G   T A I L S C A L E                                │"
    echo "└────────────────────────────────────────────────────────────────────────┘"
    # Stop tailscale
    echo "Stopping tailscale ..."
    /etc/init.d/tailscale stop 2>/dev/null
    sleep 5
    # Moving tailscale to /usr/sbin
    echo "Moving tailscale to /usr/sbin ..."
    mv /tmp/tailscale/*/tailscale /usr/sbin/tailscale
    mv /tmp/tailscale/*/tailscaled /usr/sbin/tailscaled
    # Remove temporary files
    echo "Removing temporary files ..."
    rm -rf /tmp/tailscale
    # Restart tailscale
    echo "Restarting tailscale ..."
    /etc/init.d/tailscale restart 2>/dev/null
}

upgrade_persistance() {
    echo "┌────────────────────────────────────────────────────────────────────────┐"
    echo "│ U P G R A D E   P E R S I S T A N C E                                  │"
    echo "└────────────────────────────────────────────────────────────────────────┘"
    echo "The update was successful. Do you want to make the installation permanent?"
    echo "This will make your tailscale installation persistent over firmware upgrades."
    echo "Please note that this is not officially supported by GL.iNet."
    echo "It could lead to issues, even if not likely. Just keep that in mind."
    echo "In worst case, you might need to remove the config from /etc/sysupgrade.conf"
    echo -e "> \033[36mDo you want to make the installation permanent?\033[0m (y/N)"
    if [ "$FORCE" -eq 1 ]; then
        echo "--force flag is used. Continuing ..."
        answer_create_persistance="y"
    else
        read -r answer_create_persistance
    fi
    if [ "$answer_create_persistance" != "${answer_create_persistance#[Yy]}" ]; then
        echo "Making installation permanent ..."
        echo "Modifying /etc/sysupgrade.conf ..."
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
        if ! grep -q "/etc/config/tailscale" /etc/sysupgrade.conf; then
            echo "/etc/config/tailscale" >>/etc/sysupgrade.conf
        fi
    fi
}

restore() {
    echo -e "\033[31m┌────────────────────────────────────────────────────────────────────────┐\033[0m"
    echo -e "\033[31m│R E S T O R I N G   T A I L S C A L E                                   │\033[0m"
    echo -e "\033[31m└────────────────────────────────────────────────────────────────────────┘\033[0m"
    echo -e "\033[31mWARNING: This will restore the tailscale to factory default!\033[0m"
    echo -e "\033[31mDowngrading tailscale is not officially supported. It could lead to issues.\033[0m"
    echo -e "> \033[36mDo you want to restore tailscale?\033[0m (y/N)"
    if [ "$FORCE" -eq 1 ]; then
        echo "--force flag is used. Continuing ..."
        answer_restore="y"
    else
        read -r answer_restore
    fi
    if [ "$answer_restore" != "${answer_restore#[Yy]}" ]; then
        echo "Restoring tailscale ... Please wait ..."
        /etc/init.d/tailscale stop 2>/dev/null
        sleep 5
        if [ -f "/usr/sbin/tailscale" ]; then
            rm /usr/sbin/tailscale
        fi
        if [ -f "/usr/sbin/tailscaled" ]; then
            rm /usr/sbin/tailscaled
        fi
        echo "Restoring tailscale binary from rom ..."
        if [ -f "/rom/usr/sbin/tailscale" ]; then
            cp /rom/usr/sbin/tailscale /usr/sbin/tailscale
        else
            echo -e "\033[31mERROR: tailscale binary not found in /rom. Exiting ...\033[0m"
        fi
        echo "Restoring tailscaled binary from rom ..."
        if [ -f "/rom/usr/sbin/tailscaled" ]; then
            cp /rom/usr/sbin/tailscaled /usr/sbin/tailscaled
        else
            echo -e "\033[31mERROR: tailscaled binary not found in /rom. Exiting ...\033[0m"
        fi
        echo "Restarting tailscale ... Might or might not work ..."
        /etc/init.d/tailscale start 2>/dev/null
        # Remove from /etc/sysupgrade.conf
        echo "Removing entries from /etc/sysupgrade.conf ..."
        sed -i '/\/usr\/sbin\/tailscale/d' /etc/sysupgrade.conf
        sed -i '/\/usr\/sbin\/tailscaled/d' /etc/sysupgrade.conf
        sed -i '/\/etc\/config\/tailscale/d' /etc/sysupgrade.conf
        sed -i '/\/root\/tailscale_config_backup\//d' /etc/sysupgrade.conf
        echo "Tailscale restored to factory default."
    else
        echo "Ok, see you next time!"
        exit 1
    fi
}

invoke_outro() {
    echo -e "\033[32m┌────────────────────────────────────────────────────────────────────────┐\033[0m"
    echo -e "\033[32m│ S C R I P T   F I N I S H E D   S U C C E S S F U L L Y                │\033[0m"
    echo -e "\033[32m└────────────────────────────────────────────────────────────────────────┘\033[0m"
    echo "Script finished successfully. The new tailscale version (software, daemon) is:"
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
    echo -e "  \033[93m--help\033[0m               \033[97mShow this help\033[0m"
}

# Variables
IGNORE_FREE_SPACE=0
FORCE=0
RESTORE=0
UPX_ERROR=0
NO_UPX=0
# Read arguments
for arg in "$@"; do
    if [ "$arg" = "--help" ]; then
        invoke_help
        exit 0
    fi
    if [ "$arg" = "--force" ]; then
        FORCE=1
    fi
    if [ "$arg" = "--ignore-free-space" ]; then
        IGNORE_FREE_SPACE=1
    fi
    if [ "$arg" = "--restore" ]; then
        RESTORE=1
    fi
    if [ "$arg" = "--no-upx" ]; then
        NO_UPX=1
    fi
    # If unknown argument is passed, show help
    if [ "$arg" != "--force" ] && [ "$arg" != "--ignore-free-space" ] && [ "$arg" != "--restore" ] && [ "$arg" != "--no-upx" ] && [ "$arg" != "--help" ]; then
        echo "Unknown argument: $arg"
        invoke_help
        exit 1
    fi
done

# Main
# Check if --restore flag is used, if yes, restore tailscale
if [ "$RESTORE" -eq 1 ]; then
    restore
    exit 0
fi

invoke_intro
preflight_check
echo -e "> \033[36mDo you want to continue?\033[0m (y/N)"
if [ "$FORCE" -eq 1 ]; then
    echo "--force flag is used. Continuing ..."
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
        echo -e "> \033[36mDo you want to continue?\033[0m (y/N)"
        if [ "$FORCE" -eq 1 ]; then
            echo "--force flag is used. Continuing ..."
            answer="y"
        else
            read -r answer
        fi
        if [ "$answer" != "${answer#[Yy]}" ]; then
            echo "Ok, continuing ..."
        else
            echo "Ok, see you next time!"
            exit 1
        fi
    fi
    get_latest_tailscale_version
    backup
    install_tailscale
    upgrade_persistance
    invoke_outro
    exit 0
else
    echo "Ok, see you next time!"
    exit 1
fi
