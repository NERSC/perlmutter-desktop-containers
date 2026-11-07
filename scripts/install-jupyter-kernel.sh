#!/usr/bin/env bash
set -euo pipefail

usage() {
    cat <<'EOF'
Usage: scripts/install-jupyter-kernel.sh [OPTIONS] [DISTRO [DESKTOP]]

Install the VNC/noVNC podman-hpc Jupyter kernelspec for the current user.

DISTRO and DESKTOP select which published image tag the installed kernel uses.
They may also be passed with --distro and --desktop.
Image pulls prefer the NERSC Registry cache and retry GHCR directly if it fails.
With no variant arguments, install the Perlmutter openSUSE XFCE Slurm kernel.

Options:
  --distro DISTRO         Image distro. Values: debian12, ubuntu24.04, ubuntu,
                          alma9, opensuse15.6. Dash aliases such as
                          debian-12 and opensuse-15.6 are also accepted.
                          When only DESKTOP is given: debian12
  --desktop DESKTOP       Desktop environment. Values depend on distro:
                          debian12: fvwm3, xfce
                          ubuntu24.04: fvwm3, xfce, xfce-slurm
                          ubuntu: gpu-xfce
                          alma9: fvwm3, xfce
                          opensuse15.6: xfce, xfce-slurm
                          When only DISTRO is given: fvwm3
  --name NAME             Kernelspec directory name.
                          Default: vnc-novnc-DISTRO-DESKTOP.
  --display-name NAME     Kernel display name shown in Jupyter.
                          Default: VNC-DISTRO-DESKTOP.
  --display-mode MODE     Display preset for the installed kernel. Values:
                          default, 1080p, fhd, high. Non-default modes add a
                          suffix to the default kernel name/display name.
  --prefix DIR            Jupyter prefix. Installs to DIR/share/jupyter/kernels/NAME.
                          Default: ${HOME}/.local
  --no-pip-install        Do not run "python3 -m pip install --user -e .".
  --source-wrapper        Install a wrapper that imports vnc_novnc from this checkout.
                          This is the default.
  --no-source-wrapper     Do not add this checkout to PYTHONPATH in the wrapper.
  --novnc-transport MODE  noVNC exposure mode for installed kernels: unix or tcp.
                          Default: unix.
  --novnc-socket PATH     noVNC Unix socket path. Default is computed at runtime:
                          /tmp/vnc-novnc-UID/novnc-HOST.sock.
  --jupyter-proxy-service NAME
                          Named Jupyter Server Proxy service for Unix mode.
                          Default: vnc-novnc.
  --slurm                 Enable scli socket setup in the generated kernelspec.
                          Automatically enabled for slurm-cli image variants.
  --no-slurm              Disable scli socket setup in the generated kernelspec.
  --ssh-proxy             Enable host SSH proxy socket setup in the generated kernelspec.
                          Automatically enabled for slurm-cli image variants.
  --no-ssh-proxy          Disable host SSH proxy socket setup in the generated kernelspec.
  --all                   Install one kernelspec for every supported variant.
  --prepull               Run "podman-hpc pull IMAGE" for each installed image.
  --prepull-only          Only run "podman-hpc pull IMAGE"; do not install kernelspecs.
  --podman-hpc COMMAND    podman-hpc command used for image pulls and host proxy installation.
                          Default: ${PODMAN_HPC:-podman-hpc}
  --list-variants         Print supported DISTRO/DESKTOP combinations.
  --force                 Replace an existing kernelspec directory.
  -h, --help              Show this help.
EOF
}

list_variants() {
    cat <<'EOF'
Supported variants:
  debian12      fvwm3  registry.nersc.gov/ghcr.io/nersc/perlmutter-desktop-containers:debian-12-main
  debian12      xfce   registry.nersc.gov/ghcr.io/nersc/perlmutter-desktop-containers:debian-12-xfce-main
  ubuntu24.04   fvwm3  registry.nersc.gov/ghcr.io/nersc/perlmutter-desktop-containers:ubuntu-24.04-fvwm3-main
  ubuntu24.04   xfce   registry.nersc.gov/ghcr.io/nersc/perlmutter-desktop-containers:ubuntu-24.04-xfce-main
  ubuntu24.04   xfce-slurm registry.nersc.gov/ghcr.io/nersc/perlmutter-desktop-containers:ubuntu24.04-xfce-slurm
  ubuntu        gpu-xfce registry.nersc.gov/ghcr.io/nersc/perlmutter-desktop-containers:ubuntu-gpu-xfce-main
  alma9         fvwm3  registry.nersc.gov/ghcr.io/nersc/perlmutter-desktop-containers:alma-9-fvwm3-main
  alma9         xfce   registry.nersc.gov/ghcr.io/nersc/perlmutter-desktop-containers:alma-9-xfce-main
  opensuse15.6  xfce   registry.nersc.gov/ghcr.io/nersc/perlmutter-desktop-containers:opensuse-15.6-main
  opensuse15.6  xfce-slurm registry.nersc.gov/ghcr.io/nersc/perlmutter-desktop-containers:opensuse15.6-xfce-slurm
EOF
}

