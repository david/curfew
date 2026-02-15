#!/bin/bash
set -euo pipefail

CONFIG_DIR="/etc/curfew/config"
HOME_DIR="/home/app"

if [ -d "$CONFIG_DIR" ]; then
    mkdir -p "$HOME_DIR/.config"

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
                ln -sfn "$entry" "$HOME_DIR/.claude"
                ;;
            *)
                # everything else → ~/.config/<name>
                ln -sfn "$entry" "$HOME_DIR/.config/$name"
                ;;
        esac
    done
fi

exec "$@"
