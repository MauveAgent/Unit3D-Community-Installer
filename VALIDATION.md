# Validation record

Reviewed against UNIT3D v9.2.0, commit 8b88f4c8182eb3d3912ffef425c3224dcfd596f4, on 2026-10-01.

Passed locally:

- ShellCheck 0.11.0 on new shell entry points, provisioning scripts and container scripts.
- Bash/sh syntax checks.
- Caddy 2.10.2 parsed both proxy configurations, including the peer-only announce route and management API guard.
- UNIT3D-Announce v0.3.1 compiled successfully with Rust 1.93.1, `--release --locked --jobs 2`, `SQLX_OFFLINE=true` and portable x86-64 CPU flags.
- Eight Python regression tests, including seven OS acceptance/rejection cases and native/Docker optional announce configuration.
- Docker Compose v2.39.4 configuration parsing with generated test configuration, with and without the announce profile.
- Confirmed the official MySQL repository publishes Debian trixie and Ubuntu resolute metadata; inspected the Debian MySQL 8.4 package index.

Not run locally:

- Native installation on Debian 13, Ubuntu 24.04 or Ubuntu 26.04 fresh VMs.
- Docker image builds or a live container deployment.
- Live certificate issuance, SMTP delivery or BitTorrent client announces.

This execution environment cannot provision system services or run a Docker daemon. A GitHub Actions Docker build/smoke-test workflow is included but has not been executed here. Until those tests and fresh-VM deployments pass, treat the changes as an implementation candidate requiring deployment validation, not a verified production release.

Optional UNIT3D-Announce was reviewed against v0.3.1, commit fcd189e9aebf07a12a1f8cc39500819c3870925b. The added CI matrix covers both built-in and Rust announce installations, private health checks, public peer routing and management API isolation. Tracker startup against MySQL and real client announces have not been run in this environment. The Rust release build passed locally.

Preinstalled Docker is accepted with a visible warning in both modes. Regression tests cover empty Docker installations, existing containers, unavailable daemons, container inspection failures and rejection of a stopped but installed Redis stack.

Regenerated against MauveAgent/Unit3D-Community-Installer at base commit a2b9cfa0e3ac8ef4af3c9fa5c72a81c55f815b5f. Installer clone instructions and help identify https://github.com/MauveAgent/Unit3D-Community-Installer.git; application and announce source URLs remain their respective upstream repositories.
