# UNIT3D Community Installer

Unofficial fresh-server installer for [HDInnovations/UNIT3D](https://github.com/HDInnovations/UNIT3D). This project is not affiliated with HDInnovations.

## No support, warranties or guarantees — use at your own risk

**This installer is offered strictly AS IS, with NO SUPPORT and NO WARRANTIES OR GUARANTEES OF ANY KIND, express or implied.** No guarantees are made regarding installation success, compatibility, security, reliability, continued functionality or any other result. No technical assistance, troubleshooting, maintenance or future updates are promised or provided.

**Do not contact or ask the UNIT3D or HDInnovations developers for help with this installer or issues resulting from its use.** They are not affiliated with this project and are not responsible for supporting it.

**All usage is expressly at your own risk. By using this installer, you assume all risks, liabilities, responsibilities and outcomes arising from its use**, including installation failures, data loss or corruption, downtime, security incidents, server damage, costs and any other consequences. To the fullest extent permitted by applicable law, the author and contributors accept no liability for any loss, damage or other outcome arising from its use.


Two deployment options are available: native services managed by systemd/Supervisor, or Docker Compose containers. Both bootstrap UNIT3D **v9.2.0**, pinned to commit `8b88f4c8182eb3d3912ffef425c3224dcfd596f4`.

## Supported host targets

- Debian 13
- Ubuntu 24.04 LTS
- Ubuntu 26.04 LTS

Only amd64/x86_64, fresh dedicated VPS/server installs are accepted. **Docker is the only server/application stack permitted to be preinstalled**, including its normal Engine, containerd, Buildx and Compose components. Preinstalled web servers, databases, Redis, PHP runtimes, Node.js, Composer and other checked application services are rejected, even when stopped. Native mode requires systemd. Other releases are rejected using `/etc/os-release`; the installer never rewrites your OS identity. The three host targets still require full deployment testing; local syntax/configuration checks do not establish production compatibility.

Plan for at least 4 GB RAM, 2 CPU cores and adequate disk space for your database, uploaded files and backups. More memory may be needed to build assets. A domain's A record must point to the server; if an AAAA record exists, IPv6 must reach it too. Allow incoming TCP 80/443 (and optionally UDP 443 for Docker HTTP/3) plus your SSH port. The installer does not change firewall rules. Only the specified domain is configured; `www` is optional and is not required.

## Preinstalled Docker warning

Docker may already be installed when using either native or Docker mode. The installer displays a warning before proceeding, including during `--check`:

> WARNING: Docker is already installed on this server. You may continue, provided no other server/application stack is installed, no Docker containers exist, and the required ports are available. Preinstalled Docker is used AS IS. No support or guarantees are provided. If issues arise, you are on your own and assume all risks, liabilities, responsibilities and outcomes from continuing.

The warning allows installation to continue automatically when the checks pass. It does not override checks for other installed stacks, existing containers, previous tracker data or occupied ports. Native mode does not start or replace preinstalled Docker. In either mode, a preinstalled Docker daemon must be working so the installer can check for existing containers. Docker mode also requires the Compose v2 plugin to be available.

## Install

```bash
sudo apt-get update
sudo apt-get install -y git
git clone https://github.com/MauveAgent/Unit3D-Community-Installer.git installer
cd installer
```

Run all installation commands from the `installer` directory created above.

### Native

```bash
sudo ./install.sh native --check
sudo ./install.sh native
```

You will be prompted for the domain and owner email. For unattended configuration:

```bash
sudo env DOMAIN=tracker.example.com OWNER_EMAIL=you@example.com OWNER_NAME=Owner ./install.sh native
```

The script installs PHP 8.4 (Debian 13 / Ubuntu 24.04) or PHP 8.5 (Ubuntu 26.04), MySQL 8.4 LTS, Redis, Meilisearch 1.15.2, Nginx, Certbot, Supervisor, Node.js and Bun 1.3.0. Debian 13 and Ubuntu 26.04 use distro PHP packages; Ubuntu 24.04 uses Ondřej Surý's PHP PPA. MySQL comes from Oracle's signed APT repository. Upstream's Composer and Bun lock files are respected; application Composer development dependencies are excluded.

Application: `/var/www/unit3d`. Generated owner credentials: `/etc/unit3d/credentials.txt` (root-only). MySQL, Redis, search and chat listen on loopback. Nginx terminates HTTPS and proxies chat through the same domain. The scheduler runs once per minute using a systemd timer. Two queue workers and the chat server are supervised. Application code is owned by root; only storage and bootstrap/cache are writable by the web user.

In the native maintenance commands below, replace `php8.4` with `php8.5` on Ubuntu 26.04.

Inspect services:

```bash
sudo supervisorctl status
sudo systemctl status unit3d-search unit3d-schedule.timer php8.4-fpm mysql
sudo journalctl -u unit3d-search -u unit3d-schedule.service
```

### Docker

```bash
sudo ./install.sh docker --check
sudo ./install.sh docker
```

Or supply the same DOMAIN/OWNER_EMAIL/OWNER_NAME variables as native mode. Docker Engine and the Compose v2 plugin are installed from Docker's signed repository if Docker is absent. An existing Docker daemon must be working and have no containers, including stopped containers. No host PHP, MySQL, Redis or Nginx installation is needed.

Deployment: `/opt/unit3d`. Generated owner credentials: `/opt/unit3d/credentials.txt` (root-only). PHP-FPM, Nginx, queues, scheduler, chat, MySQL, Redis and search run in separate containers. Caddy handles HTTPS and certificate renewal. Only Caddy publishes ports. Named volumes persist database, uploads, Redis, search indexes and certificate data. The application image contains the code and built assets; secrets are excluded from its build context.

```bash
cd /opt/unit3d
sudo docker compose ps
sudo docker compose logs --tail=100 app queue scheduler echo meilisearch
sudo docker compose stop
sudo docker compose up -d
```

Do not use `docker compose down -v`: it deletes persistent data. Initialization explicitly refuses an existing database or previous initialization marker. Normal restarts do not seed the database or regenerate APP_KEY. Do not rerun the bootstrap over a previous installation.

## Optional Rust tracker: UNIT3D-Announce

Both deployment modes can install and configure [UNIT3D-Announce](https://github.com/Roardom/UNIT3D-Announce) instead of UNIT3D's built-in PHP announce handler. Interactive installation asks whether to include it; the default is **No**. For unattended installation, set `INSTALL_ANNOUNCE=true`:

```bash
# Native installation with the Rust tracker
sudo env DOMAIN=tracker.example.com OWNER_EMAIL=you@example.com INSTALL_ANNOUNCE=true ./install.sh native

# Docker installation with the Rust tracker
sudo env DOMAIN=tracker.example.com OWNER_EMAIL=you@example.com INSTALL_ANNOUNCE=true ./install.sh docker
```

Set `INSTALL_ANNOUNCE=false` to skip it explicitly. This option is for fresh installations; it does not convert an existing deployment.

The installer pins UNIT3D-Announce **v0.3.1** to commit `fcd189e9aebf07a12a1f8cc39500819c3870925b` and builds it with Rust 1.93.1 using its Cargo lock file and offline SQLx metadata. The reviewed combination is UNIT3D v9.2.0; overriding UNIT3D_REF while selecting the Rust tracker is rejected. Building Rust adds installation time and memory/disk requirements.

The installer generates a shared API key, configures the existing UNIT3D MySQL database connection, and enables the external tracker through `TRACKER_ENABLED`, `TRACKER_HOST`, `TRACKER_PORT` and `TRACKER_KEY`. Database seeding runs with the external tracker disabled; the Rust service starts after initialization. Public announce URLs stay on the same HTTPS domain. Only peer announce routes are exposed; management endpoints and health checks stay private. The reverse proxy supplies the client IP and replaces incoming `X-Real-IP` headers.

### Native Rust tracker

Source and configuration: `/opt/unit3d-announce`. Binary: `/usr/local/bin/unit3d-announce`. An isolated Rust toolchain lives in `/opt/unit3d-rust`. The service runs as a dedicated unprivileged user, listens on `127.0.0.1:6969`, and is managed by systemd.

```bash
sudo systemctl status unit3d-announce
sudo journalctl -u unit3d-announce --tail=100
curl -fsS http://127.0.0.1:6969/announce/health/ping
sudoedit /opt/unit3d-announce/.env
sudo systemctl restart unit3d-announce
```

### Docker Rust tracker

Source and configuration: `/opt/unit3d/announce`. The optional `announce` Compose profile is enabled in `/opt/unit3d/.env`. The tracker runs in its own container as an unprivileged user and does not publish port 6969 to the host. Its `.env` is mounted read-only and excluded from the image build. Stop operations allow 120 seconds for graceful database flushing.

```bash
cd /opt/unit3d
sudo docker compose ps announce
sudo docker compose logs --tail=100 announce
sudo docker compose exec -T announce curl -fsS http://127.0.0.1:6969/announce/health/ping
sudoedit announce/.env
sudo docker compose restart announce
```

When enabling global freeleech or double-upload events, configure **both** UNIT3D's event settings and the Rust tracker's `DOWNLOAD_FACTOR` / `UPLOAD_FACTOR`. Defaults are 100/100; freeleech uses `DOWNLOAD_FACTOR=0`, and double upload uses `UPLOAD_FACTOR=200`. Restart the Rust service after changes. Events configured only in the website do not automatically change Rust tracker accounting.

The same **AS IS, no support, no warranties or guarantees, and use-at-your-own-risk** terms apply to this optional component and its installation. Do not ask UNIT3D, HDInnovations or UNIT3D-Announce developers for help with this unofficial installer or problems it causes.

## After installation

1. Read the generated credentials file with `sudo cat`, sign in, change the generated owner password and enable 2FA.
2. Configure real SMTP in the application's `.env`; the default `MAIL_MAILER=log` does **not** deliver email. Set MAIL_FROM_ADDRESS/MAIL_FROM_NAME and required provider settings. Add your TMDB/Twitch credentials if those features are used.
3. Review UNIT3D settings, registration policy and tracker rules, and test an actual torrent announce, search, chat, queues and email before inviting users.
4. Back up the database, `.env` (including APP_KEY), uploaded files and configuration before any upgrades. Store backups off-server and test recovery.

For native config changes:

```bash
cd /var/www/unit3d
sudoedit .env
sudo -u www-data php8.4 artisan config:cache
sudo supervisorctl restart 'unit3d-queue:*' unit3d-echo
```

For Docker config changes:

```bash
cd /opt/unit3d
sudoedit app/.env
sudo docker compose up -d --force-recreate app queue scheduler
```

Docker reads app configuration using `env_file`; containers must be recreated after edits. Do not run `config:cache` only in a temporary container: its filesystem is not shared with the application containers. When changing database/Redis/search credentials, update the service configuration and existing service credentials as well; changing initialization variables does not rotate an existing MySQL password.

VITE_ECHO_ADDRESS is built into frontend assets. A domain change requires an asset rebuild (native: rebuild with Bun; Docker: `docker compose build` after updating the domain and Caddyfile, then recreate services).

## Updates and recovery

This is an **installer**, not an in-place upgrade script. A failed install leaves files in place for diagnosis and refuses a blind rerun. For Docker, inspect `docker compose logs` and repair the failed step manually; never clear a database or remove volumes to bypass a safety check. If initialization fails, the `storage/.initializing` marker remains intentionally.

Keep the pinned release until a new release has been reviewed. `UNIT3D_REF` may be overridden with a tag for deliberate testing; other releases are not verified by this installer. For a native application upgrade, back up, stop workers, check out the chosen release, install locked dependencies, build assets, apply `artisan migrate --force` **without `--seed`**, refresh caches and restore permissions before restarting. For Docker, change the checkout in `/opt/unit3d/app`, rebuild images, run migrations with the new image, and recreate services. An upgrade procedure must account for release-specific changes; don't use the fresh-install initialization command for upgrades.

The previous PHP installer is retained in `src/` for historical reference and is no longer called by `install.sh` or `ubuntu.sh`. It has not been modernized; do not invoke `php artisan install` in this installer repository.

## Validation

```bash
python3 tests/test_modern_installer.py
for script in install.sh ubuntu.sh scripts/*.sh; do bash -n "$script"; done
shellcheck -x install.sh ubuntu.sh scripts/*.sh docker/*.sh
```

The included GitHub Actions workflow checks configuration generation and scripts, then builds and smoke-tests the Docker stack against an empty MySQL database. Native provisioning needs fresh VPS/VM testing on each host target; it cannot be safely verified by running installation on a shared development machine.
