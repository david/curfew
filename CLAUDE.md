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
- `scripts/alias/` — command wrappers installed to `/usr/local/alias/` (shadow `/usr/local/bin`)
- `scripts/installs/` — self-contained install scripts, copied to `/usr/local/installs/` in the image (see below)
- `bin/curfew` — launcher script (intended for `~/.local/bin`)
- `terminfo/` — kitty terminfo, copied into the image at build time
- `cosign.pub` — public key for image verification
- `cosign.key` — private key (gitignored, never commit)

## Image Architecture

The Containerfile is organized in layers:

1. **Base apt packages** — Wayland libs, Mesa/GPU drivers, wl-clipboard, libnotify, core utilities, locale generation
2. **ENV** — `LANG`, `LC_ALL` (en_US.UTF-8), `AGENT_BROWSER_EXECUTABLE_PATH` (system Chrome), `DBUS_SESSION_BUS_ADDRESS`
3. **Install helpers** — `add-apt-repo` and `scripts/installs/*` copied into the image
4. **Chrome** — installed via `/usr/local/installs/chrome`
5. **CLI tools via [ubi](https://github.com/houseabsolute/ubi)** — single-binary tools from GitHub releases (bat, eza, atuin, rg, mailpit, process-compose, direnv, starship, lazygit, agent-browser, beads)
6. **ble.sh** — installed to `/usr/local/share/blesh`
7. **Kitty terminfo** — `xterm-kitty` copied to `/usr/share/terminfo/x/`
8. **Entrypoint** — `scripts/entrypoint.sh` copied to `/usr/local/bin/entrypoint`
9. **User setup** — removes default `ubuntu` user, creates `app` (uid/gid 1000) with passwordless sudo
10. **Claude Code** — installed as `app` user via official install script

## Launcher (`bin/curfew`)

The launcher generates Podman Quadlet files and delegates container lifecycle to systemd. Two commands:

### `curfew gen [--force] [-i tool[:version]]... [-p host:container]...`

Generates four files and runs `systemctl --user daemon-reload`:

- `~/.config/containers/systemd/<unit>.volume` — named volume (`curfew-<project>-app-home`, shared across worktrees)
- `~/.config/containers/systemd/<unit>.build` — builds from `.curfew.dockerfile` with `Pull=always`
- `~/.config/containers/systemd/<unit>.container` — container definition with all mounts, env, and ports
- `.curfew.dockerfile` — in the project directory, `FROM ghcr.io/david/curfew:latest` plus install scripts

Unit name is `curfew-<project>-<tree>` derived from the current directory. `--force` overwrites existing files. `-i` adds install script RUN lines to the Dockerfile. `-p` adds `PublishPort=` lines to the .container file.

Environment values (`TERM`, `WAYLAND_DISPLAY`, `XDG_RUNTIME_DIR`, config dir, project dir) are baked at gen time. Re-run `gen --force` if they change.

### `curfew run [cmd...]`

Runs `podman exec -it` into the container (defaults to `bash`). Does **not** auto-start — prints a `systemctl --user start` hint if the container isn't running.

### Lifecycle via systemd

| Action | Command |
|--------|---------|
| Start | `systemctl --user start curfew-PROJECT-TREE` |
| Stop | `systemctl --user stop curfew-PROJECT-TREE` |
| Restart/rebuild | `systemctl --user restart curfew-PROJECT-TREE` |
| Logs | `journalctl --user -u curfew-PROJECT-TREE` |

## Config File Mapping (entrypoint)

On each start, `entrypoint.sh` recursively symlinks **individual files** (not directories) from `/etc/curfew/config` into `/home/app`. This lets tools write their own state/caches alongside the symlinked config files.

Mapping rules:
- `bash/*` → `~/.<filename>` (e.g. `bash/bashrc` → `~/.bashrc`)
- `claude/*` → `~/.claude/<files>`
- Everything else → `~/.config/<name>/<files>` (e.g. `nvim/init.lua` → `~/.config/nvim/init.lua`)

Nested directories are created as real directories with only leaf files symlinked.

## Install Scripts (`scripts/installs/`)

Self-contained scripts copied to `/usr/local/installs/` in the image. Each script adds the necessary apt repo (via `add-apt-repo`), installs the package, and cleans up. Downstream images based on curfew can call these to install per-project tools.

| Script | Default | Usage |
|--------|---------|-------|
| `chrome` | — | `/usr/local/installs/chrome` |
| `node` | v24 | `/usr/local/installs/node [major-version]` |
| `postgres` | v17 | `/usr/local/installs/postgres [version]` |
| `bun` | latest | `/usr/local/installs/bun [version]` |

Chrome is installed in the base image. The others are available for downstream use.

To add a new install script: create `scripts/installs/<name>` following the same pattern (set `DEBIAN_FRONTEND`, call `add-apt-repo` if needed, install, clean up).

## Adding Tools

- **Single binaries from GitHub releases**: add a `ubi --project <owner/repo> --in /usr/local/bin` line. Use `--exe <name>` if the binary name differs from the project name (e.g. ripgrep → `--exe rg`).
- **apt packages**: add to the base `apt-get install` block.
- **Tools with third-party apt repos**: create an install script in `scripts/installs/` (see above).

## Conventions

- The Containerfile name must match the image name (`curfew`).
- `--no-install-recommends` for all apt installs.
- Clean up apt caches in the same RUN layer (`apt-get clean && rm -rf /var/lib/apt/lists/*`).
- Shell init (ble.sh, direnv, starship, atuin) is **not** baked into the image — provided via config file mounts.
- Playwright uses system Chrome (`channel: 'chrome'`).
- The container mounts the host project directory at `/app`.
