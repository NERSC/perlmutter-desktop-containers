# Perlmutter environment

This page describes the NERSC environment used by the desktop containers. The
source is released under [BSD-3-Clause-LBNL](../LICENSE).

## Perlmutter scope and prerequisites (November 2026)

This guide describes the Perlmutter and NERSC Jupyter environment as of
**November 2026**. Perlmutter runs SLES 15 SP6; the recommended openSUSE Leap
15.6 image is the closest variant here to that host environment. Start a
Perlmutter JupyterLab server at <https://jupyter.nersc.gov> and use its terminal
for commands in the linked guides. A login-node server is suitable for setup,
desktop interaction, and light work. For GPU access or compute-intensive applications,
start a Jupyter server on an allocated compute node.

GitHub Actions publishes the public images to the
[GHCR package](https://github.com/orgs/NERSC/packages/container/package/perlmutter-desktop-containers)
at `ghcr.io/nersc/perlmutter-desktop-containers` when their inputs change on
`main`. A new Git tag or published release rebuilds every variant under a
versioned tag such as `opensuse-15.6-xfce-slurm-v1.0.0`; a manual workflow run
also rebuilds every variant. The
Perlmutter examples and kernel installer pull them through the
[NERSC Registry pull-through cache](https://docs.nersc.gov/development/containers/registry/#pulling-images-through-the-pull-through-cache)
using `registry.nersc.gov/ghcr.io/nersc/perlmutter-desktop-containers`.
The cache generally gives faster pulls and protects against
upstream outages and rate limits, so it should perform better on Perlmutter
than pulling directly from GHCR. The cache requires a NERSC Registry login on
Perlmutter. If you do not have registry access, request it through
<https://help.nersc.gov>. The installer and kernel launcher fall back to the
public GHCR image if the cached pull fails, including when you have not logged
in or the NERSC Registry is unavailable. For Slurm and host SSH support, the
installer also downloads the tested Linux x86-64 host proxy binaries from the
same GHCR package. It verifies their SHA-256 checksums and installs them in
`${HOME}/bin`; no Go module is needed on Perlmutter.

Current NERSC references: [Perlmutter timeline](https://docs.nersc.gov/systems/perlmutter/timeline/),
[Jupyter server choices](https://docs.nersc.gov/services/jupyter/reference/),
[podman-hpc](https://docs.nersc.gov/development/containers/podman-hpc/overview/),
and [login-node policy](https://docs.nersc.gov/policies/resource-usage/).

The kernel installer's no-argument default is openSUSE Leap 15.6 XFCE Slurm
with Unix noVNC, host-based SSH through the host proxy, and the mounted
Perlmutter programming environment:

```text
registry.nersc.gov/ghcr.io/nersc/perlmutter-desktop-containers:opensuse15.6-xfce-slurm-unix
```

Images include TigerVNC, noVNC, Chromium, D-Bus session helpers, common fonts,
`sshproxy`, a desktop environment, terminal tools, common debugging/networking
tools, and Python `ipykernel` support. The `ubuntu gpu-xfce` variant is based on
NVIDIA CUDA 13.3 with cuDNN development libraries and adds OpenGL runtime
packages for GPU visualization GUIs. The VNC/noVNC helper code is installed in
the container under
`/usr/local/lib/vnc-novnc`; `/opt` is not used so host `/opt` mounts do not hide
it.

Continue with the [Jupyter kernel guide](jupyter.md) or the [manual runner guide](manual-runner.md).
