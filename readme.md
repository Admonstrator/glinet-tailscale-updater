# Tailscale Update Script for GL.iNet Routers

This script is designed to update Tailscale on GL.iNet routers. It was created by Admon for the GL.iNet community and tested on the MT-6000 (Flint2) with firmware 4.5.4.

## Warning

This script might potentially harm your router. Use it at your own risk. It is recommended to use this script only if you know what you are doing.

## Usage

Run the script with the following command:

```shell
./update-tailscale.sh
```

You can run it without cloning the repository by using the following command:

```shell
wget -O update-tailscale.sh https://raw.githubusercontent.com/Admonstrator/glinet.forum/main/scripts/update-tailscale/update-tailscale.sh && sh update-tailscale.sh
```
