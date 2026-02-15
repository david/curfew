# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Is

Curfew is a container image definition for an isolated development environment. It builds an Ubuntu 24.04 LTS image with Wayland/GPU support, CLI tools, and a pre-configured `app` user. The image is published to `ghcr.io/<owner>/curfew:latest`.

## Build & CI

The image is built by GitHub Actions (`.github/workflows/build-boxkit.yml`) using `redhat-actions/buildah-build`. There is no local build step — push to `main` and the workflow builds, pushes to GHCR, and signs with cosign.

- **Trigger**: push to main, weekly (Tue 00:00 UTC), or manual dispatch
- **PR builds**: build only, no push/sign
- **Image signing**: cosign with private key stored as `SIGNING_SECRET` repo secret; public key is `cosign.pub`

## Repository Structure

- `ContainerFiles/curfew` — the Containerfile (the main artifact of this repo)
- `scripts/add-apt-repo.sh` — reusable helper to add apt repos with GPG keys: `add-apt-repo <name> <key-url> <deb-url> [components...]`
- `cosign.pub` — public key for image verification
- `cosign.key` — private key (gitignored, never commit)

## Image Architecture

The Containerfile is organized in layers:

1. **Base apt packages** — Wayland libs, Mesa/GPU drivers, wl-clipboard, core utilities, locale generation
2. **ENV** — `LANG`, `LC_ALL` (en_US.UTF-8), `AGENT_BROWSER_EXECUTABLE_PATH` (points to system Chrome)
3. **Third-party apt repos** — uses `add-apt-repo.sh` helper, then installs (currently: Google Chrome)
4. **CLI tools via [ubi](https://github.com/houseabsolute/ubi)** — single-binary tools from GitHub releases (bat, eza, atuin, rg, mailpit, process-compose, direnv, starship, agent-browser, beads)
5. **ble.sh** — installed to `/usr/local/share/blesh`
6. **User setup** — removes default `ubuntu` user, creates `app` (uid/gid 1000) with passwordless sudo
7. **Claude Code** — installed as `app` user via official install script
8. **WORKDIR /app**

## Adding Tools

- **Single binaries from GitHub releases**: add a `ubi --project <owner/repo> --in /usr/local/bin` line. Use `--exe <name>` if the binary name differs from the project name (e.g. ripgrep → `--exe rg`).
- **apt packages**: add to the base `apt-get install` block.
- **Third-party apt repos**: call `add-apt-repo` in the existing RUN block before `apt-get update`, then add the package name to the `apt-get install` list below it.

## Conventions

- The Containerfile name must match the image name (`curfew`).
- `--no-install-recommends` for all apt installs.
- Clean up apt caches in the same RUN layer (`apt-get clean && rm -rf /var/lib/apt/lists/*`).
- Shell init (ble.sh, direnv, starship, atuin) is **not** baked into `.bashrc` — it's provided via volume mounts at runtime.
- Node.js is per-project, not in the base image. Playwright uses system Chrome (`channel: 'chrome'`).