canonical_distro() {
    case "$1" in
        debian12|debian-12) printf 'debian12\n' ;;
        ubuntu|cuda|cuda13|cuda-13) printf 'ubuntu\n' ;;
        ubuntu24.04|ubuntu-24.04) printf 'ubuntu24.04\n' ;;
        alma9|alma-9|almalinux9|almalinux-9) printf 'alma9\n' ;;
        opensuse15.6|opensuse-15.6|opensuseleap15.6|opensuse-leap-15.6) printf 'opensuse15.6\n' ;;
        *)
            printf 'Unsupported distro: %s\n\n' "$1" >&2
            list_variants >&2
            exit 2
            ;;
    esac
}

canonical_desktop() {
    case "$1" in
        fvwm3|xfce|xfce-slurm|gpu-xfce) printf '%s\n' "$1" ;;
        XFCE) printf 'xfce\n' ;;
        FVWM3) printf 'fvwm3\n' ;;
        XFCE-SLURM|XFCE_SLURM) printf 'xfce-slurm\n' ;;
        GPU-XFCE|GPU_XFCE) printf 'gpu-xfce\n' ;;
        *)
            printf 'Unsupported desktop: %s\n\n' "$1" >&2
            list_variants >&2
            exit 2
            ;;
    esac
}

set_variant_metadata() {
    extra_podman_args=()
    variant_gpu=0
    variant_slurm=0
    variant_ssh_proxy=0

    case "${distro}:${desktop}" in
        debian12:fvwm3)
            image="registry.nersc.gov/ghcr.io/nersc/perlmutter-desktop-containers:debian-12-main"
            variant_slug="debian12-fvwm3"
            ;;
        debian12:xfce)
            image="registry.nersc.gov/ghcr.io/nersc/perlmutter-desktop-containers:debian-12-xfce-main"
            variant_slug="debian12-xfce"
            ;;
        ubuntu24.04:fvwm3)
            image="registry.nersc.gov/ghcr.io/nersc/perlmutter-desktop-containers:ubuntu-24.04-fvwm3-main"
            variant_slug="ubuntu24.04-fvwm3"
            ;;
        ubuntu24.04:xfce)
            image="registry.nersc.gov/ghcr.io/nersc/perlmutter-desktop-containers:ubuntu-24.04-xfce-main"
            variant_slug="ubuntu24.04-xfce"
            ;;
        ubuntu24.04:xfce-slurm)
            image="registry.nersc.gov/ghcr.io/nersc/perlmutter-desktop-containers:ubuntu24.04-xfce-slurm"
            variant_slug="ubuntu24.04-xfce-slurm"
            variant_gpu=1
            variant_slurm=1
            variant_ssh_proxy=1
            ;;
        ubuntu:gpu-xfce)
            image="registry.nersc.gov/ghcr.io/nersc/perlmutter-desktop-containers:ubuntu-gpu-xfce-main"
            variant_slug="ubuntu-gpu-xfce"
            variant_gpu=1
            ;;
        alma9:fvwm3)
            image="registry.nersc.gov/ghcr.io/nersc/perlmutter-desktop-containers:alma-9-fvwm3-main"
            variant_slug="alma9-fvwm3"
            ;;
        alma9:xfce)
            image="registry.nersc.gov/ghcr.io/nersc/perlmutter-desktop-containers:alma-9-xfce-main"
            variant_slug="alma9-xfce"
            ;;
        opensuse15.6:xfce)
            image="registry.nersc.gov/ghcr.io/nersc/perlmutter-desktop-containers:opensuse-15.6-main"
            variant_slug="opensuse15.6-xfce"
            ;;
        opensuse15.6:xfce-slurm)
            image="registry.nersc.gov/ghcr.io/nersc/perlmutter-desktop-containers:opensuse15.6-xfce-slurm"
            variant_slug="opensuse15.6-xfce-slurm"
            variant_gpu=1
            variant_slurm=1
            variant_ssh_proxy=1
            ;;
        *)
            printf 'Unsupported distro/desktop combination: %s %s\n\n' "${distro}" "${desktop}" >&2
            list_variants >&2
            exit 2
            ;;
    esac
}

apply_novnc_transport_image_metadata() {
    if [[ "${novnc_transport}" != "unix" ]]; then
        return 0
    fi

    case "${distro}:${desktop}" in
        opensuse15.6:xfce-slurm)
            image="registry.nersc.gov/ghcr.io/nersc/perlmutter-desktop-containers:opensuse15.6-xfce-slurm-unix"
            ;;
    esac
}

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_dir="$(cd "${script_dir}/.." && pwd)"
install_python="$(python3 -c 'import sys; print(sys.executable)')"

distro="debian12"
desktop="fvwm3"
kernel_name=""
display_name=""
display_mode="default"
prefix="${HOME}/.local"
pip_install=1
source_wrapper=1
slurm_override=""
ssh_proxy_override=""
novnc_transport="unix"
novnc_socket=""
jupyter_proxy_service="vnc-novnc"
force=0
all_variants=0
prepull=0
prepull_only=0
podman_hpc="${PODMAN_HPC:-podman-hpc}"
kernel_name_set=0
display_name_set=0
display_mode_set=0
distro_set=0
desktop_set=0
positionals=()
prepulled_images=()
extra_podman_args=()
variant_gpu=0
variant_slurm=0
variant_ssh_proxy=0
host_proxy_servers_installed=0
jupyter_proxy_config_installed=0

