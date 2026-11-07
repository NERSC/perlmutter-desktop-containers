# Perlmutter Desktop Containers (VNC/noVNC)

Run a desktop in NERSC JupyterLab on Perlmutter. These instructions apply to
the Perlmutter environment as of **November 2026**.

## Quick start

1. Start a **Perlmutter** JupyterLab server at <https://jupyter.nersc.gov> and
   open a terminal. Use a compute-node server for GPU or compute-intensive work.

2. Clone the repository and load Python:

   ```sh
   cd "${HOME}"
   git clone https://github.com/nersc/perlmutter-desktop-containers.git
   cd perlmutter-desktop-containers
   module load python
   ```

3. If you have NERSC Registry access, log in to use its pull-through cache. The
   installer falls back to GHCR when the cache cannot be used.

   ```sh
   podman-hpc login registry.nersc.gov
   ```

4. Install and pre-pull the default openSUSE Leap 15.6 XFCE Slurm kernel, with
   Unix noVNC, host SSH, and the Perlmutter programming environment:

   ```sh
   scripts/install-jupyter-kernel.sh --prepull --force
   ```

5. Restart JupyterLab, create a notebook with the
   `VNC-opensuse15.6-xfce-slurm` kernel, run its first cell, and open the noVNC
   URL it prints.

## Guides

- [Perlmutter scope and prerequisites](docs/perlmutter.md)
- [Jupyter kernel setup and behavior](docs/jupyter.md)
- [Manual desktop runner, TCP default, and optional Unix socket](docs/manual-runner.md)
- [Image variants and builds](docs/images.md)
- [Slurm and host SSH proxies](docs/proxies.md)
