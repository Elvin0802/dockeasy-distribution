# DockEasy `install.sh` — Usage

One script handles **install**, **update**, and **uninstall**. Always run it with **`bash`** (the script uses bash features — `sh` will not work).

- Script URL: `https://sirajli.dev/dockeasy/install.sh`
- Must run as **root** (use `sudo -i` or a root shell).
- Only **Linux** hosts; it refuses to run inside a Docker container.
- Ports **80** and **443** must be free on first install.
- Docker is installed automatically if missing.

---

## Quick reference

| Action | Command |
|---|---|
| Install latest | `curl -sSL https://sirajli.dev/dockeasy/install.sh \| bash` |
| Install specific version | `curl -sSL https://sirajli.dev/dockeasy/install.sh \| bash -s -- --version v0.1.1` |
| Update to latest | `curl -sSL https://sirajli.dev/dockeasy/install.sh \| bash -s -- update` |
| Update to specific version | `curl -sSL https://sirajli.dev/dockeasy/install.sh \| bash -s -- update --version v0.1.1` |
| Uninstall (keep data) | `curl -sSL https://sirajli.dev/dockeasy/install.sh \| bash -s -- uninstall` |
| Uninstall (delete data) | download first, then `bash install.sh uninstall` and answer `y` (see below) |

> `bash -s --` means: run the piped script and pass everything after `--` as its arguments.

---

## Install

**Latest stable version** (auto-detected from `version.json`, falls back to `latest`):

```bash
curl -sSL https://sirajli.dev/dockeasy/install.sh | bash
```

**A specific version** — two equivalent ways:

```bash
# via flag
curl -sSL https://sirajli.dev/dockeasy/install.sh | bash -s -- --version v0.1.1

# via environment variable
curl -sSL https://sirajli.dev/dockeasy/install.sh | DOCKEASY_VERSION=v0.1.1 bash
```

After install, open `http://<server-ip>` and go to `http://<server-ip>/auth/setup` to create the admin account.

---

## Update

Updates image tags in `/etc/dockeasy/.env`, re-downloads the compose file, pulls new images, and restarts the containers. Your database and config are preserved.

**To the latest version:**

```bash
curl -sSL https://sirajli.dev/dockeasy/install.sh | bash -s -- update
```

**To a specific version** — two equivalent ways:

```bash
# via flag
curl -sSL https://sirajli.dev/dockeasy/install.sh | bash -s -- update --version v0.1.1

# via environment variable
curl -sSL https://sirajli.dev/dockeasy/install.sh | DOCKEASY_VERSION=v0.1.1 bash -s -- update
```

---

## Uninstall

Stops and removes all DockEasy containers and deletes `/etc/dockeasy`.

```bash
curl -sSL https://sirajli.dev/dockeasy/install.sh | bash -s -- uninstall
```

**About database volumes:** uninstall asks *"Remove database volumes too?"*.
- When piped through `curl ... | bash`, the prompt receives no keyboard input and defaults to **No** — your database volume is **kept** (safe).
- To actually **delete all data**, download the script and run it locally so you can answer the prompt:

```bash
curl -sSL https://sirajli.dev/dockeasy/install.sh -o install.sh
bash install.sh uninstall
# answer: y   (to delete database volumes)
```

---

## Running from a downloaded file

If you saved the script locally (e.g. `install.sh`), pass the command/flags directly — no `-s --` needed:

```bash
bash install.sh                          # install latest
bash install.sh --version v0.1.1         # install a specific version
DOCKEASY_VERSION=v0.1.1 bash install.sh  # install a specific version (env var)
bash install.sh update                   # update to latest
bash install.sh update --version v0.1.1  # update to a specific version
bash install.sh uninstall                # uninstall (interactive prompt works here)
```

---

## Version selection — how it's resolved

The version is chosen in this order:

1. `--version vX.Y.Z` flag (highest priority).
2. `DOCKEASY_VERSION=vX.Y.Z` environment variable.
3. Auto-detected latest from `https://sirajli.dev/dockeasy/version.json`.
4. Falls back to the `latest` image tag if detection fails.

Use tags exactly as published (with the leading `v`), e.g. `v0.1.1`.

---

## Where things live

| Path | Purpose |
|---|---|
| `/etc/dockeasy/docker-compose.prod.yml` | Compose file for the DockEasy system containers |
| `/etc/dockeasy/.env` | Generated secrets, version, and image tags |
| `/etc/dockeasy/traefik/dynamic/system.yml` | Traefik routing config (managed by DockEasy) |
| `/etc/dockeasy/traefik/acme/` | Let's Encrypt certificate storage |

---

## Troubleshooting

- **"This script must be run as root."** → run as root (`sudo -i`, then the command).
- **"Port 80/443 is already in use."** → stop whatever is bound to those ports (another web server / proxy) and retry.
- **"Docker Compose plugin not found."** → update Docker to a version that includes `docker compose` (v2).
- **"DockEasy is not installed. Run install first."** (on update) → run the install command first.
- **`sh: ... not found` / syntax errors** → you used `sh`. Always use **`bash`**.