while [[ "$#" -gt 0 ]]; do
    case "$1" in
        --distro)
            distro="${2:?--distro requires a value}"
            distro_set=1
            shift 2
            ;;
        --desktop)
            desktop="${2:?--desktop requires a value}"
            desktop_set=1
            shift 2
            ;;
        --name)
            kernel_name="${2:?--name requires a value}"
            kernel_name_set=1
            shift 2
            ;;
        --display-name)
            display_name="${2:?--display-name requires a value}"
            display_name_set=1
            shift 2
            ;;
        --display-mode)
            display_mode="${2:?--display-mode requires a value}"
            display_mode_set=1
            shift 2
            ;;
        --prefix)
            prefix="${2:?--prefix requires a value}"
            shift 2
            ;;
        --no-pip-install)
            pip_install=0
            shift
            ;;
        --source-wrapper)
            source_wrapper=1
            shift
            ;;
        --no-source-wrapper)
            source_wrapper=0
            shift
            ;;
        --novnc-transport)
            novnc_transport="${2:?--novnc-transport requires a value}"
            shift 2
            ;;
        --novnc-socket)
            novnc_socket="${2:?--novnc-socket requires a value}"
            shift 2
            ;;
        --jupyter-proxy-service)
            jupyter_proxy_service="${2:?--jupyter-proxy-service requires a value}"
            shift 2
            ;;
        --slurm)
            slurm_override=1
            shift
            ;;
        --no-slurm)
            slurm_override=0
            shift
            ;;
        --ssh-proxy)
            ssh_proxy_override=1
            shift
            ;;
        --no-ssh-proxy)
            ssh_proxy_override=0
            shift
            ;;
        --all)
            all_variants=1
            shift
            ;;
        --prepull)
            prepull=1
            shift
            ;;
        --prepull-only)
            prepull=1
            prepull_only=1
            shift
            ;;
        --podman-hpc)
            podman_hpc="${2:?--podman-hpc requires a value}"
            shift 2
            ;;
        --list-variants)
            list_variants
            exit 0
            ;;
        --force)
            force=1
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        --)
            shift
            while [[ "$#" -gt 0 ]]; do
                positionals+=("$1")
                shift
            done
            ;;
        -*)
            printf 'Unknown option: %s\n\n' "$1" >&2
            usage >&2
            exit 2
            ;;
        *)
            positionals+=("$1")
            shift
            ;;
    esac
done

if [[ "${#positionals[@]}" -gt 2 ]]; then
    printf 'Expected at most DISTRO and DESKTOP positional arguments; got %s.\n\n' "${#positionals[@]}" >&2
    usage >&2
    exit 2
fi

if [[ "${#positionals[@]}" -ge 1 ]]; then
    distro="${positionals[0]}"
    distro_set=1
fi

if [[ "${#positionals[@]}" -ge 2 ]]; then
    desktop="${positionals[1]}"
    desktop_set=1
fi

if [[ "${distro_set}" -eq 0 && "${desktop_set}" -eq 0 && "${all_variants}" -eq 0 ]]; then
    distro="opensuse15.6"
    desktop="xfce-slurm"
fi

case "${display_mode,,}" in
    default|"")
        display_mode="default"
        ;;
    1080p|fhd|high)
        display_mode="${display_mode,,}"
        ;;
    *)
        printf 'Unsupported display mode: %s\n\n' "${display_mode}" >&2
        usage >&2
        exit 2
        ;;
esac

case "${novnc_transport,,}" in
    unix|tcp)
        novnc_transport="${novnc_transport,,}"
        ;;
    *)
        printf 'Unsupported noVNC transport: %s\n\n' "${novnc_transport}" >&2
        usage >&2
        exit 2
        ;;
esac

