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
                          opensuse15.6: xfce
                          Default: fvwm3
  --name NAME             Kernelspec directory name.
                          Default: vnc-novnc-DISTRO-DESKTOP.
  --display-name NAME     Kernel display name shown in Jupyter.
                          Default: VNC-DISTRO-DESKTOP.
  --prefix DIR            Jupyter prefix. Installs to DIR/share/jupyter/kernels/NAME.
                          Default: ${HOME}/.local
  --no-pip-install        Do not run "python3 -m pip install --user -e .".
  --source-wrapper        Install a wrapper that imports vnc_novnc from this checkout.
  --slurm                 Enable scli socket setup in the generated kernelspec.
                          Automatically enabled for slurm-cli image variants.
  --no-slurm              Disable scli socket setup in the generated kernelspec.
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
  ubuntu24.04   xfce-slurm ghcr.io/dingp/vnc-novnc-container:ubuntu-24.04-xfce-slurm-main
  ubuntu        gpu-xfce ghcr.io/dingp/vnc-novnc-container:ubuntu-gpu-xfce-main
  alma9         fvwm3  ghcr.io/dingp/vnc-novnc-container:alma-9-fvwm3-main
  alma9         xfce   ghcr.io/dingp/vnc-novnc-container:alma-9-xfce-main
  opensuse15.6  xfce   ghcr.io/dingp/vnc-novnc-container:opensuse-15.6-main
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
            image="ghcr.io/dingp/vnc-novnc-container:ubuntu-24.04-xfce-slurm-main"
            variant_slug="ubuntu24.04-xfce-slurm"
            variant_slurm=1
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
prefix="${HOME}/.local"
pip_install=1
source_wrapper=0
slurm_override=""
force=0
all_variants=0
prepull=0
prepull_only=0
podman_hpc="${PODMAN_HPC:-podman-hpc}"
kernel_name_set=0
display_name_set=0
distro_set=0
desktop_set=0
positionals=()
prepulled_images=()
extra_podman_args=()
variant_slurm=0

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

kernel_src="${repo_dir}/kernels/vnc-novnc"

if [[ ! -f "${kernel_src}/kernel.json" ]]; then
    printf 'Missing sample kernelspec: %s\n' "${kernel_src}/kernel.json" >&2
    exit 1
fi

if [[ "${all_variants}" -eq 1 ]]; then
    if [[ "${distro_set}" -eq 1 || "${desktop_set}" -eq 1 || "${kernel_name_set}" -eq 1 || "${display_name_set}" -eq 1 || -n "${slurm_override}" ]]; then
        printf '%s\n' '--all cannot be combined with DISTRO, DESKTOP, --distro, --desktop, --name, --display-name, --slurm, or --no-slurm.' >&2
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

    if [[ "${prepull}" -eq 1 ]]; then
        prepull_image "${image}"
    fi

    if [[ -z "${install_kernel_name}" ]]; then
        install_kernel_name="vnc-novnc-${variant_slug}"
    fi

    if [[ -z "${install_display_name}" ]]; then
        install_display_name="VNC-${distro}-${desktop}"
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

    python3 - "${tmpdir}/${install_kernel_name}/kernel.json" "${tmpdir}/${install_kernel_name}/vnc-novnc.yaml" "${install_display_name}" "${image}" "${variant_slurm}" "${extra_podman_args[@]}" <<'PY'
import json
import sys

kernel_json, kernel_yaml, display_name, image, slurm_enabled = sys.argv[1:6]
extra_podman_args = sys.argv[6:]
pull_policy = "missing"
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
set_yaml_list(lines, "extra_podman_args", extra_podman_args)

with open(kernel_yaml, "w") as handle:
    handle.writelines(lines)
PY

    "${install_python}" - "${tmpdir}/${install_kernel_name}/kernel-wrapper" "${install_python}" "${repo_dir}" "${source_wrapper}" <<'PY'
import shlex
import sys

wrapper_path, python_executable, repo_dir, source_wrapper = sys.argv[1:5]
with open(wrapper_path, "w") as handle:
    handle.write("#!/bin/sh\n")
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
else
    distro="$(canonical_distro "${distro}")"
    desktop="$(canonical_desktop "${desktop}")"
    set_variant_metadata

    if [[ "${kernel_name_set}" -ne 1 ]]; then
        kernel_name="vnc-novnc-${variant_slug}"
    fi

    if [[ "${display_name_set}" -ne 1 ]]; then
        display_name="VNC-${distro}-${desktop}"
    fi

    install_one "${distro}" "${desktop}" "${kernel_name}" "${display_name}"
fi

printf 'To verify visible kernels, run: jupyter kernelspec list\n'
