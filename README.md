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

## Local Environment & Podman Setup

To ensure containerized applications and Helm charts tested locally run cleanly when deployed to OpenShift or Kubernetes, this repository is designed to be used alongside the Podman configuration in [joeckr/dotfiles](https://github.com/joeckr/dotfiles).

The dotfiles repository provides a centralized [`containers.conf`](https://github.com/joeckr/dotfiles/blob/main/containers/containers.conf) (deployed to `~/.config/containers/containers.conf`) that configures Podman to simulate OpenShift's default **`restricted-v2` Security Context Constraints (SCC)**:

| OpenShift SCC Rule | Podman Configuration | Description |
|---|---|---|
| **Random UID (`MustRunAsRange`)** | `userns = "auto"` | Allocates dynamic subordinate UID/GID ranges from `/etc/subuid` and `/etc/subgid`. Containers run unprivileged without mapping host root. |
| **Drop Capabilities** | `default_capabilities = ["NET_BIND_SERVICE"]` | Drops standard root capabilities (`CHOWN`, `DAC_OVERRIDE`, `FOWNER`, `SETUID`, `SETGID`, `SYS_CHROOT`, etc.) and permits only `NET_BIND_SERVICE`. |
| **Disallow Privileged** | `privileged = false` | Disallows privileged container execution by default. |
| **Seccomp Profile** | `seccomp_profile = "/usr/share/containers/seccomp.json"` | Enforces the runtime default seccomp profile (`RuntimeDefault`). |
| **Namespace Isolation** | `cgroupns`, `ipcns`, `pidns`, `utsns = "private"` | Enforces private container namespaces (host namespaces are forbidden in restricted SCC). |

### macOS Podman Machine Integration

On macOS, the dotfiles installer script (`brew/podman.sh`) automates the machine lifecycle:

1. Deploys `containers/containers.conf` to `~/.config/containers/containers.conf` on the host.
2. Initializing `podman machine init` automatically mounts `~/.config/containers` into `/etc/containers` inside the Fedora CoreOS VM.
3. Automatically symlinks `/etc/containers/containers.conf` to the VM user's config (`~core/.config/containers/containers.conf`) and restarts the Podman API service so all container executions immediately enforce these constraints.

## Testing with Podman Compose

Two Compose configurations are provided to facilitate testing, benchmarking, and debugging:

### 1. Upstream Baseline (`compose.upstream.yml`)

The [`compose.upstream.yml`](compose.upstream.yml) file runs the original, unmodified upstream container image (`postgres:18-alpine`):

```sh
# Start upstream container
podman compose -f compose.upstream.yml up -d
```

**Why test upstream?**
Running the unmodified image against your SCC-compliant Podman setup simulates deploying standard public images directly into OpenShift. This will typically surface common failures:
- Standard upstream PostgreSQL images set `PGDATA` to `/var/lib/postgresql/data` (owned by UID 999 `postgres`), failing when OpenShift assigns arbitrary non-zero UIDs.
- Inability to write or create Unix sockets in `/var/run/postgresql` without group 0 permissions.
- Inability to perform privileged `chown` operations due to dropped capabilities.

### 2. Modified Image (`compose.yml`)

The [`compose.yml`](compose.yml) file builds and runs the customized `Dockerfile` containing the adaptations required for OpenShift and rootless environments:

```sh
# Build and start the modified compliant container
podman compose up -d --build

# Or via mise
mise run compose
```

This verified configuration applies:
- Group 0 (`root` group) write permissions across `/tmp` and `/var/run/postgresql`.
- Sets `PGDATA=/tmp/data` and mounts persistent storage to `/tmp`.
- Automatic schema initialization by mounting custom `.sql` scripts into `/docker-entrypoint-initdb.d/schema.sql:z`.

**Default Credentials:**
- **Port:** `5432`
- **Database:** `postgres`
- **User:** `postgres`
- **Password:** `mysecretpassword`

### Stopping Containers

```sh
# Stop modified compose stack
podman compose down
# or: mise run down

# Stop upstream compose stack
podman compose -f compose.upstream.yml down

# View logs
podman compose logs -f
# or: mise run logs
```

### Local Helm Testing (Podman Play Kube)

Test rendered Helm chart manifests directly in Podman without requiring a remote cluster:

```sh
# Render Helm template and run pods locally via podman play kube
mise run play

# Stop and tear down local pods
mise run downplay
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
| `mise run install` | Install tools and git hooks (`hk install --mise`) |
| `mise run hk` *(or `check`)* | Run git hooks and linters (`betterleaks`, `actionlint`, `zizmor`, `hadolint`, `shellcheck`, `yamllint`, `helm lint`, `tombi`, `pkl`, etc.) |
| `mise run compose` | Start local development environment via Podman Compose (`podman compose up -d --build`) |
| `mise run down` | Stop local Podman Compose stack (`podman compose down`) |
| `mise run logs` | View Podman Compose logs (`podman compose logs -f`) |
| `mise run play` | Test Helm chart manifests locally with Podman Play Kube (`podman play kube rendered.yaml`) |
| `mise run downplay` | Stop and tear down Podman Play Kube pods (`podman play kube rendered.yaml --down`) |
| `mise run helm-lint` | Lint the Helm chart (`helm lint chart/`) |
| `mise run helm-template` | Render Helm chart templates to `rendered.yaml` (`helm template test chart/ > rendered.yaml`) |
| `mise run helm-dep` | Build Helm chart dependencies (`helm dependency build chart/`) |
| `mise run build` | Build container image locally using Podman Buildx |
| `mise run trivy-fs` | Scan repository files for vulnerabilities with Trivy |
| `mise run trivy-image` | Build and scan container image with Trivy |

---

## Support

If you find this project useful, consider supporting my work on [Ko-fi](https://ko-fi.com/joeckr):

[![ko-fi](https://ko-fi.com/img/githubbutton_sm.svg)](https://ko-fi.com/joeckr)

## License

Please refer to the `LICENSE` file for details.
