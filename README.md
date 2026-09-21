# oci-postgres

An OpenShift-compliant, rootless PostgreSQL container image and Helm chart designed to run under arbitrary user IDs (UIDs) in restricted security contexts such as OpenShift Security Context Constraints (SCC) and Kubernetes.

Built on top of official Alpine PostgreSQL images, this repository provides automated multi-version matrix builds, rootless permission handling, and first-class Helm support.

---

## Features

- **Rootless Image Builds**: Engineered to build cleanly in unprivileged, rootless container builders without requiring host root or privileged daemon sockets.
- **OpenShift & Rootless Kubernetes Ready**: Runs seamlessly under arbitrary non-root user IDs by configuring group 0 (`root` group) permissions (`chmod -R g+rwX`).
- **Talos Linux Compatibility**: Fully compliant with upstream Kubernetes Pod Security Standards (`restricted` PSS/PSA level) suited for Talos Linux's immutable, hardened architecture.
- **Restricted SCC Compatible**: Defaults `PGDATA` to `/tmp/data` and mounts persistent storage to `/tmp`, avoiding elevated privilege requirements.
- **Multi-Version Matrix**: Dynamically builds and publishes images for multiple active PostgreSQL major versions via GitHub Actions.
- **Schema Initialization**: Automated database seeding on first startup by mounting custom `.sql` or `.sh` scripts into `/docker-entrypoint-initdb.d/`.
- **Helm Chart Included**: Ready-to-deploy chart located in [`chart/`](chart/) with configurable Persistent Volume Claims (PVC) and ConfigMap-based schema initialization.
- **Multi-Tier Testing Pipeline**: Integrated with `mise` for a 4-tier testing workflow spanning upstream comparison, local container validation, local Kubernetes manifest testing, and live Talos cluster deployment.
- **Published Artifacts**: Container images and Helm charts published directly to GitHub Container Registry (GHCR).

---

## Supported Versions

Images are built from official Alpine base images as defined in [`versions.json`](versions.json):

| PostgreSQL Version | Upstream Version | Image Tags |
| :--- | :--- | :--- |
| **18** (Default / Latest) | `18.6` | `ghcr.io/joeckr/postgres:18`, `ghcr.io/joeckr/postgres:latest` |
| **17** | `17.11` | `ghcr.io/joeckr/postgres:17` |
| **16** | `16.15` | `ghcr.io/joeckr/postgres:16` |
| **15** | `15.19` | `ghcr.io/joeckr/postgres:15` |
| **14** | `14.24` | `ghcr.io/joeckr/postgres:14` |

---

## Security & Compliance Architecture

Both OpenShift and Talos Linux prioritize workload security and least privilege, but they enforce and evaluate constraints through different mechanisms. This repository is architected to satisfy both environments without code changes.

### OpenShift Compliance (`restricted-v2` SCC)

OpenShift uses **Security Context Constraints (SCC)** to control pod permissions. Under the default `restricted-v2` SCC:
- **Arbitrary Dynamic UIDs**: OpenShift assigns a random UID from a dedicated per-namespace range (e.g., `1000670000`). Containers cannot assume a fixed UID like `1000`.
- **Root Group (GID 0)**: Files and directories required at runtime (`/tmp`, `/tmp/data`, `/var/run/postgresql`, `/docker-entrypoint-initdb.d`) are owned by group 0 (`chgrp -R 0`) with group read/write permissions (`chmod -R g+rwX`) so the dynamically assigned UID can access them.
- **Dropped Capabilities**: Drops standard root capabilities (`CHOWN`, `DAC_OVERRIDE`, `FOWNER`, `SETUID`, `SETGID`, `SYS_CHROOT`, etc.) and permits only unprivileged operations (and `NET_BIND_SERVICE` when needed).
- **Unprivileged Ports**: Listens on standard port `5432` without requiring elevated privileges.

### Talos Linux Compliance (Kubernetes PSS `restricted`)

Talos Linux is an immutable, minimal, secure-by-default Kubernetes operating system with no SSH, no interactive shell, and an immutable root filesystem. In Talos clusters:
- **Pod Security Standards (PSS)**: Workload namespaces enforce the Kubernetes **Pod Security Admission (PSA)** `restricted` profile.
- **Must Run As Non-Root**: The pod specification must set `securityContext.runAsNonRoot: true`. Containers cannot execute as UID 0.
- **Drop All Capabilities**: The container specification explicitly drops all Linux capabilities (`capabilities: drop: ["ALL"]`).
- **Disallow Privilege Escalation**: Sets `securityContext.allowPrivilegeEscalation: false` to prevent child processes from acquiring more privileges than the parent.
- **Seccomp Profile**: Pods enforce `seccompProfile: { type: RuntimeDefault }`.
- **Credential Protection**: Best practice sets `automountServiceAccountToken: false` to avoid leaking Kubernetes API tokens to database containers.
- **Persistent Storage**: Integrates with CSI storage providers (e.g., Local Path Provisioner, OpenEBS Mayastor, Rook-Ceph) via configurable PVC StorageClass.

