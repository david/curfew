# Curfew

Isolated development environment in a container. Ubuntu 24.04 LTS with Wayland/GPU support, CLI tools, and a pre-configured `app` user.

Published to `ghcr.io/david/curfew:latest`.

## Usage

```bash
# Place the launcher in your PATH
cp bin/curfew ~/.local/bin/

# From any project directory:
curfew restart        # start/recreate the container
curfew run            # open a bash shell
curfew run lazygit    # run a specific command
```

The launcher mounts the host project directory at `/app` inside the container. A named volume (`curfew-<project>-app-home`) persists the home directory across runs and is shared by all workspaces under the same project.

## What's included

**System:** Wayland libs, Mesa/GPU drivers, wl-clipboard, libnotify, locale (en_US.UTF-8)

**Packages:** Google Chrome, git, curl, wget, sudo

**CLI tools (via [ubi](https://github.com/houseabsolute/ubi)):** bat, eza, atuin, ripgrep, gh, lazygit, direnv, starship, mailpit, process-compose, agent-browser, beads

**Shell:** [ble.sh](https://github.com/akinomyoga/ble.sh), kitty terminfo

**Dev tools:** Claude Code, pre-configured PostgreSQL and Node.js apt repos (install as needed per project)

## Config files

The launcher mounts a config directory (default `~/.config/curfew`, override with `CURFEW_CONFIG`) into the container. On each start, the entrypoint symlinks files into the home directory:

| Source path | Destination |
|---|---|
| `bash/*` | `~/.<filename>` (e.g. `bash/bashrc` -> `~/.bashrc`) |
| `claude/*` | `~/.claude/<files>` |
| Everything else | `~/.config/<name>/<files>` |

This lets tools write their own state alongside the symlinked config files.

## Build

The image is built automatically by GitHub Actions on push to main, daily at 8AM UTC, or via manual dispatch. PR builds verify the image builds but don't push.

Images are signed with [cosign](https://docs.sigstore.dev/cosign/system_config/installation/). Verify with:

```bash
cosign verify --key cosign.pub ghcr.io/david/curfew:latest
```

## Adding tools

- **Single binaries from GitHub releases:** add a `ubi --project <owner/repo> --in /usr/local/bin` line to the Containerfile (use `--exe <name>` if the binary name differs)
- **apt packages:** add to the base `apt-get install` block
- **Third-party apt repos:** call `add-apt-repo` then add the package name