case "${jupyter_proxy_service}" in
    ""|*/*)
        printf 'Jupyter proxy service name must be non-empty and must not contain "/": %s\n' "${jupyter_proxy_service}" >&2
        exit 2
        ;;
esac

kernel_src="${repo_dir}/kernels/vnc-novnc"

if [[ ! -f "${kernel_src}/kernel.json" ]]; then
    printf 'Missing sample kernelspec: %s\n' "${kernel_src}/kernel.json" >&2
    exit 1
fi

if [[ "${all_variants}" -eq 1 ]]; then
    if [[ "${distro_set}" -eq 1 || "${desktop_set}" -eq 1 || "${kernel_name_set}" -eq 1 || "${display_name_set}" -eq 1 || "${display_mode_set}" -eq 1 || -n "${slurm_override}" || -n "${ssh_proxy_override}" ]]; then
        printf '%s\n' '--all cannot be combined with DISTRO, DESKTOP, --distro, --desktop, --name, --display-name, --display-mode, --slurm, --no-slurm, --ssh-proxy, or --no-ssh-proxy.' >&2
        exit 2
    fi
fi

if [[ "${pip_install}" -eq 1 && "${prepull_only}" -ne 1 ]]; then
    "${install_python}" -m pip install --user -e "${repo_dir}"
fi

tmpdir="$(mktemp -d)"
cleanup() {
    rm -rf "${tmpdir}"
}
trap cleanup EXIT

image_already_prepulled() {
    local candidate="$1"
    local pulled_image

    for pulled_image in "${prepulled_images[@]}"; do
        if [[ "${pulled_image}" == "${candidate}" ]]; then
            return 0
        fi
    done

    return 1
}

image_available_locally() {
    local candidate="$1"
    local listed_image

    if "${podman_hpc}" image inspect "${candidate}" >/dev/null 2>&1; then
        return 0
    fi

    while IFS= read -r listed_image; do
        if [[ "${listed_image}" == "${candidate}" ]]; then
            return 0
        fi
    done < <("${podman_hpc}" images --format '{{.Repository}}:{{.Tag}}' "${candidate}" 2>/dev/null || true)

    return 1
}

prepull_image() {
    local pull_image="$1"
    local fallback_image

    if image_already_prepulled "${pull_image}"; then
        return 0
    fi

    if image_available_locally "${pull_image}"; then
        printf 'Image already available locally or as a migrated podman-hpc image: %s\n' "${pull_image}"
        prepulled_images+=("${pull_image}")
        return 0
    fi

    printf 'Pre-pulling image: %s\n' "${pull_image}"
    if "${podman_hpc}" pull "${pull_image}"; then
        prepulled_images+=("${pull_image}")
        return 0
    fi

    case "${pull_image}" in
        registry.nersc.gov/ghcr.io/nersc/perlmutter-desktop-containers:*)
            fallback_image="${pull_image#registry.nersc.gov/}"
            ;;
        *)
            return 1
            ;;
    esac

    printf 'NERSC Registry pull failed; using GHCR directly: %s\n' "${fallback_image}" >&2
    if image_available_locally "${fallback_image}"; then
        printf 'Image already available locally or as a migrated podman-hpc image: %s\n' "${fallback_image}"
    else
        "${podman_hpc}" pull "${fallback_image}"
    fi
    image="${fallback_image}"
    prepulled_images+=("${fallback_image}")
}

install_host_proxy_servers() {
    local package_image="${HOST_PROXY_IMAGE:-registry.nersc.gov/ghcr.io/nersc/perlmutter-desktop-containers:host-proxies-linux-amd64}"
    local fallback_image

    if [[ "${host_proxy_servers_installed}" -eq 1 ]]; then
        return 0
    fi
    if [[ "$(uname -m)" != "x86_64" ]]; then
        printf 'The published host proxy binaries require an x86_64 host.\n' >&2
        return 1
    fi
    if ! command -v "${podman_hpc}" >/dev/null 2>&1; then
        printf 'podman-hpc is required to install the host proxy binaries.\n' >&2
        return 1
    fi

    if ! image_available_locally "${package_image}"; then
        printf 'Pulling host proxy binaries: %s\n' "${package_image}"
        if ! "${podman_hpc}" pull "${package_image}"; then
            case "${package_image}" in
                registry.nersc.gov/ghcr.io/nersc/perlmutter-desktop-containers:*)
                    fallback_image="${package_image#registry.nersc.gov/}"
                    ;;
                *)
                    return 1
                    ;;
            esac
            printf 'NERSC Registry pull failed; using GHCR directly: %s\n' "${fallback_image}" >&2
            package_image="${fallback_image}"
            if ! image_available_locally "${package_image}"; then
                "${podman_hpc}" pull "${package_image}"
            fi
        fi
    fi

    (
        staging_dir="$(mktemp -d "${TMPDIR:-/tmp}/vnc-novnc-host-proxies.XXXXXXXX")"
        container_id=""
        cleanup() {
            if [[ -n "${container_id}" ]]; then
                "${podman_hpc}" rm "${container_id}" >/dev/null 2>&1 || true
            fi
            rm -rf "${staging_dir}"
        }
        trap cleanup EXIT

        container_id="$("${podman_hpc}" create "${package_image}")"
        "${podman_hpc}" cp "${container_id}:/usr/local/bin/." "${staging_dir}"
        (cd "${staging_dir}" && sha256sum -c SHA256SUMS)
        mkdir -p "${HOME}/bin"
        install -m 0755 "${staging_dir}/scli-server" "${HOME}/bin/scli-server"
        install -m 0755 "${staging_dir}/ssh-proxy-server" "${HOME}/bin/ssh-proxy-server"
    )
    host_proxy_servers_installed=1
    printf 'Installed host proxy binaries in %s/bin.\n' "${HOME}"
}

install_jupyter_proxy_config() {
    if [[ "${novnc_transport}" != "unix" ]]; then
        return 0
    fi
    if [[ "${jupyter_proxy_config_installed}" -eq 1 ]]; then
        return 0
    fi

    local jupyter_config_dir="${HOME}/.jupyter"
    local jupyter_config="${jupyter_config_dir}/jupyter_server_config.py"
    mkdir -p "${jupyter_config_dir}"

    python3 - "${jupyter_config}" "${jupyter_proxy_service}" "${novnc_socket}" <<'PY'
from pathlib import Path
import json
import sys

config_path = Path(sys.argv[1])
service = sys.argv[2]
configured_socket = sys.argv[3]

begin = "# BEGIN vnc-novnc-container noVNC Unix socket proxy"
end = "# END vnc-novnc-container noVNC Unix socket proxy"

block = f"""{begin}
import os as _vnc_novnc_os
import re as _vnc_novnc_re
import socket as _vnc_novnc_socket
import tempfile as _vnc_novnc_tempfile

def _vnc_novnc_safe_hostname():
    return _vnc_novnc_re.sub(
        r"[^A-Za-z0-9_.-]",
        "_",
        _vnc_novnc_socket.gethostname() or "unknown",
    )

def _vnc_novnc_socket_path():
    configured = {json.dumps(configured_socket)}
    if configured:
        return _vnc_novnc_os.path.expandvars(_vnc_novnc_os.path.expanduser(configured))
    return _vnc_novnc_os.path.join(
        _vnc_novnc_tempfile.gettempdir(),
        "vnc-novnc-{{}}".format(_vnc_novnc_os.getuid()),
        "novnc-{{}}.sock".format(_vnc_novnc_safe_hostname()),
    )

c.ServerProxy.servers.update({{
    {json.dumps(service)}: {{
        "command": [],
        "unix_socket": _vnc_novnc_socket_path(),
        "launcher_entry": {{"enabled": False}},
        "timeout": 30,
    }}
}})
{end}
"""

existing = config_path.read_text() if config_path.exists() else ""
if begin in existing and end in existing:
    before, rest = existing.split(begin, 1)
    _, after = rest.split(end, 1)
    existing = before.rstrip() + "\n\n" + block + after
else:
    prefix = existing.rstrip()
    existing = (prefix + "\n\n" if prefix else "") + block

config_path.write_text(existing)
PY

    jupyter_proxy_config_installed=1
    printf 'Installed Jupyter Server Proxy config: %s\n' "${jupyter_config}"
    printf 'Restart the Jupyter session once for the noVNC Unix socket service to be loaded.\n'
}

install_one() {
    local install_distro="$1"
    local install_desktop="$2"
    local install_kernel_name="${3:-}"
    local install_display_name="${4:-}"
    local kernel_dst

    distro="$(canonical_distro "${install_distro}")"
    desktop="$(canonical_desktop "${install_desktop}")"
    set_variant_metadata
    apply_novnc_transport_image_metadata
    if [[ -n "${slurm_override}" ]]; then
        variant_slurm="${slurm_override}"
    fi
    if [[ -n "${ssh_proxy_override}" ]]; then
        variant_ssh_proxy="${ssh_proxy_override}"
    fi

    if [[ "${variant_slurm}" -eq 1 || "${variant_ssh_proxy}" -eq 1 ]]; then
        install_host_proxy_servers
    fi

    if [[ "${prepull}" -eq 1 ]]; then
        prepull_image "${image}"
    fi

    if [[ -z "${install_kernel_name}" ]]; then
        install_kernel_name="vnc-novnc-${variant_slug}"
        if [[ "${display_mode}" != "default" ]]; then
            install_kernel_name="${install_kernel_name}-${display_mode}"
        fi
    fi

    if [[ -z "${install_display_name}" ]]; then
        install_display_name="VNC-${distro}-${desktop}"
        if [[ "${display_mode}" != "default" ]]; then
            install_display_name="${install_display_name}-${display_mode}"
        fi
    fi

    kernel_dst="${prefix}/share/jupyter/kernels/${install_kernel_name}"

    if [[ -e "${kernel_dst}" && "${force}" -ne 1 ]]; then
        printf 'Kernelspec already exists: %s\n' "${kernel_dst}" >&2
        printf 'Re-run with --force to replace it.\n' >&2
        exit 1
    fi

    mkdir -p "${tmpdir}/${install_kernel_name}"
    cp "${kernel_src}/kernel.json" "${tmpdir}/${install_kernel_name}/"
    cp "${kernel_src}/kernel-wrapper" "${tmpdir}/${install_kernel_name}/"
    cp "${kernel_src}/vnc-novnc.yaml" "${tmpdir}/${install_kernel_name}/"

    python3 - "${tmpdir}/${install_kernel_name}/kernel.json" "${tmpdir}/${install_kernel_name}/vnc-novnc.yaml" "${install_display_name}" "${image}" "${variant_gpu}" "${variant_slurm}" "${variant_ssh_proxy}" "${display_mode}" "${novnc_transport}" "${novnc_socket}" "${jupyter_proxy_service}" "${extra_podman_args[@]}" <<'PY'
import json
import sys

kernel_json, kernel_yaml, display_name, image, gpu_enabled, slurm_enabled, ssh_proxy_enabled, display_mode, novnc_transport, novnc_socket, jupyter_proxy_service = sys.argv[1:12]
extra_podman_args = sys.argv[12:]
pull_policy = "missing"
slurm_volumes = [
    "/global:/global",
    "${SCRATCH}:${SCRATCH}:rw",
    "${CFS}:${CFS}:rw",
    "/opt:/opt",
    "/etc/cray-pe.d:/etc/cray-pe.d:ro",
    "/etc/clustername:/etc/clustername:ro",
    "/etc/environment:/etc/environment:ro",
]
slurm_env = [
    "HOME",
    "MODULEPATH",
    "MODULEPATH_ROOT",
    "MODULESHOME",
    "PE_ENV",
    "LMOD_FAMILY_MPI",
    "LMOD_FAMILY_CUDATOOLKIT",
    "LMOD_FAMILY_CUDATOOLKIT_VERSION",
]
with open(kernel_json) as handle:
    data = json.load(handle)
data["display_name"] = display_name
with open(kernel_json, "w") as handle:
    json.dump(data, handle, indent=2)
    handle.write("\n")

def set_yaml_scalar(lines, key, value):
    replacement = f"{key}: {value}\n"
    for index, line in enumerate(lines):
        if line.startswith(f"{key}:"):
            lines[index] = replacement
            return
    lines.insert(0, replacement)

def set_yaml_list(lines, key, values):
    start = None
    end = None
    for index, line in enumerate(lines):
        if line.startswith(f"{key}:"):
            start = index
            end = index + 1
            while end < len(lines) and lines[end].startswith("  - "):
                end += 1
            break

    replacement = []
    if values:
        replacement = [f"{key}:\n"]
        replacement.extend(f"  - {value}\n" for value in values)

    if start is None:
        if replacement:
            lines.extend(["\n"] + replacement)
        return

    lines[start:end] = replacement

with open(kernel_yaml) as handle:
    lines = handle.readlines()

set_yaml_scalar(lines, "image", image)
set_yaml_scalar(lines, "pull_policy", pull_policy)
set_yaml_scalar(lines, "gpu", "true" if gpu_enabled == "1" else "false")
set_yaml_scalar(lines, "slurm", "true" if slurm_enabled == "1" else "false")
set_yaml_scalar(lines, "ssh_proxy", "true" if ssh_proxy_enabled == "1" else "false")
set_yaml_scalar(lines, "display_mode", display_mode)
set_yaml_scalar(lines, "novnc_transport", novnc_transport)
set_yaml_scalar(lines, "novnc_socket", novnc_socket)
set_yaml_scalar(lines, "jupyter_proxy_service", jupyter_proxy_service)
set_yaml_list(lines, "extra_podman_args", extra_podman_args)
if slurm_enabled == "1":
    set_yaml_list(lines, "volume", slurm_volumes)
    set_yaml_list(lines, "env", slurm_env)

with open(kernel_yaml, "w") as handle:
    handle.writelines(lines)
PY

    "${install_python}" - "${tmpdir}/${install_kernel_name}/kernel-wrapper" "${install_python}" "${repo_dir}" "${source_wrapper}" <<'PY'
import shlex
import sys

wrapper_path, python_executable, repo_dir, source_wrapper = sys.argv[1:5]
with open(wrapper_path, "w") as handle:
    handle.write("#!/bin/sh\n")
    handle.write(r'''
slurm_config_path=
slurm_config_enabled=
slurm_cli_enabled=
slurm_socket="${SCLI_SOCKET:-}"
ssh_proxy_config_enabled=
ssh_proxy_cli_enabled=
ssh_proxy_socket="${SSH_PROXY_SOCKET:-}"
vnc_novnc_dry_run=0

vnc_novnc_read_yaml_scalar() {
    awk -F: -v key="$1" '
        $1 == key {
            sub(/^[^:]*:[[:space:]]*/, "")
            gsub(/^[[:space:]]+|[[:space:]]+$/, "")
            gsub(/^"|"$/, "")
            gsub(/^'\''|'\''$/, "")
            print
            exit
        }
    ' "$2"
}