### Rootless Build Environment Compliance

Building container images inside secure or unprivileged environments (such as rootless Podman/Buildah on developer workstations, or unprivileged Kubernetes CI runners like Tekton or Kaniko) requires that the build process itself does not rely on host `root` privileges or the legacy root-owned Docker daemon socket (`/var/run/docker.sock`).

This repository's `Dockerfile` is engineered for complete rootless build support:
- **No Host Root Required**: Builds execute and succeed cleanly under unprivileged user namespaces without needing `sudo` or privileged container builders.
- **User Namespace Friendly Permissions**: Layer modifications rely on `chgrp -R 0` and group-based permissions (`g+rwX`), which map cleanly into subordinate UID/GID allocations (`/etc/subuid` and `/etc/subgid`) without failing on host-restricted `chown` operations.
- **Unprivileged Local Build**: Run `mise run build` (`podman buildx build --platform linux/amd64 -t ghcr.io/joeckr/postgres:test . --load`) or `mise run compose` to build locally without root escalation.

### Compliance Matrix

| Security Dimension | OpenShift (`restricted-v2` SCC) | Talos Linux (Kubernetes PSS `restricted`) | Implementation in This Repo |
|---|---|---|---|
| **Build Execution** | Rootless builder compatible | Rootless builder compatible | Builds unprivileged via rootless Podman/Buildah (`mise run build`) |
| **User ID** | Dynamic arbitrary UID (`MustRunAsRange`) | Non-root UID (`runAsNonRoot: true`) | `USER 1031` in Dockerfile + `runAsNonRoot: true` in Helm |
| **Group Permissions** | Requires GID 0 (`root`) with `g+rwX` | Compatible with GID 0 / unprivileged groups | `chgrp -R 0` & `chmod -R g+rwX` on runtime paths (`/tmp`) |
| **Capabilities** | Drops root caps; allows `NET_BIND_SERVICE` | Must drop `ALL` capabilities | `capabilities.drop: ["ALL"]` in Helm chart |
| **Privilege Escalation** | Prohibited | `allowPrivilegeEscalation: false` | Configured in Helm `securityContext` |
| **Seccomp Profile** | `RuntimeDefault` | `RuntimeDefault` or `Localhost` | `seccompProfile: { type: RuntimeDefault }` |
| **Service Account Token** | Optional | Recommended disabled | Hardened in pod configuration |
| **Port Binding** | Unprivileged (> 1024) | Unprivileged (> 1024) | Listens on port `5432` |
| **Storage Layer** | OpenShift StorageClass | Talos CSI StorageClass | Standard PVC template with configurable `storageClass` |

---

## Local Environment & Podman Setup

