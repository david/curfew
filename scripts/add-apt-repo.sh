#!/bin/bash
set -euo pipefail

# Usage: add-apt-repo.sh <name> <key-url> <deb-url> [component...]
# Example: add-apt-repo.sh google-chrome \
#   https://dl-ssl.google.com/linux/linux_signing_key.pub \
#   http://dl.google.com/linux/chrome/deb/ stable main

name="$1"
key_url="$2"
deb_url="$3"
shift 3
components="$*"

keyring="/usr/share/keyrings/${name}.gpg"
tmpkey="$(mktemp)"
curl -fsSL "$key_url" -o "$tmpkey"

# Check if key is already in binary (dearmored) format
if head -c1 "$tmpkey" | LC_ALL=C grep -qP '[\x80-\xff]'; then
    mv "$tmpkey" "$keyring"
else
    gpg --dearmor -o "$keyring" < "$tmpkey"
    rm "$tmpkey"
fi
echo "deb [arch=amd64 signed-by=${keyring}] ${deb_url} ${components}" \
    > "/etc/apt/sources.list.d/${name}.list"
