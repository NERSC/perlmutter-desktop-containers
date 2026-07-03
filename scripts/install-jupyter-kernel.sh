#!/usr/bin/env bash
set -euo pipefail

usage() {
    cat <<'EOF'
Usage: scripts/install-jupyter-kernel.sh [OPTIONS] [DISTRO [DESKTOP]]

Install the VNC/noVNC podman-hpc Jupyter kernelspec for the current user.

DISTRO and DESKTOP select which published image tag the installed kernel uses.
They may also be passed with --distro and --desktop.

Options:
  --distro DISTRO         Image distro. Values: debian12, ubuntu24.04, ubuntu,
                          alma9, opensuse15.6. Dash aliases such as
                          debian-12 and opensuse-15.6 are also accepted.
                          Default: debian12
  --desktop DESKTOP       Desktop environment. Values depend on distro:
                          debian12: fvwm3, xfce
                          ubuntu24.04: fvwm3, xfce, xfce-slurm
                          ubuntu: gpu-xfce
                          alma9: fvwm3, xfce
                          opensuse15.6: xfce, xfce-slurm
                          Default: fvwm3
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
  --slurm                 Enable scli socket setup in the generated kernelspec.
                          Automatically enabled for slurm-cli image variants.
  --no-slurm              Disable scli socket setup in the generated kernelspec.
  --ssh-proxy             Enable host SSH proxy socket setup in the generated kernelspec.
                          Automatically enabled for slurm-cli image variants.
  --no-ssh-proxy          Disable host SSH proxy socket setup in the generated kernelspec.
  --all                   Install one kernelspec for every supported variant.
  --prepull               Run "podman-hpc pull IMAGE" for each installed image.
  --prepull-only          Only run "podman-hpc pull IMAGE"; do not install kernelspecs.
  --podman-hpc COMMAND    podman-hpc command used by --prepull and --prepull-only.
                          Default: ${PODMAN_HPC:-podman-hpc}
  --list-variants         Print supported DISTRO/DESKTOP combinations.
  --force                 Replace an existing kernelspec directory.
  -h, --help              Show this help.
EOF
}

list_variants() {
    cat <<'EOF'
Supported variants:
  debian12      fvwm3  ghcr.io/dingp/vnc-novnc-container:debian-12-main
  debian12      xfce   ghcr.io/dingp/vnc-novnc-container:debian-12-xfce-main
  ubuntu24.04   fvwm3  ghcr.io/dingp/vnc-novnc-container:ubuntu-24.04-fvwm3-main
  ubuntu24.04   xfce   ghcr.io/dingp/vnc-novnc-container:ubuntu-24.04-xfce-main
  ubuntu24.04   xfce-slurm registry.nersc.gov/dseg/novnc:ubuntu24.04-xfce-slurm
  ubuntu        gpu-xfce ghcr.io/dingp/vnc-novnc-container:ubuntu-gpu-xfce-main
  alma9         fvwm3  ghcr.io/dingp/vnc-novnc-container:alma-9-fvwm3-main
  alma9         xfce   ghcr.io/dingp/vnc-novnc-container:alma-9-xfce-main
  opensuse15.6  xfce   ghcr.io/dingp/vnc-novnc-container:opensuse-15.6-main
  opensuse15.6  xfce-slurm registry.nersc.gov/dseg/novnc:opensuse15.6-xfce-slurm
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
    variant_slurm=0
    variant_ssh_proxy=0

    case "${distro}:${desktop}" in
        debian12:fvwm3)
            image="ghcr.io/dingp/vnc-novnc-container:debian-12-main"
            variant_slug="debian12-fvwm3"
            ;;
        debian12:xfce)
            image="ghcr.io/dingp/vnc-novnc-container:debian-12-xfce-main"
            variant_slug="debian12-xfce"
            ;;
        ubuntu24.04:fvwm3)
            image="ghcr.io/dingp/vnc-novnc-container:ubuntu-24.04-fvwm3-main"
            variant_slug="ubuntu24.04-fvwm3"
            ;;
        ubuntu24.04:xfce)
            image="ghcr.io/dingp/vnc-novnc-container:ubuntu-24.04-xfce-main"
            variant_slug="ubuntu24.04-xfce"
            ;;
        ubuntu24.04:xfce-slurm)
            image="registry.nersc.gov/dseg/novnc:ubuntu24.04-xfce-slurm"
            variant_slug="ubuntu24.04-xfce-slurm"
            variant_slurm=1
            variant_ssh_proxy=1
            ;;
        ubuntu:gpu-xfce)
            image="ghcr.io/dingp/vnc-novnc-container:ubuntu-gpu-xfce-main"
            variant_slug="ubuntu-gpu-xfce"
            extra_podman_args=("--gpu")
            ;;
        alma9:fvwm3)
            image="ghcr.io/dingp/vnc-novnc-container:alma-9-fvwm3-main"
            variant_slug="alma9-fvwm3"
            ;;
        alma9:xfce)
            image="ghcr.io/dingp/vnc-novnc-container:alma-9-xfce-main"
            variant_slug="alma9-xfce"
            ;;
        opensuse15.6:xfce)
            image="ghcr.io/dingp/vnc-novnc-container:opensuse-15.6-main"
            variant_slug="opensuse15.6-xfce"
            ;;
        opensuse15.6:xfce-slurm)
            image="registry.nersc.gov/dseg/novnc:opensuse15.6-xfce-slurm"
            variant_slug="opensuse15.6-xfce-slurm"
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
source_wrapper=0
slurm_override=""
ssh_proxy_override=""
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
variant_slurm=0
variant_ssh_proxy=0
scli_server_built=0
ssh_proxy_server_built=0

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