vnc_novnc_detect_slurm() {
    while [ "$#" -gt 0 ]; do
        case "$1" in
            --config)
                slurm_config_path="${2:-}"
                shift 2
                ;;
            --slurm)
                slurm_cli_enabled=1
                shift
                ;;
            --no-slurm)
                slurm_cli_enabled=0
                shift
                ;;
            --ssh-proxy)
                ssh_proxy_cli_enabled=1
                shift
                ;;
            --no-ssh-proxy)
                ssh_proxy_cli_enabled=0
                shift
                ;;
            --slurm-socket)
                slurm_socket="${2:-}"
                shift 2
                ;;
            --ssh-proxy-socket)
                ssh_proxy_socket="${2:-}"
                shift 2
                ;;
            --dry-run)
                vnc_novnc_dry_run=1
                shift
                ;;
            --)
                break
                ;;
            *)
                shift
                ;;
        esac
    done

    if [ -n "$slurm_config_path" ] && [ -f "$slurm_config_path" ]; then
        case "$(vnc_novnc_read_yaml_scalar slurm "$slurm_config_path")" in
            1|true|True|TRUE|yes|Yes|YES|on|On|ON) slurm_config_enabled=1 ;;
            0|false|False|FALSE|no|No|NO|off|Off|OFF) slurm_config_enabled=0 ;;
        esac
        case "$(vnc_novnc_read_yaml_scalar ssh_proxy "$slurm_config_path")" in
            1|true|True|TRUE|yes|Yes|YES|on|On|ON) ssh_proxy_config_enabled=1 ;;
            0|false|False|FALSE|no|No|NO|off|Off|OFF) ssh_proxy_config_enabled=0 ;;
        esac
        if [ -z "$slurm_socket" ]; then
            slurm_socket="$(vnc_novnc_read_yaml_scalar slurm_socket "$slurm_config_path")"
        fi
        if [ -z "$ssh_proxy_socket" ]; then
            ssh_proxy_socket="$(vnc_novnc_read_yaml_scalar ssh_proxy_socket "$slurm_config_path")"
        fi
    fi

    if [ -n "$slurm_cli_enabled" ]; then
        VNC_NOVNC_SLURM="$slurm_cli_enabled"
    elif [ -n "$slurm_config_enabled" ]; then
        VNC_NOVNC_SLURM="$slurm_config_enabled"
    else
        VNC_NOVNC_SLURM="${VNC_NOVNC_SLURM:-0}"
    fi

    if [ -n "$ssh_proxy_cli_enabled" ]; then
        VNC_NOVNC_SSH_PROXY="$ssh_proxy_cli_enabled"
    elif [ -n "$ssh_proxy_config_enabled" ]; then
        VNC_NOVNC_SSH_PROXY="$ssh_proxy_config_enabled"
    else
        VNC_NOVNC_SSH_PROXY="${VNC_NOVNC_SSH_PROXY:-0}"
    fi
}

