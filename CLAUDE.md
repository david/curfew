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
- `scripts/entrypoint.sh` — container entrypoint: symlinks config files, runs autostart scripts, execs into `"$@"`
- `scripts/add-apt-repo.sh` — reusable helper to add apt repos with GPG keys: `add-apt-repo <name> <key-url> <deb-url> [components...]`
- `scripts/alias/` — command wrappers installed to `/usr/local/alias/` (shadow `/usr/local/bin`)
- `scripts/installs/` — self-contained install scripts, copied to `/usr/local/installs/` in the image (see below)
- `bin/curfew` — launcher script (intended for `~/.local/bin`)
- `cosign.pub` — public key for image verification
- `cosign.key` — private key (gitignored, never commit)

## Image Architecture

The Containerfile is organized in layers:

1. **Base apt packages** — Wayland libs, Mesa/GPU drivers, wl-clipboard, libnotify, core utilities, locale generation
2. **ENV** — `LANG`, `LC_ALL` (en_US.UTF-8), `AGENT_BROWSER_EXECUTABLE_PATH` (system Chrome), `DBUS_SESSION_BUS_ADDRESS`
3. **Install helpers** — `add-apt-repo` and `scripts/installs/*` copied into the image
4. **Chrome** — installed via `/usr/local/installs/chrome`
5. **CLI tools via [ubi](https://github.com/houseabsolute/ubi)** — single-binary tools from GitHub releases (rg, gh, agent-browser)
6. **Entrypoint** — `scripts/entrypoint.sh` copied to `/usr/local/bin/entrypoint` (config symlinking + autostart)
7. **User setup** — removes default `ubuntu` user, creates `app` (uid/gid 1000) with passwordless sudo
8. **Claude Code** — installed as `app` user via official install script

## Launcher (`bin/curfew`)

The launcher uses systemd template units (`NAME@TREE`) and Podman Quadlet files to manage per-worktree containers. A `.curfew.json` marker in the project parent directory ties worktrees to a shared set of quadlet files.

### Directory layout

```
/home/user/projects/myapp/          # project parent dir
├── .curfew.json                    # {"name": "myapp"} — written by quadlet add
├── main/                           # worktree
│   └── .curfew.dockerfile          # written by containerfile gen
└── feature/                        # worktree
    └── .curfew.dockerfile
```

Quadlet files in `~/.config/containers/systemd/`:
```
myapp.volume        # shared volume across all worktrees
myapp@.build        # template — %i is the tree name
myapp@.container    # template — %i is the tree name
```

### `curfew quadlet add <name> [--force] [-p host:container]...`

Generates three quadlet template files and writes `../.curfew.json`:

- `NAME.volume` — named volume (`NAME-app-home`, shared across worktrees)
- `NAME@.build` — template build unit, uses `%i` for the tree name
- `NAME@.container` — template container unit with all mounts, env, and ports

Runs `systemctl --user daemon-reload`. Refuses if files exist (unless `--force`). `-p` adds `PublishPort=` lines.

Environment values (`TERM`, `WAYLAND_DISPLAY`, `XDG_RUNTIME_DIR`, config dir, project dir) are baked at gen time. Re-run `quadlet add --force` if they change.

### `curfew quadlet rm`

Reads name from `../.curfew.json`, removes the three quadlet files and `.curfew.json`, runs `systemctl --user daemon-reload`.

### `curfew containerfile gen [--force] [-i tool[:version]]...`

Generates `.curfew.dockerfile` in the current directory. `-i` adds install script `RUN` lines. Refuses if the file exists (unless `--force`).

### `curfew run [cmd...]`

Reads name from `../.curfew.json`, derives tree from `basename $PWD`. Runs `podman exec -it` into `NAME-TREE` (defaults to `bash`). Does **not** auto-start — prints a `systemctl --user start NAME@TREE` hint if the container isn't running.

### Lifecycle via systemd

| Action | Command |
|--------|---------|
| Start | `systemctl --user start NAME@TREE` |
| Stop | `systemctl --user stop NAME@TREE` |
| Restart/rebuild | `systemctl --user restart NAME@TREE` |
| Logs | `journalctl --user -u NAME@TREE` |

## Entrypoint & Autostart

The container uses `scripts/entrypoint.sh` as its entrypoint (`ENTRYPOINT ["entrypoint"]`). On boot it:

1. Symlinks config files from `/etc/curfew/config` into `/home/app`
2. Runs autostart scripts from `/usr/local/etc/curfew/autostart/`
3. Execs into `"$@"`

### Config file mapping

The entrypoint recursively symlinks **individual files** (not directories) from `/etc/curfew/config` into `/home/app`. This lets tools write their own state/caches alongside the symlinked config files.

Mapping rules:
- `bash/*` → `~/.<filename>` (e.g. `bash/bashrc` → `~/.bashrc`)
- `claude/*` → `~/.claude/<files>`
- Everything else → `~/.config/<name>/<files>` (e.g. `nvim/init.lua` → `~/.config/nvim/init.lua`)

Nested directories are created as real directories with only leaf files symlinked.

### Autostart scripts (`/usr/local/etc/curfew/autostart/`)

Executable scripts in this directory are run in the background at container boot (before `exec "$@"`). Install scripts register daemons here.

### Adding a background service via install scripts

Install scripts should register autostart scripts for background daemons:

```bash
mkdir -p /usr/local/etc/curfew/autostart
cat <<'AUTOSTART' > /usr/local/etc/curfew/autostart/NAME
#!/bin/bash
exec my-daemon
AUTOSTART
chmod +x /usr/local/etc/curfew/autostart/NAME
```

## Install Scripts (`scripts/installs/`)

Self-contained scripts copied to `/usr/local/installs/` in the image. Each script adds the necessary apt repo (via `add-apt-repo`), installs the package, and cleans up. Downstream images based on curfew can call these to install per-project tools.

| Script | Default | Usage |
|--------|---------|-------|
| `chrome` | — | `/usr/local/installs/chrome` |
| `mailpit` | latest | `/usr/local/installs/mailpit` |
| `node` | v24 | `/usr/local/installs/node [major-version]` |
| `postgres` | v17 | `/usr/local/installs/postgres [version]` |
| `process-compose` | latest | `/usr/local/installs/process-compose` |
| `bun` | latest | `/usr/local/installs/bun [version]` |

Chrome is installed in the base image. The others are available for downstream use.

To add a new install script: create `scripts/installs/<name>` following the same pattern (set `DEBIAN_FRONTEND`, call `add-apt-repo` if needed, install, clean up). If the tool needs a background daemon, register an autostart script (see "Adding a background service" above). If the script needs a user-phase step (e.g. installing packages as `app`), support `--user` as the first argument — the root phase runs by default, `--user` runs the app phase. The Containerfile calls the script twice: once as root, once as `USER app` with `--user`.

## Adding Tools

- **Single binaries from GitHub releases**: add a `ubi --project <owner/repo> --in /usr/local/bin` line. Use `--exe <name>` if the binary name differs from the project name (e.g. ripgrep → `--exe rg`).
- **apt packages**: add to the base `apt-get install` block.
- **Tools with third-party apt repos**: create an install script in `scripts/installs/` (see above).

## Conventions

- The Containerfile name must match the image name (`curfew`).
- `--no-install-recommends` for all apt installs.
- Clean up apt caches in the same RUN layer (`apt-get clean && rm -rf /var/lib/apt/lists/*`).
- Shell init is **not** baked into the image — provided via config file mounts.
- Playwright uses system Chrome (`channel: 'chrome'`).
- The container mounts the host project directory at `/app`.