To ensure containerized applications and Helm charts tested locally run cleanly when deployed to OpenShift or Talos Linux, this repository is designed to be used alongside the Podman configuration in [joeckr/dotfiles](https://github.com/joeckr/dotfiles).

The dotfiles repository provides a centralized [`containers.conf`](https://github.com/joeckr/dotfiles/blob/main/containers/containers.conf) (deployed to `~/.config/containers/containers.conf`) that configures Podman to simulate OpenShift and Talos Linux runtime restrictions:

| Security Rule | Podman Configuration | Description |
|---|---|---|
| **Random UID (`MustRunAsRange`)** | `userns = "auto"` | Allocates dynamic subordinate UID/GID ranges from `/etc/subuid` and `/etc/subgid`. Containers run unprivileged without mapping host root. |
| **Drop Capabilities** | `default_capabilities = ["NET_BIND_SERVICE"]` | Drops standard root capabilities (`CHOWN`, `DAC_OVERRIDE`, `FOWNER`, `SETUID`, `SETGID`, `SYS_CHROOT`, etc.) and permits only `NET_BIND_SERVICE`. |
| **Disallow Privileged** | `privileged = false` | Disallows privileged container execution by default. |
| **Seccomp Profile** | `seccomp_profile = "/usr/share/containers/seccomp.json"` | Enforces the runtime default seccomp profile (`RuntimeDefault`). |
| **Namespace Isolation** | `cgroupns`, `ipcns`, `pidns`, `utsns = "private"` | Enforces private container namespaces (host namespaces are forbidden in restricted profiles). |

### macOS Podman Machine Integration

On macOS, the dotfiles installer script (`brew/podman.sh`) automates the machine lifecycle:

1. Deploys `containers/containers.conf` to `~/.config/containers/containers.conf` on the host.
2. Initializing `podman machine init` automatically mounts `~/.config/containers` into `/etc/containers` inside the Fedora CoreOS VM.
3. Automatically symlinks `/etc/containers/containers.conf` to the VM user's config (`~core/.config/containers/containers.conf`) and restarts the Podman API service so all container executions immediately enforce these constraints.

---

## Testing & Validation Process

This repository defines a 4-tier testing process to validate container security, manifest generation, and runtime compatibility from local development through to production cluster deployment.

```
┌─────────────────────────┐     ┌─────────────────────────┐     ┌─────────────────────────┐     ┌─────────────────────────┐
│ Tier 1: Upstream Test   │ ──> │ Tier 2: Modified Test   │ ──> │ Tier 3: Podman Play     │ ──> │ Tier 4: Talos Cluster   │
│ Surface root & cap gaps │     │ Verify non-root & fixes │     │ Validate K8s manifests  │     │ Live Helm verification  │
│ (compose.upstream.yml)  │     │ (compose.yml)           │     │ (podman play kube)      │     │ (helm install)          │
└─────────────────────────┘     └─────────────────────────┘     └─────────────────────────┘     └─────────────────────────┘
```

### Tier 1: Upstream Baseline Comparison (`compose.upstream.yml`)

The [`compose.upstream.yml`](compose.upstream.yml) configuration runs the original, unmodified upstream container image (`postgres:18-alpine`):

```sh
# Start upstream container
mise run compose-up
# or: podman compose -f compose.upstream.yml up -d

# Stop upstream container
mise run down-up
# or: podman compose -f compose.upstream.yml down
```

**Why test upstream?**
Running the unmodified image against your restricted Podman environment simulates deploying standard public images directly into OpenShift or Talos Linux. This will typically surface common failures:
- Standard upstream PostgreSQL images set `PGDATA` to `/var/lib/postgresql/data` (owned by UID 999 `postgres`), failing when OpenShift assigns arbitrary non-zero UIDs.
- Inability to write or create Unix sockets in `/var/run/postgresql` without group 0 permissions.
- Inability to perform privileged `chown` operations due to dropped capabilities.

---

### Tier 2: Modified Image Local Validation (`compose.yml`)

The [`compose.yml`](compose.yml) configuration builds and runs the customized `Dockerfile` containing the adaptations required for OpenShift and Talos Linux:

```sh
# Build and start the modified compliant container
mise run compose
# or: podman compose up -d --build

# View container logs
mise run logs
# or: podman compose logs -f

# Stop modified stack
mise run down
# or: podman compose down
```

**What this verifies:**
- Rootless image build and layer assembly without host root privileges.
- Group 0 (`root` group) write permissions across `/tmp` and `/var/run/postgresql`.
- Sets `PGDATA=/tmp/data` and mounts persistent storage to `/tmp`.
- Automatic schema initialization by mounting custom `.sql` scripts into `/docker-entrypoint-initdb.d/schema.sql:z`.

**Default Credentials:**
- **Port:** `5432`
- **Database:** `postgres`
- **User:** `postgres`
- **Password:** `mysecretpassword`

---

### Tier 3: Local Kubernetes Manifest Testing (`mise run play`)

Before deploying to an actual Kubernetes cluster, you can test the rendered Kubernetes manifests locally using Podman's built-in `play kube` feature.

```sh
# Render templates and play Kubernetes manifests locally
mise run play

# Teardown the played pod and resources
mise run downplay
```

**How `mise run play` works:**
1. Triggers the dependent task `mise run helm-template`, which executes:
   ```sh
   helm dependency build chart/
   helm template test chart/ > rendered.yaml
   ```
2. Executes `podman play kube rendered.yaml`, which:
   - Reads the multi-document Kubernetes YAML (`ConfigMap`, `PersistentVolumeClaim`, `Service`, `Deployment`).
   - Creates a local Podman pod matching the Kubernetes `Deployment` specification.
   - Applies the pod's `securityContext` (`runAsNonRoot: true`, capabilities drop, seccomp profile).
   - Mounts the persistent volume and ConfigMap into the container at `/tmp` and `/docker-entrypoint-initdb.d/`.
   - Exposes container port `5432`.

**Inspecting the local play deployment:**
```sh
# View running pods created by play kube
podman pod ps

# View container status within the pod
podman ps --filter "pod=postgres"

# Check container logs within the pod
podman logs -f postgres-pod-postgres
```

**Teardown:**
```sh
mise run downplay
# or: podman play kube rendered.yaml --down
```

---

### Tier 4: Cluster Deployment & Testing on Talos Linux (`mise run helm-install`)

The final phase validates the workload on a live **Talos Linux** Kubernetes cluster. This tests real-world Pod Security Admission (PSA) enforcement, CSI storage provisioning, network policies, and database startup.

#### 1. Cluster Prerequisites & Configuration

Ensure your `kubectl` context points to your Talos cluster:
```sh
kubectl config current-context
# Example: admin@my-talos-cluster
```

Ensure the container image is accessible to your Talos nodes (e.g., built and pushed to GitHub Container Registry `ghcr.io` or your local registry):
```sh
# Build image locally with target tag
mise run build
```

Configure `chart/values.yaml` for Talos Linux:
- **StorageClass**: If your Talos cluster uses a specific CSI storage provisioner (e.g., `local-path`, `mayastor`, `ceph-block`), configure `postgres.storageClass` in `values.yaml` or leave it empty `""` to use the cluster's default StorageClass.

#### 2. Linting & Template Validation

```sh
# Lint the chart for syntax and formatting errors
mise run helm-lint

# Inspect the rendered manifests before installation
mise run helm-template
cat rendered.yaml
```

#### 3. Deploying to the Talos Cluster

Install the Helm chart release:
```sh
mise run helm-install
# or: helm install test chart/
```

#### 4. Verifying Talos PSS Compliance & Health

Check the pod status and verify that Talos Linux Pod Security Admission (PSA) allowed the pod to run:

```sh
# Check pod deployment status
kubectl get pods -l app=postgres

# Inspect pod details and events for security policy rejections
kubectl describe pod -l app=postgres
```

> [!TIP]
> If your namespace enforces the `restricted` Pod Security Standard and there are non-compliant settings (such as missing `runAsNonRoot` or un-dropped capabilities), `kubectl describe pod` will show warning events from the `pod-security` admission controller.

Check the application logs:
```sh
kubectl logs -l app=postgres -f
```

Verify persistent storage and schema initialization inside the pod:
```sh
kubectl exec -it deployment/postgres -- ls -la /tmp/data
kubectl exec -it deployment/postgres -- psql -U postgres -d postgres -c "\dt"
```

Verify network access via port-forwarding:
```sh
kubectl port-forward svc/postgres 5432:5432
```

#### 5. Uninstalling from the Talos Cluster

When testing is complete, clean up the release:
```sh
mise run helm-uninstall
# or: helm uninstall test
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

Run tasks with `mise run <task>`:

| Task | Description | Command |
|---|---|---|
| `install` | Install tools and set up git hooks | `hk install --mise` |
| `hk` (or `check`) | Run all linters and hook checks | `hk check --all` |
| `compose` | Start local container stack with Podman Compose | `podman compose up -d --build` |
| `down` | Stop local Podman Compose stack | `podman compose down` |
| `compose-up` | Run unmodified upstream baseline container | `podman compose -f compose.upstream.yml up -d` |
| `down-up` | Stop upstream baseline container stack | `podman compose -f compose.upstream.yml down` |
| `logs` | View Podman Compose logs | `podman compose logs -f` |
| `play` | Test Helm chart manifests locally with Podman Play Kube | `podman play kube rendered.yaml` |
| `downplay` | Stop and remove Podman Play Kube pods | `podman play kube rendered.yaml --down` |
| `helm-dep` | Build Helm chart dependencies | `helm dependency build chart/` |
| `helm-lint` | Lint Helm chart | `helm lint chart/` |
| `helm-template` | Render Helm chart templates to `rendered.yaml` | `helm template test chart/ > rendered.yaml` |
| `helm-install` | Install Helm chart to current Kubernetes cluster | `helm install test chart/` |
| `helm-uninstall` | Uninstall Helm chart release from cluster | `helm uninstall test` |
| `build` | Build container image locally with Podman Buildx | `podman buildx build --platform linux/amd64 -t ghcr.io/joeckr/postgres:test . --load` |
| `trivy-fs` | Scan repository filesystem for security vulnerabilities | `trivy fs .` |
| `trivy-image` | Scan built container image with Trivy | `trivy image ghcr.io/joeckr/postgres:test` |


---

## Support

If you find this project useful, consider supporting my work on [Ko-fi](https://ko-fi.com/joeckr):

[![ko-fi](https://ko-fi.com/img/githubbutton_sm.svg)](https://ko-fi.com/joeckr)

## License

Please refer to the `LICENSE` file for details.