vnc_novnc_socket_is_live() {
    [ -S "$1" ] || return 1
    python3 - "$1" <<'VNC_NOVNC_SOCKET_PY' >/dev/null 2>&1
import socket
import sys

sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
sock.settimeout(0.5)
try:
    sock.connect(sys.argv[1])
except OSError:
    raise SystemExit(1)
finally:
    sock.close()
VNC_NOVNC_SOCKET_PY
}

vnc_novnc_remove_stale_socket() {
    if [ -S "$1" ] && ! vnc_novnc_socket_is_live "$1"; then
        rm -f "$1"
    fi
}

vnc_novnc_start_scli_server() {
    case "$VNC_NOVNC_SLURM" in
        1|true|True|TRUE|yes|Yes|YES|on|On|ON) ;;
        *) return 0 ;;
    esac
    if [ "$vnc_novnc_dry_run" = "1" ]; then
        return 0
    fi

    if [ -z "$slurm_socket" ]; then
        socket_host="$(hostname 2>/dev/null || printf unknown)"
        socket_host="$(printf '%s' "$socket_host" | tr -c 'A-Za-z0-9_.-' '_')"
        if [ -n "${SCLI_SOCKET:-}" ]; then
            slurm_socket="$SCLI_SOCKET"
        elif [ -n "${XDG_RUNTIME_DIR:-}" ]; then
            slurm_socket="${XDG_RUNTIME_DIR}/scli-${socket_host}.sock"
        else
            slurm_socket="/tmp/vnc-novnc-$(id -u)/scli-${socket_host}.sock"
        fi
    fi
    SCLI_SOCKET="$slurm_socket"
    export SCLI_SOCKET VNC_NOVNC_SLURM

    if vnc_novnc_socket_is_live "$SCLI_SOCKET"; then
        return 0
    fi
    vnc_novnc_remove_stale_socket "$SCLI_SOCKET"

    scli_server="${SCLI_SERVER:-${HOME}/bin/scli-server}"
    if [ ! -x "$scli_server" ]; then
        echo "scli-server is not executable: $scli_server" >&2
        exit 1
    fi

    socket_dir="$(dirname "$SCLI_SOCKET")"
    mkdir -p "$socket_dir"
    chmod 700 "$socket_dir" 2>/dev/null || true

    log_user="${USER:-$(id -u)}"
    scli_log="${SCLI_SERVER_LOG:-/tmp/vnc-novnc-scli-server-${log_user}.log}"
    mkdir -p "$(dirname "$scli_log")"
    echo "Starting scli-server: $scli_server --socket $SCLI_SOCKET" >&2
    "$scli_server" --socket "$SCLI_SOCKET" >>"$scli_log" 2>&1 &

    i=0
    while [ "$i" -lt 50 ]; do
        if [ -S "$SCLI_SOCKET" ]; then
            echo "scli-server log: $scli_log" >&2
            return 0
        fi
        i=$((i + 1))
        sleep 0.1
    done

    echo "Timed out waiting for scli-server socket: $SCLI_SOCKET" >&2
    echo "See log: $scli_log" >&2
    exit 1
}

