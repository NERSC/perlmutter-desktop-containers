# Perlmutter desktop containers

Open a graphical desktop in your browser from NERSC JupyterLab on Perlmutter.
The recommended desktop includes a terminal and browser and can use
Perlmutter's job scheduler and SSH setup. These instructions apply to
Perlmutter as of **November 2026**.

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

4. Install the recommended desktop and prepare its container image so the
   first launch is faster:

   ```sh
   scripts/install-jupyter-kernel.sh --prepull --force
   ```

5. Restart JupyterLab. Create a notebook and choose the
   `VNC-opensuse15.6-xfce-slurm` kernel (the desktop launch option). Run a cell,
   then open the desktop link it prints.

## Guides

- [Perlmutter setup and prerequisites](docs/perlmutter.md)
- [Install and use a Jupyter desktop](docs/jupyter.md)
- [Run a desktop directly from a terminal](docs/manual-runner.md)
- [Available desktops and image builds](docs/images.md)
- [How Slurm and SSH work inside the desktop](docs/proxies.md)
