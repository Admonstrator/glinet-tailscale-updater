#!/bin/sh
#
#
# Description: This script updates tailscale on GL.iNet routers
# Thread: https://forum.gl-inet.com/t/how-to-update-tailscale-on-arm64/37582
# Author: Admon
# Updated: 2024-03-12
# Date: 2024-01-24
# Version: 1.0 BETA
#
# Usage: ./update-tailscale.sh [--ignore-free-space] [--force]
# Warning: This script might potentially harm your router. Use it at your own risk.
#

# Functions
invoke_intro() {
    echo "┌────────────────────────────────────────────────────────────────────────┐"
    echo "│ GL.iNet router script by Admon 🦭 for the GL.iNet community            │"
    echo "├────────────────────────────────────────────────────────────────────────┤"
    echo "│ WARNING: THIS SCRIPT MIGHT POTENTIALLY HARM YOUR ROUTER!               │"
    echo "│ It's only recommended to use this script if you know what you're doing.│"
    echo "├────────────────────────────────────────────────────────────────────────┤"
    echo "│ This script will update Tailscale on your router.                      │"
    echo "│                                                                        │"
    echo "│ Prerequisites:                                                         │"
    echo "│ 1. At least 130 MB of free space.                                      │"
    echo "│ 2. Firmware version 4 or higher.                                       │"
    echo "│ 3. Architecture arm64, armv7 or mips.                                  │"
    echo "└────────────────────────────────────────────────────────────────────────┘"
}

preflight_check(){
    echo "┌────────────────────────────────────────────────────────────────────────┐"
    echo "│ P R E F L I G H T   C H E C K                                          │"
    echo "└────────────────────────────────────────────────────────────────────────┘"
    AVAILABLE_SPACE=$(df -k / | tail -n 1 | awk '{print $4}')
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
        echo -e "\033[31mx\033[0m ERROR: This script only works on arm64 and armv7."
        PREFLIGHT=1
    fi
    if [ "$AVAILABLE_SPACE" -lt 130000 ]; then
        echo -e "\033[31mx\033[0m ERROR: Not enough space available. Please free up some space and try again."
        echo "The script needs at least 130 MB of free space. Available space: $AVAILABLE_SPACE KB"
        echo "If you want to continue, you can use --ignore-free-space to ignore this check."
        PREFLIGHT=1
    else
        echo -e "\033[32m✓\033[0m Available space: $AVAILABLE_SPACE KB"
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
    mkdir -p /root/tailscale.bak
    cp /usr/sbin/tailscaled /root/tailscale.bak/tailscaled
    cp /usr/sbin/tailscale /root/tailscale.bak/tailscale
    echo "The backup of tailscale is located in /root/tailscale.bak/"
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
    wget -qO /tmp/tailscale.tar.gz https://pkgs.tailscale.com/stable/$TAILSCALE_VERSION_NEW
    # Extract tailscale
    echo "Extracting tailscale ..."
    mkdir /tmp/tailscale
    tar xzf /tmp/tailscale.tar.gz -C /tmp/tailscale
    # Removing archive
    rm /tmp/tailscale.tar.gz
}

install_tailscale(){
    echo "┌────────────────────────────────────────────────────────────────────────┐"
    echo "│ I N S T A L L I N G   T A I L S C A L E                                │"
    echo "└────────────────────────────────────────────────────────────────────────┘"
    # Stop tailscale
    echo "Stopping tailscale ..."
    /etc/init.d/tailscale stop 2&>/dev/null
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
    /etc/init.d/tailscale restart 2&>/dev/null
}

upgrade_persistance(){
    echo "┌────────────────────────────────────────────────────────────────────────┐"
    echo "│ U P G R A D E   P E R S I S T A N C E                                  │"
    echo "└────────────────────────────────────────────────────────────────────────┘"
    echo "The update was successful. Do you want to make the installation permanent?"
    echo "This will make your tailscale installation persistent over firmware upgrades."
    echo "Please note that this is not officially supported by GL.iNet."
    echo "It could lead to issues, even if not likely. Just keep that in mind."
    echo "In worst case, you might need to remove the config from /etc/sysupgrade.conf"
    echo "Do you want to make the installation permanent? (y/N)"
    if [ "$FORCE" -eq 1 ]; then
        echo "--force flag is used. Making installation permanent ..."
        answer_create_persistance="y"
    else
        read answer_create_persistance
    fi
    if [ "$answer_create_persistance" != "${answer_create_persistance#[Yy]}" ]; then
        echo "Making installation permanent ..."
        echo "Modifying /etc/sysupgrade.conf ..."
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

invoke_outro() {
    echo -e "\033[32m┌────────────────────────────────────────────────────────────────────────┐\033[0m"
    echo -e "\033[32m│ S C R I P T   F I N I S H E D   S U C C E S S F U L L Y                │\033[0m"
    echo -e "\033[32m└────────────────────────────────────────────────────────────────────────┘\033[0m"
    echo "Script finished successfully. The new tailscale version (software, daemon) is:"
    tailscale version
    tailscaled --version
}
# Main
# Variables
IGNORE_FREE_SPACE=0
FORCE=0
# Read arguments
for arg in "$@"; do
    if [ "$arg" = "--ignore-free-space" ]; then
        IGNORE_FREE_SPACE=1
    fi
    if [ "$arg" = "--force" ]; then
        FORCE=1
    fi
done
invoke_intro
preflight_check
echo "Do you want to continue? (y/N)"
if [ "$FORCE" -eq 1 ]; then
    echo "--force flag is used. Continuing ..."
    answer="y"
else
    read answer
fi
if [ "$answer" != "${answer#[Yy]}" ]; then
    if [ "$IGNORE_FREE_SPACE" -eq 1 ]; then
        echo -e "\033[31m---\033[0m"
        echo -e "\033[31mWARNING: --ignore-free-space is used. There will be no backup of your current version of tailscale!\033[0m"
        echo -e "\033[31mYou might need to reset your router to factory settings if something goes wrong.\033[0m"
        echo -e "\033[31m---\033[0m"
        echo "Are you sure you want to continue? (y/N)"
        if [ "$FORCE" -eq 1 ]; then
            echo "--force flag is used. Continuing ..."
            answer="y"
        else
            read answer
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
