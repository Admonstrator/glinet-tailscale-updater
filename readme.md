# Tailscale Update Script for GL.iNet Routers

This script is designed to update Tailscale on GL.iNet routers.

It was created by [Admon](https://forum.gl-inet.com/u/admon/) for the GL.iNet community and tested on the MT-6000 (Flint2) with firmware 4.5.4.

## Requirements

- GL.iNet router with firmware 4.x
- Supported architecture: arm64, armv7, mips

## Usage

Run the script with the following command:

```shell
./update-tailscale.sh [--ignore-free-space] [--force]
```

You can run it without cloning the repository by using the following command:

```shell
wget -O update-tailscale.sh https://raw.githubusercontent.com/Admonstrator/glinet.forum/main/scripts/update-tailscale/update-tailscale.sh && sh update-tailscale.sh
```

## Force update

By using the --force option, the script will skip all confirmation prompts. It will make the install permanent. This is useful for unattended installations. In combination with --ignore-free-space, it will also skip the free space check. Please use with caution!

## Running on devices with low free space

You can use --ignore-free-space to ignore the free space check. This is useful for devices with low free space.

In that case there will be no backup of the original files and the script will not check if there is enough free space to download the new files. Could potentially break your router if there is not enough free space.

## Feedback

Feel free to provide feedback in the [GL.iNet forum](https://forum.gl-inet.com/t/how-to-update-tailscale-on-arm64/37582).

## Reverting

To revert the changes, replace the `/usr/sbin/tailscaled` and `/usr/sbin/tailscale` files with the original files.
The original files can be found in the `/root/tailscale.bak` folder - they are named `tailscaled` and `tailscale`.

## Disclaimer

This script is provided as is and without any warranty. Use it at your own risk.

**It may break your router, your computer, your network or anything else. It may even burn down your house.**

**You have been warned!**
