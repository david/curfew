#!/bin/bash
set -euo pipefail

CONFIG_DIR="/etc/curfew/config"
HOME_DIR="/home/app"

# Recursively symlink individual files from src into dest,
# creating directories as needed.
link_files() {
    local src="$1" dest="$2"
    for f in "$src"/*; do
        local name="$(basename "$f")"
        if [ -d "$f" ]; then
            mkdir -p "$dest/$name"
            link_files "$f" "$dest/$name"
        else
            ln -sfn "$f" "$dest/$name"
        fi
    done
}

if [ -d "$CONFIG_DIR" ]; then
    for entry in "$CONFIG_DIR"/*; do
        name="$(basename "$entry")"

        case "$name" in
            bash)
                # bash/* → ~/.<filename>
                for f in "$entry"/*; do
                    ln -sfn "$f" "$HOME_DIR/.$(basename "$f")"
                done
                ;;
            claude)
                # claude/ → ~/.claude/
                mkdir -p "$HOME_DIR/.claude"
                link_files "$entry" "$HOME_DIR/.claude"
                ;;
            *)
                # everything else → ~/.config/<name>
                if [ -d "$entry" ]; then
                    mkdir -p "$HOME_DIR/.config/$name"
                    link_files "$entry" "$HOME_DIR/.config/$name"
                else
                    ln -sfn "$entry" "$HOME_DIR/.config/$name"
                fi
                ;;
        esac
    done
fi

# Source environment from install scripts
for f in /etc/profile.d/deps-*.sh; do
    [ -f "$f" ] && . "$f"
done

# Start a D-Bus session bus (Chrome, libnotify, etc. need it)
if command -v dbus-daemon >/dev/null 2>&1; then
    mkdir -p /run/user/1000
    eval "$(dbus-launch --sh-syntax)"
    export DBUS_SESSION_BUS_ADDRESS
fi

# Run autostart scripts
AUTOSTART_DIR="/usr/local/etc/curfew/autostart"
if [ -d "$AUTOSTART_DIR" ]; then
    for script in "$AUTOSTART_DIR"/*; do
        [ -x "$script" ] && "$script" &
    done
fi

exec "$@"
