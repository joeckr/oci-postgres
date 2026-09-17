# oci-postgres

An OpenShift-compliant, rootless PostgreSQL container image and Helm chart designed to run under arbitrary user IDs (UIDs) in restricted security contexts such as OpenShift Security Context Constraints (SCC) and Kubernetes.

Built on top of official Alpine PostgreSQL images, this repository provides automated multi-version matrix builds, rootless permission handling, and first-class Helm support.

---

## Features

- **OpenShift & Rootless Kubernetes Ready**: Runs seamlessly under arbitrary non-root user IDs by configuring group 0 (`root` group) permissions (`chmod -R g+rwX`).
- **Restricted SCC Compatible**: Defaults `PGDATA` to `/tmp/data` and mounts persistent storage to `/tmp`, avoiding elevated privilege requirements.
- **Multi-Version Matrix**: Dynamically builds and publishes images for multiple active PostgreSQL major versions via GitHub Actions.
- **Schema Initialization**: Automated database seeding on first startup by mounting custom `.sql` or `.sh` scripts into `/docker-entrypoint-initdb.d/`.
- **Helm Chart Included**: Ready-to-deploy chart located in [`chart/`](chart/) with configurable Persistent Volume Claims (PVC) and ConfigMap-based schema initialization.
- **Published Artifacts**: Container images and Helm charts published directly to GitHub Container Registry (GHCR).

---

## Supported Versions

Images are built from official Alpine base images as defined in [`versions.json`](versions.json):

| PostgreSQL Version | Upstream Version | Image Tags |
| :--- | :--- | :--- |
| **18** (Default / Latest) | `18.4` | `ghcr.io/joeckr/postgres:18`, `ghcr.io/joeckr/postgres:latest` |
| **17** | `17.10` | `ghcr.io/joeckr/postgres:17` |
| **16** | `16.14` | `ghcr.io/joeckr/postgres:16` |
| **15** | `15.18` | `ghcr.io/joeckr/postgres:15` |
| **14** | `14.23` | `ghcr.io/joeckr/postgres:14` |

---

## Quick Start

### Docker Run

```bash
docker run -d \
  --name postgres \
  -p 5432:5432 \
  -e POSTGRES_USER=postgres \
  -e POSTGRES_PASSWORD=mysecretpassword \
  -e POSTGRES_DB=postgres \
  -v pgdata:/tmp \
  ghcr.io/joeckr/postgres:latest
```

> **Note**: Mount persistent storage to `/tmp` because `PGDATA` defaults to `/tmp/data`.

### Docker Compose

A local [`docker-compose.yml`](docker-compose.yml) is included for testing:

```bash
docker compose up -d
```

To initialize your own custom schema on first run, mount your SQL script into `/docker-entrypoint-initdb.d/`:

```yaml
volumes:
  - pgdata:/tmp
  - ./schema.sql:/docker-entrypoint-initdb.d/schema.sql:z
```

---

## Helm Chart

A Helm chart is available in the [`chart/`](chart/) directory and is published as an OCI artifact to GHCR.

### Configuration (`values.yaml`)

| Parameter | Description | Default |
| :--- | :--- | :--- |
| `postgres.name` | Deployment and service name | `postgres` |
| `postgres.app` | Application label | `postgres` |
| `postgres.replicaCount` | Number of replicas | `1` |
| `postgres.resources` | Resource requests and limits | `{ limits: { cpu: 100m, memory: 200Mi } }` |
| `postgres.image` | Container image repository | `ghcr.io/joeckr/postgres` |
| `postgres.tag` | Image tag | `latest` |
| `postgres.pullPolicy` | Image pull policy | `Always` |
| `postgres.port` | PostgreSQL service port | `5432` |
| `postgres.user` | PostgreSQL superuser username | `postgres` |
| `postgres.password` | PostgreSQL superuser password | `changeme` |
| `postgres.db` | Default database name | `postgres` |
| `postgres.storageSize` | Persistent volume claim size | `1Gi` |
| `postgres.storageAccessMode` | PVC access mode | `ReadWriteOnce` |
| `postgres.storageClass` | Storage class name (empty uses default) | `""` |
| `initSchema.enabled` | Enable ConfigMap-based schema initialization | `true` |

### Installing the Chart

From the repository root:

```bash
helm upgrade --install postgres ./chart \
  --set postgres.password="your-secure-password" # betterleaks:allow
```

---

## Why `/tmp/data`?

Standard PostgreSQL container images set `PGDATA` to `/var/lib/postgresql/data`, which is owned by UID 999 (`postgres`). When running in OpenShift or hardened Kubernetes clusters:
- Containers are assigned arbitrary, non-zero user IDs.
- These arbitrary UIDs belong to group 0 (`root` group).

This image configures:
- `PGDATA=/tmp/data`
- Group 0 write permissions across `/tmp` and `/var/run/postgresql`

This ensures any assigned user ID within GID 0 can create the data directory, manage Unix sockets in `/var/run/postgresql`, and run PostgreSQL cleanly without requiring root access.

---

## Local Development & Contributing

This project uses [`mise`](https://mise.jdx.dev/) for tool management and [`hk`](https://github.com/jdx/hk) for pre-commit checks and code quality hooks.

### Setup

```bash
# Install tools and git hooks
mise run install
```

### Available Tasks

| Command | Description |
| :--- | :--- |
| `mise run hk` *(or `check`)* | Run git hooks and linters (`betterleaks`, `actionlint`, `zizmor`, `hadolint`, `shellcheck`, `yamllint`, `helm lint`, `tombi`, `pkl`, etc.) |
| `mise run build` | Build container image locally using Docker Buildx |
| `mise run compose` | Start local development environment via Docker Compose |
| `mise run trivy-fs` | Scan repository files for vulnerabilities with Trivy |
| `mise run trivy-image` | Build and scan container image with Trivy |

---

## Support

If you find this project useful, consider supporting my work on [Ko-fi](https://ko-fi.com/joeckr):

[![ko-fi](https://ko-fi.com/img/githubbutton_sm.svg)](https://ko-fi.com/joeckr)

## License

Please refer to the `LICENSE` file for details.
