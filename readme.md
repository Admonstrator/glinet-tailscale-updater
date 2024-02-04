# Tailscale Update Script for GL.iNet Routers

This script is designed to update Tailscale on GL.iNet routers.

It was created by [Admon](https://forum.gl-inet.com/u/admon/) for the GL.iNet community and tested on the MT-6000 (Flint2) with firmware 4.5.4.

## Usage

Run the script with the following command:

```shell
./update-tailscale.sh [--ignore-free-space]
```

You can run it without cloning the repository by using the following command:

```shell
wget -O update-tailscale.sh https://raw.githubusercontent.com/Admonstrator/glinet.forum/main/scripts/update-tailscale/update-tailscale.sh && sh update-tailscale.sh
```

## Running on devices with low free space

You can use --ignore-free-space to ignore the free space check. This is useful for devices with low free space.

In that case there will be no backup of the original files and the script will not check if there is enough free space to download the new files. Could potentially break your router if there is not enough free space.

## Feedback

Feel free to provide feedback in the [GL.iNet forum](https://forum.gl-inet.com/t/how-to-update-tailscale-on-arm64/37582).

## Reverting

To revert the changes, replace the `/usr/sbin/tailscaled` and `/usr/sbin/tailscale` files with the original files.
The original files can be found in the `/usr/sbin/` folder - they are named `tailscaled.bak` and `tailscale.bak`.

## Disclaimer

This script is provided as is and without any warranty. Use it at your own risk.

**It's a really early stage and definitely not ready for production use.**

**It may break your router, your computer, your network or anything else. It may even burn down your house.**

**You have been warned!**