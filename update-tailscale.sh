#!/bin/sh
#
#
# Description: This script updates tailscale on GL.iNet routers
# Thread: https://forum.gl-inet.com/t/how-to-update-tailscale-on-arm64/37582
# Author: Admon
# Date: 2024-01-21
# Version: 0.1
#
# Usage: ./update-tailscale.sh
# Warning: This script might potentially harm your router. Use it at your own risk.
#

# Detect architecture
ARCH=$(uname -m)
# Only continue if architecture is arm64
if [ "$ARCH" != "aarch64" ]; then
    echo "This script only works on arm64 architecture."
    exit 1
fi

# Detect firmware version
FIRMWARE_VERSION=$(cat /etc/glversion)
# Only continue if firmware version is 4 or higher
if [ "${FIRMWARE_VERSION:0:1}" -lt 4 ]; then
    echo "This script only works on firmware version 4 or higher."
    exit 1
fi

# Get latest tailscale version
TAILSCALE_VERSION_NEW=$(curl -s https://pkgs.tailscale.com/stable/#static | grep -o 'tailscale_[0-9]*\.[0-9]*\.[0-9]*_arm64\.tgz' | head -n 1)

# Stop if tailscale URL is empty
if [ -z "$TAILSCALE_VERSION_NEW" ]; then
    echo "Could not get latest tailscale version. Please check your internet connection."
    exit 1
fi

echo "Another GL.iNET router script by Admon for the GL.iNET community"
echo "---"
echo "WARNING: THIS SCRIPT MIGHT POTENTIALLY HARM YOUR ROUTER!"
echo "It's only recommended to use this script if you know what you're doing."
echo "---"
echo "This script will update tailscale to $TAILSCALE_VERSION_NEW on your router."
echo "Do you want to continue? (y/N)"
read answer

if [ "$answer" != "${answer#[Yy]}" ]; then
    # Stop tailscale
    echo "Stopping tailscale ..."
    /etc/init.d/tailscale stop 2&> /dev/null
    # Create backup of tailscale
    echo "Creating backup of tailscale ..."
    cp /usr/sbin/tailscaled /usr/sbin/tailscaled.bak
    cp /usr/sbin/tailscale /usr/sbin/tailscale.bak
    echo "The backup of tailscale is located at /usr/sbin/tailscaled.bak and /usr/sbin/tailscale.bak"
    # Download latest tailscale
    echo "Downloading latest tailscale version ..."
    wget -qO /tmp/tailscale.tar.gz https://pkgs.tailscale.com/stable/$TAILSCALE_VERSION_NEW 2&> /dev/null
    # Extract tailscale
    echo "Extracting tailscale ..."
    tar -xzf /tmp/tailscale.tar.gz -C /tmp/tailscale 2&> /dev/null
    # Copy tailscale to /usr/sbin
    echo "Copying tailscale to /usr/sbin ..."
    cp /tmp/tailscale/*/tailscale /usr/sbin/tailscale 2&> /dev/null
    cp /tmp/tailscale/*/tailscaled /usr/sbin/tailscaled 2&> /dev/null
    # Remove temporary files
    echo "Removing temporary files ..."
    rm -rf /tmp/tailscale.tar.gz /tmp/tailscale 2&> /dev/null
    # Restart tailscale
    echo "Restarting tailscale ..."
    /etc/init.d/tailscale restart 2&> /dev/null
    echo "Done!"
else
    echo "Ok, see you next time!"
fi