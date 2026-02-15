# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Is

Curfew is a container image definition for an isolated development environment. It builds an Ubuntu 24.04 LTS image with Wayland/GPU support, CLI tools, and a pre-configured `app` user. The image is published to `ghcr.io/<owner>/curfew:latest`.

## Build & CI

The image is built by GitHub Actions (`.github/workflows/build-boxkit.yml`) using `redhat-actions/buildah-build`. There is no local build step — push to `main` and the workflow builds, pushes to GHCR, and signs with cosign.

- **Trigger**: push to main, daily at 8AM UTC, or manual dispatch
- **PR builds**: build only, no push/sign
- **Image signing**: cosign with private key stored as `SIGNING_SECRET` repo secret; public key is `cosign.pub`

## Repository Structure

- `ContainerFiles/curfew` — the Containerfile (the main artifact of this repo)
- `scripts/entrypoint.sh` — entrypoint that symlinks config files into `/home/app` on each start
- `scripts/add-apt-repo.sh` — reusable helper to add apt repos with GPG keys: `add-apt-repo <name> <key-url> <deb-url> [components...]`
- `bin/curfew` — launcher script (intended for `~/.local/bin`)
- `terminfo/` — kitty terminfo, copied into the image at build time
- `cosign.pub` — public key for image verification
- `cosign.key` — private key (gitignored, never commit)

## Image Architecture

The Containerfile is organized in layers:

1. **Base apt packages** — Wayland libs, Mesa/GPU drivers, wl-clipboard, libnotify, core utilities, locale generation
2. **ENV** — `LANG`, `LC_ALL` (en_US.UTF-8), `AGENT_BROWSER_EXECUTABLE_PATH` (system Chrome), `DBUS_SESSION_BUS_ADDRESS`
3. **Third-party apt repos** — uses `add-apt-repo.sh` helper, then installs (currently: Google Chrome). PostgreSQL (PGDG) and Node.js (NodeSource) repos are added but no packages installed.
4. **CLI tools via [ubi](https://github.com/houseabsolute/ubi)** — single-binary tools from GitHub releases (bat, eza, atuin, rg, mailpit, process-compose, direnv, starship, lazygit, agent-browser, beads)
5. **ble.sh** — installed to `/usr/local/share/blesh`
6. **Kitty terminfo** — `xterm-kitty` copied to `/usr/share/terminfo/x/`
7. **Entrypoint** — `scripts/entrypoint.sh` copied to `/usr/local/bin/entrypoint`
8. **User setup** — removes default `ubuntu` user, creates `app` (uid/gid 1000) with passwordless sudo
9. **Claude Code** — installed as `app` user via official install script

## Launcher (`bin/curfew`)

The launcher script sets up all runtime mounts and runs the container:

- **Project directory**: mounted at the same host path (`--workdir` sets cwd)
- **Home volume**: named volume `<project-name>-app-home` at `/home/app` (persists shell history, caches, tool state across runs)
- **Config files**: `~/Dot/w0/config` (override with `CURFEW_CONFIG`) mounted read-only at `/etc/curfew/config`
- **Wayland**: `$XDG_RUNTIME_DIR/$WAYLAND_DISPLAY` mounted into the container
- **D-Bus**: session bus socket for notifications (`notify-send`)
- **GPU**: `--device /dev/dri`
- **TERM**: passed through for kitty terminfo

Usage: `curfew [project-dir]` (defaults to cwd)

## Config File Mapping (entrypoint)

On each start, `entrypoint.sh` recursively symlinks **individual files** (not directories) from `/etc/curfew/config` into `/home/app`. This lets tools write their own state/caches alongside the symlinked config files.

Mapping rules:
- `bash/*` → `~/.<filename>` (e.g. `bash/bashrc` → `~/.bashrc`)
- `claude/*` → `~/.claude/<files>`
- Everything else → `~/.config/<name>/<files>` (e.g. `nvim/init.lua` → `~/.config/nvim/init.lua`)

Nested directories are created as real directories with only leaf files symlinked.

## Adding Tools

- **Single binaries from GitHub releases**: add a `ubi --project <owner/repo> --in /usr/local/bin` line. Use `--exe <name>` if the binary name differs from the project name (e.g. ripgrep → `--exe rg`).
- **apt packages**: add to the base `apt-get install` block.
- **Third-party apt repos**: call `add-apt-repo` in the existing RUN block before `apt-get update`, then add the package name to the `apt-get install` list below it.

## Conventions

- The Containerfile name must match the image name (`curfew`).
- `--no-install-recommends` for all apt installs.
- Clean up apt caches in the same RUN layer (`apt-get clean && rm -rf /var/lib/apt/lists/*`).
- Shell init (ble.sh, direnv, starship, atuin) is **not** baked into the image — provided via config file mounts.
- Node.js and PostgreSQL are per-project (repos are pre-configured, install as needed). Playwright uses system Chrome (`channel: 'chrome'`).
- The container mounts the host project directory at the same path (no indirection).
