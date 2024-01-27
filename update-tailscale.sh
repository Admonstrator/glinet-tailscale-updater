#!/bin/sh
#
#
# Description: This script updates tailscale on GL.iNet routers
# Thread: https://forum.gl-inet.com/t/how-to-update-tailscale-on-arm64/37582
# Author: Admon
# Date: 2024-01-24
# Version: 0.3
#
# Usage: ./update-tailscale.sh [--ignore-free-space]
# Warning: This script might potentially harm your router. Use it at your own risk.
#
# Populate variables
AVAILABLE_SPACE=$(df -k / | tail -n 1 | awk '{print $4}')
ARCH=$(uname -m)
FIRMWARE_VERSION=$(cut -c1 </etc/glversion)

# Check if --ignore-free-space is used
if [ "$1" = "--ignore-free-space" ]; then
    IGNORE_FREE_SPACE=1
else
    IGNORE_FREE_SPACE=0
fi

# Choose TAILSCALE_VERSION_NEW based on architecture
if [ "$ARCH" = "aarch64" ]; then
    TAILSCALE_VERSION_NEW=$(curl -s https://pkgs.tailscale.com/stable/ | grep -o 'tailscale_[0-9]*\.[0-9]*\.[0-9]*_arm64\.tgz' | head -n 1)
elif [ "$ARCH" = "armv7l" ]; then
    TAILSCALE_VERSION_NEW=$(curl -s https://pkgs.tailscale.com/stable/ | grep -o 'tailscale_[0-9]*\.[0-9]*\.[0-9]*_arm\.tgz' | head -n 1)
else
    echo "This script only works on arm64 and armv7."
    exit 1
fi

# Detect firmware version
# Only continue if firmware version is 4 or higher
if [ "${FIRMWARE_VERSION}" -lt 4 ]; then
    echo "This script only works on firmware version 4 or higher."
    exit 1
fi

if [ "$IGNORE_FREE_SPACE" -eq 1 ]; then
    echo "Skipping free space check, because --ignore-free-space is used"
else
    if [ "$AVAILABLE_SPACE" -lt 130000 ]; then
    echo "Not enough space available. Please free up some space and try again."
    echo "The script needs at least 130 MB of free space."
    echo "---"
    echo "On devices with less internal storage, you can use --ignore-free-space to continue."
    exit 1
    fi
fi

# Stop if tailscale URL is empty
if [ -z "$TAILSCALE_VERSION_NEW" ]; then
    echo "Could not get latest tailscale version. Please check your internet connection."
    exit 1
fi

# Function for backup
backup() {
    echo "Creating backup of tailscale ..."
    cp /usr/sbin/tailscaled /usr/sbin/tailscaled.bak
    cp /usr/sbin/tailscale /usr/sbin/tailscale.bak
    echo "The backup of tailscale is located at /usr/sbin/tailscaled.bak and /usr/sbin/tailscale.bak"
}

echo "Another GL.iNET router script by Admon for the GL.iNET community"
echo "---"
echo -e "\033[31mWARNING: THIS SCRIPT MIGHT POTENTIALLY HARM YOUR ROUTER!\033[0m"
echo -e "\033[31mIt's only recommended to use this script if you know what you're doing.\033[0m"
echo "---"
echo "This script will update tailscale to $TAILSCALE_VERSION_NEW on your router."
echo "Do you want to continue? (y/N)"
read answer

if [ "$answer" != "${answer#[Yy]}" ]; then
    # Ask for confirmation when --ignore-free-space is used
    if [ "$IGNORE_FREE_SPACE" -eq 1 ]; then
        echo -e "\033[31m---\033[0m"
        echo -e "\033[31mWARNING: --ignore-free-space is used. There will be no backup of your current version of tailscale!\033[0m"
        echo -e "\033[31mYou might need to reset your router to factory settings if something goes wrong.\033[0m"
        echo -e "\033[31m---\033[0m"
        echo "Are you sure you want to continue? (y/N)"
        read answer
        if [ "$answer" != "${answer#[Yy]}" ]; then
            echo "Ok, continuing ..."
        else
            echo "Ok, see you next time!"
            exit 0
        fi
    fi
    # Stop tailscale
    echo "Stopping tailscale ..."
    /etc/init.d/tailscale stop 2&>/dev/null
    # Create backup of tailscale
    if [ "$IGNORE_FREE_SPACE" -eq 1 ]; then
        echo "Skipping backup, because --ignore-free-space is used"
    else
        backup
    fi
    # Download latest tailscale
    echo "Downloading latest tailscale version ..."
    wget -qO /tmp/tailscale.tar.gz https://pkgs.tailscale.com/stable/$TAILSCALE_VERSION_NEW
    # Extract tailscale
    echo "Extracting tailscale ..."
    mkdir /tmp/tailscale
    tar xzf /tmp/tailscale.tar.gz -C /tmp/tailscale
    # Removing archive
    rm /tmp/tailscale.tar.gz
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
    # Print new tailscale version
    echo "Script finished successfully. The new tailscale version (software, daemon) is:"
    tailscale version
    tailscaled --version
else
    echo "Ok, see you next time!"
fi

exit 0