vnc_novnc_start_ssh_proxy_server() {
    case "$VNC_NOVNC_SSH_PROXY" in
        1|true|True|TRUE|yes|Yes|YES|on|On|ON) ;;
        *) return 0 ;;
    esac
    if [ "$vnc_novnc_dry_run" = "1" ]; then
        return 0
    fi

    if [ -z "$ssh_proxy_socket" ]; then
        socket_host="$(hostname 2>/dev/null || printf unknown)"
        socket_host="$(printf '%s' "$socket_host" | tr -c 'A-Za-z0-9_.-' '_')"
        if [ -n "${SSH_PROXY_SOCKET:-}" ]; then
            ssh_proxy_socket="$SSH_PROXY_SOCKET"
        elif [ -n "${XDG_RUNTIME_DIR:-}" ]; then
            ssh_proxy_socket="${XDG_RUNTIME_DIR}/ssh-proxy-${socket_host}.sock"
        else
            ssh_proxy_socket="/tmp/vnc-novnc-$(id -u)/ssh-proxy-${socket_host}.sock"
        fi
    fi
    SSH_PROXY_SOCKET="$ssh_proxy_socket"
    export SSH_PROXY_SOCKET VNC_NOVNC_SSH_PROXY

    if vnc_novnc_socket_is_live "$SSH_PROXY_SOCKET"; then
        return 0
    fi
    vnc_novnc_remove_stale_socket "$SSH_PROXY_SOCKET"

    ssh_proxy_server="${SSH_PROXY_SERVER:-${HOME}/bin/ssh-proxy-server}"
    if [ ! -x "$ssh_proxy_server" ]; then
        echo "ssh-proxy-server is not executable: $ssh_proxy_server" >&2
        exit 1
    fi

    socket_dir="$(dirname "$SSH_PROXY_SOCKET")"
    mkdir -p "$socket_dir"
    chmod 700 "$socket_dir" 2>/dev/null || true

    log_user="${USER:-$(id -u)}"
    ssh_proxy_log="${SSH_PROXY_SERVER_LOG:-/tmp/vnc-novnc-ssh-proxy-server-${log_user}.log}"
    mkdir -p "$(dirname "$ssh_proxy_log")"
    echo "Starting ssh-proxy-server: $ssh_proxy_server --socket $SSH_PROXY_SOCKET" >&2
    "$ssh_proxy_server" --socket "$SSH_PROXY_SOCKET" >>"$ssh_proxy_log" 2>&1 &

    i=0
    while [ "$i" -lt 50 ]; do
        if [ -S "$SSH_PROXY_SOCKET" ]; then
            echo "ssh-proxy-server log: $ssh_proxy_log" >&2
            return 0
        fi
        i=$((i + 1))
        sleep 0.1
    done

    echo "Timed out waiting for ssh-proxy-server socket: $SSH_PROXY_SOCKET" >&2
    echo "See log: $ssh_proxy_log" >&2
    exit 1
}

