# Manual desktop runner

This guide applies to Perlmutter as of November 2026. Run shell commands from the repository root after cloning it.

## Quickstart: Manual noVNC Container

You can also run a desktop container directly from a terminal without installing
or selecting a Jupyter kernel.

1. In a Perlmutter JupyterLab terminal, clone the public repo:

```sh
cd "${HOME}"
git clone https://github.com/nersc/perlmutter-desktop-containers.git
cd perlmutter-desktop-containers
```

This path uses the default Debian 12 fvwm3 image. Other image tags are listed
in the [image variant table](images.md#image-variants).

2. Load the NERSC Python module. If you have NERSC Registry access, run
   `podman-hpc login registry.nersc.gov` to use the cache. Then run the helper
   with the cached image reference; it retries GHCR directly if the cache pull
   fails:

```sh
module load python
python3 -m vnc_novnc.runner \
  --config scripts/run-vnc-novnc.yaml \
  --image registry.nersc.gov/ghcr.io/nersc/perlmutter-desktop-containers:debian-12-main
```

The helper pulls the image if needed, starts it with `podman-hpc`, and prints a
Jupyter Server Proxy noVNC URL and a one-time VNC password. The manual runner
uses a loopback host TCP port for noVNC by default, and Jupyter Server Proxy
forwards the browser to that port. Open the printed URL and enter the password.
Jupyter IPC carries notebook kernel channels when using an installed kernel;
the manual runner does not start a notebook kernel.

Example output:

```text
Image: registry.nersc.gov/ghcr.io/nersc/perlmutter-desktop-containers:debian-12-main
noVNC: https://jupyter.nersc.gov/user/your-user-name/your-server-name/proxy/49967/vnc.html?port=443&host=jupyter.nersc.gov&path=user%2Fyour-user-name%2Fyour-server-name%2Fproxy%2F49967%2Fwebsockify
One-time VNC password: AbC123xY
VNC server port is not exposed on the host.
```

Leave the command running while you use the desktop. Press `Ctrl-C` in the
terminal to stop the noVNC container. The raw VNC port is not exposed unless you
explicitly add `--expose-vnc`.

For a multi-user node, Unix-socket noVNC avoids even the loopback host TCP
listener and limits access to the user-private socket. To use it with the
manual runner, configure the named Jupyter Server Proxy service once, restart
JupyterLab, then add `--novnc-transport unix` to the command above:

```sh
scripts/install-jupyter-kernel.sh --jupyter-proxy-only
# Restart JupyterLab before running the next command.
cd "${HOME}/perlmutter-desktop-containers"
module load python
python3 -m vnc_novnc.runner \
  --config scripts/run-vnc-novnc.yaml \
  --image registry.nersc.gov/ghcr.io/nersc/perlmutter-desktop-containers:debian-12-main \
  --novnc-transport unix
```

## Run A Desktop

The preferred runner is the Python helper:

```sh
python3 -m vnc_novnc.runner \
  --config scripts/run-vnc-novnc.yaml \
  --image registry.nersc.gov/ghcr.io/nersc/perlmutter-desktop-containers:debian-12-main
```

Run module commands in this guide from the repository root. This lets Python
import the checkout without setting `PYTHONPATH` for the `podman-hpc`
subprocess.

It starts the image with `podman-hpc`, generates a one-time VNC password, stores
the password in a temporary `0600` file, binds the noVNC host port to
`127.0.0.1` by default, and prints the noVNC URL. It also generates a Jupyter
Server Proxy URL when it can determine the Jupyter user/server prefix.

The legacy shell helper can also use the cached image:

```sh
IMAGE=registry.nersc.gov/ghcr.io/nersc/perlmutter-desktop-containers:debian-12-main \
  scripts/run-vnc-novnc.sh
```

The Python helper is more complete: it supports YAML defaults, image
preparation, bind mounts, environment passthrough, user namespace handling, and
extra `podman-hpc` arguments.

Example output:

```text
Image: registry.nersc.gov/ghcr.io/nersc/perlmutter-desktop-containers:debian-12-main
noVNC: https://jupyter.nersc.gov/user/your-user-name/your-server-name/proxy/49967/vnc.html?port=443&host=jupyter.nersc.gov&path=user%2Fyour-user-name%2Fyour-server-name%2Fproxy%2F49967%2Fwebsockify
One-time VNC password: AbC123xY
VNC server port is not exposed on the host.
```

Open the printed noVNC URL and enter the printed one-time VNC password.

## Runner Configuration

The included `scripts/run-vnc-novnc.yaml` uses `--userns=keep-id`,
`--group-add=keep-groups`, and bind mounts the NERSC global filesystem,
`$SCRATCH`, `$CFS`, `/opt`, the host Cray PE config, the host cluster name,
and the host `/etc/environment`. Environment variables in YAML strings are
expanded on the host when the script starts.

YAML keys use long option names with underscores instead of dashes:

```yaml
userns: keep-id
keep_groups: true
pull_policy: missing
display_mode: default
gpu: false

volume:
  - "/global:/global"
  - "${SCRATCH}:${SCRATCH}:rw"
  - "${CFS}:${CFS}:rw"
  - "/opt:/opt"
  - "/etc/cray-pe.d:/etc/cray-pe.d:ro"
  - "/etc/clustername:/etc/clustername:ro"
  - "/etc/environment:/etc/environment:ro"

env:
  - "HOME"
  - "MODULEPATH"
  - "MODULEPATH_ROOT"
  - "MODULESHOME"
  - "PE_ENV"
  - "LMOD_FAMILY_MPI"
  - "LMOD_FAMILY_CUDATOOLKIT"
  - "LMOD_FAMILY_CUDATOOLKIT_VERSION"
```

Precedence is: built-in defaults, YAML config, environment variables, then
command-line arguments. Repeated list options such as `volume`, `mount`, `env`,
`group_add`, and `extra_podman_args` are initialized from YAML, and additional
command-line occurrences are appended.

Common settings:

| Variable | Default | Purpose |
| --- | --- | --- |
| `IMAGE` | `ghcr.io/nersc/perlmutter-desktop-containers:debian-12-main` | Container image to run. Set it to the cached reference in the examples above for Perlmutter. |
| `HOST_NOVNC_ADDR` | `127.0.0.1` | Host address for noVNC port publication. |
| `HOST_NOVNC_PORT` | random | Host port for noVNC. |
| `NOVNC_PORT` | `6080` | noVNC port inside the container. |
| `VNC_NOVNC_TRANSPORT` | `tcp` for the standalone runner, `unix` for installed kernels | noVNC exposure mode. `unix` uses a user-private socket and named Jupyter Server Proxy service. |
| `NOVNC_UNIX_SOCKET` | `/tmp/vnc-novnc-$(id -u)/novnc-$(hostname).sock` | noVNC Unix socket path when Unix transport is enabled. |
| `JUPYTER_PROXY_SERVICE` | `vnc-novnc` | Named Jupyter Server Proxy service used by Unix transport. |
| `VNC_PORT` | `5901` | VNC server port inside the container. |
| `VNC_NOVNC_DISPLAY_MODE` | `default` | Display preset. Use `1080p`, `fhd`, or `high` for `1920x1080` with `VNC_DEPTH=32`. |
| `VNC_GEOMETRY` | image default | Explicit VNC desktop size, for example `1920x1080`. |
| `VNC_DEPTH` | image default | Explicit VNC color depth. |
| `EXPOSE_VNC` | `0` | Set to `1` to also publish the raw VNC server port. |
| `VNC_PASSWORD_LENGTH` | `8` | Length of the generated one-time VNC password. |

Common Python helper options:

| Option | Purpose |
| --- | --- |
| `--config FILE` | Read default values from a YAML config file. |
| `--image IMAGE` | Select a container image. |
| `--pull-policy POLICY` | Image preparation policy: `missing`, `newer`, `always`, or `never`. Default: `missing`. |
| `--novnc-transport tcp\|unix` | Expose noVNC through a host TCP port or a user-private Unix socket. |
| `--novnc-socket PATH` | Override the noVNC Unix socket path. |
| `--jupyter-proxy-service NAME` | Named Jupyter Server Proxy service for Unix socket mode. |
| `-v`, `--volume HOST:CONTAINER[:OPTIONS]` | Add a bind mount or volume spec. May be repeated. |
| `--mount SPEC` | Add a Podman `--mount` spec. May be repeated. |
| `-e`, `--env NAME[=VALUE]` | Pass an environment variable into the container. May be repeated. |
| `--userns=keep-id` | Pass `--userns=keep-id` to `podman-hpc`. |
| `--userns-keep-id` | Shorthand for `--userns=keep-id`. |
| `--group-add=keep-groups` | Pass `--group-add=keep-groups` to `podman-hpc`. |
| `--keep-groups` | Shorthand for `--group-add=keep-groups`. |
| `--gpu` | Pass `--gpu` to `podman-hpc` so host GPUs are available in the container. |
| `--expose-vnc` | Publish the raw VNC server port in addition to noVNC. |
| `--dry-run` | Print the generated command without running the container. |
| `--` | Pass following arguments directly to `podman-hpc run` before the image name. |

With `keep-id`, the Python helper also sets the generated container passwd entry
for the host UID to use `/bin/bash`.

## Pull Policy

The Python runner and Jupyter kernel wrapper use explicit image preparation:

- `missing` runs `podman-hpc image inspect` and checks the `podman-hpc images`
  listing first. It pulls only when the image is missing from both normal local
  image metadata and migrated `podman-hpc` image storage. This is the default.
- `newer` and `always` run `podman-hpc pull` before starting the container.
  They keep images fresher, but startup is slower and depends on registry
  availability.
- `never` never pulls and requires the image to already exist locally.

After any needed explicit pull, helpers start the container with
`podman-hpc run --pull=never`. This avoids failures seen when `podman-hpc run`
tries to pull and use a missing image in one step.

## Runner Examples

The examples below show individual options; add
`--config scripts/run-vnc-novnc.yaml` when you want the NERSC mounts and
environment settings from the included configuration.

Use a fixed noVNC host port:

```sh
python3 -m vnc_novnc.runner --host-novnc-port 49967
```

After running `scripts/install-jupyter-kernel.sh --jupyter-proxy-only` or
installing a Unix-mode kernel, restart JupyterLab so its named proxy service
is loaded. A bare runner invocation can then use Unix-socket transport:

```sh
python3 -m vnc_novnc.runner \
  --image registry.nersc.gov/ghcr.io/nersc/perlmutter-desktop-containers:debian-12-main \
  --novnc-transport unix
```

Use another published variant:

```sh
python3 -m vnc_novnc.runner --image registry.nersc.gov/ghcr.io/nersc/perlmutter-desktop-containers:opensuse-15.6-main
python3 -m vnc_novnc.runner --image registry.nersc.gov/ghcr.io/nersc/perlmutter-desktop-containers:ubuntu-24.04-xfce-main
python3 -m vnc_novnc.runner --image registry.nersc.gov/ghcr.io/nersc/perlmutter-desktop-containers:ubuntu24.04-xfce-slurm --slurm
python3 -m vnc_novnc.runner --image registry.nersc.gov/ghcr.io/nersc/perlmutter-desktop-containers:alma-9-xfce-main
```

The `--slurm` example requires the host-side `scli-server` binary installed by
the Slurm-enabled kernel installer.

Expose the raw VNC server port in addition to noVNC:

```sh
python3 -m vnc_novnc.runner \
  --image registry.nersc.gov/ghcr.io/nersc/perlmutter-desktop-containers:debian-12-main \
  --expose-vnc
```

Mount host directories into the container:

```sh
python3 -m vnc_novnc.runner \
  -v "${HOME}:${HOME}:rw" \
  -v "${SCRATCH}:${SCRATCH}:rw"
```

Pass extra `podman-hpc run` arguments:

```sh
python3 -m vnc_novnc.runner -- --ipc=host
```

See [image variants](images.md) for available tags and [Jupyter kernels](jupyter.md) for the notebook workflow.