prepull_image() {
    local pull_image="$1"

    if image_already_prepulled "${pull_image}"; then
        return 0
    fi

    printf 'Pre-pulling image: %s\n' "${pull_image}"
    "${podman_hpc}" pull "${pull_image}"
    prepulled_images+=("${pull_image}")
}

build_scli_server() {
    local user_key="${USER:-$(id -u)}"
    local go_cache="${GOCACHE:-${TMPDIR:-/tmp}/vnc-novnc-go-build-cache-${user_key}}"
    local go_mod_cache="${GOMODCACHE:-${TMPDIR:-/tmp}/vnc-novnc-go-mod-cache-${user_key}}"
    local output="${HOME}/bin/scli-server"

    if [[ "${scli_server_built}" -eq 1 ]]; then
        return 0
    fi

    if ! command -v go >/dev/null 2>&1; then
        printf 'go is required to build scli-server for Slurm-enabled kernels.\n' >&2
        printf 'Load or install Go, then rerun this installer.\n' >&2
        exit 1
    fi

    mkdir -p "${HOME}/bin"
    printf 'Building scli-server: %s\n' "${output}"
    (
        cd "${repo_dir}/container/slurm-cli-proxy"
        GOCACHE="${go_cache}" GOMODCACHE="${go_mod_cache}" go build -o "${output}" ./cmd/scli-server
    )
    chmod 0755 "${output}"
    scli_server_built=1
}

build_ssh_proxy_server() {
    local user_key="${USER:-$(id -u)}"
    local go_cache="${GOCACHE:-${TMPDIR:-/tmp}/vnc-novnc-go-build-cache-${user_key}}"
    local go_mod_cache="${GOMODCACHE:-${TMPDIR:-/tmp}/vnc-novnc-go-mod-cache-${user_key}}"
    local output="${HOME}/bin/ssh-proxy-server"

    if [[ "${ssh_proxy_server_built}" -eq 1 ]]; then
        return 0
    fi

    if ! command -v go >/dev/null 2>&1; then
        printf 'go is required to build ssh-proxy-server for SSH proxy-enabled kernels.\n' >&2
        printf 'Load or install Go, then rerun this installer.\n' >&2
        exit 1
    fi

    mkdir -p "${HOME}/bin"
    printf 'Building ssh-proxy-server: %s\n' "${output}"
    (
        cd "${repo_dir}/container/slurm-cli-proxy"
        GOCACHE="${go_cache}" GOMODCACHE="${go_mod_cache}" go build -o "${output}" ./cmd/ssh-proxy-server
    )
    chmod 0755 "${output}"
    ssh_proxy_server_built=1
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
    if [[ -n "${slurm_override}" ]]; then
        variant_slurm="${slurm_override}"
    fi
    if [[ -n "${ssh_proxy_override}" ]]; then
        variant_ssh_proxy="${ssh_proxy_override}"
    fi

    if [[ "${variant_slurm}" -eq 1 ]]; then
        build_scli_server
    fi
    if [[ "${variant_ssh_proxy}" -eq 1 ]]; then
        build_ssh_proxy_server
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

    python3 - "${tmpdir}/${install_kernel_name}/kernel.json" "${tmpdir}/${install_kernel_name}/vnc-novnc.yaml" "${install_display_name}" "${image}" "${variant_slurm}" "${variant_ssh_proxy}" "${display_mode}" "${extra_podman_args[@]}" <<'PY'
import json
import sys

kernel_json, kernel_yaml, display_name, image, slurm_enabled, ssh_proxy_enabled, display_mode = sys.argv[1:8]
extra_podman_args = sys.argv[8:]
pull_policy = "missing"
slurm_volumes = [
    "/global:/global",
    "${SCRATCH}:${SCRATCH}:rw",
    "${CFS}:${CFS}:rw",
    "/opt:/opt",
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
set_yaml_scalar(lines, "slurm", "true" if slurm_enabled == "1" else "false")
set_yaml_scalar(lines, "ssh_proxy", "true" if ssh_proxy_enabled == "1" else "false")
set_yaml_scalar(lines, "display_mode", display_mode)
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
    prepull_image "${image}"
    printf 'Pre-pulled image for %s %s: %s\n' "${distro}" "${desktop}" "${image}"
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

    printf 'Image pre-pull complete.\n'
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