vnc_novnc_detect_slurm "$@"
vnc_novnc_start_scli_server
vnc_novnc_start_ssh_proxy_server
''')
    if source_wrapper == "1":
        handle.write(
            "export PYTHONPATH={}:\"${{PYTHONPATH:-}}\"\n".format(
                shlex.quote(repo_dir)
            )
        )
    handle.write(
        "exec {} -m vnc_novnc.kernel \"$@\"\n".format(
            shlex.quote(python_executable)
        )
    )
PY

    chmod 0755 "${tmpdir}/${install_kernel_name}/kernel-wrapper"
    mkdir -p "$(dirname "${kernel_dst}")"
    rm -rf "${kernel_dst}"
    cp -R "${tmpdir}/${install_kernel_name}" "${kernel_dst}"
    install_jupyter_proxy_config

    printf 'Installed kernelspec: %s\n' "${kernel_dst}"
    printf 'Kernel display name: %s\n' "${install_display_name}"
    printf 'Kernel image: %s\n' "${image}"
    printf 'Config file: %s\n' "${kernel_dst}/vnc-novnc.yaml"
}

prepull_one() {
    local pull_distro="$1"
    local pull_desktop="$2"

    distro="$(canonical_distro "${pull_distro}")"
    desktop="$(canonical_desktop "${pull_desktop}")"
    set_variant_metadata
    apply_novnc_transport_image_metadata
    prepull_image "${image}"
    printf 'Image available for %s %s: %s\n' "${distro}" "${desktop}" "${image}"
}

if [[ "${prepull_only}" -eq 1 ]]; then
    if [[ "${all_variants}" -eq 1 ]]; then
        prepull_one debian12 fvwm3
        prepull_one debian12 xfce
        prepull_one ubuntu24.04 fvwm3
        prepull_one ubuntu24.04 xfce
        prepull_one ubuntu24.04 xfce-slurm
        prepull_one ubuntu gpu-xfce
        prepull_one alma9 fvwm3
        prepull_one alma9 xfce
        prepull_one opensuse15.6 xfce
        prepull_one opensuse15.6 xfce-slurm
    else
        prepull_one "${distro}" "${desktop}"
    fi

    printf 'Image preparation complete.\n'
    exit 0
fi

if [[ "${all_variants}" -eq 1 ]]; then
    install_one debian12 fvwm3
    install_one debian12 xfce
    install_one ubuntu24.04 fvwm3
    install_one ubuntu24.04 xfce
    install_one ubuntu24.04 xfce-slurm
    install_one ubuntu gpu-xfce
    install_one alma9 fvwm3
    install_one alma9 xfce
    install_one opensuse15.6 xfce
    install_one opensuse15.6 xfce-slurm
else
    distro="$(canonical_distro "${distro}")"
    desktop="$(canonical_desktop "${desktop}")"
    set_variant_metadata

    if [[ "${kernel_name_set}" -ne 1 ]]; then
        kernel_name="vnc-novnc-${variant_slug}"
        if [[ "${display_mode}" != "default" ]]; then
            kernel_name="${kernel_name}-${display_mode}"
        fi
    fi

    if [[ "${display_name_set}" -ne 1 ]]; then
        display_name="VNC-${distro}-${desktop}"
        if [[ "${display_mode}" != "default" ]]; then
            display_name="${display_name}-${display_mode}"
        fi
    fi

    install_one "${distro}" "${desktop}" "${kernel_name}" "${display_name}"
fi

printf 'To verify visible kernels, run: jupyter kernelspec list\n'
