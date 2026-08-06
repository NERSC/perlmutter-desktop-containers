"""Jupyter kernel provisioners for VNC/noVNC kernels."""

import os

from jupyter_client.provisioning.local_provisioner import LocalProvisioner

from .runner import socket_hostname


class VncNovncIpcProvisioner(LocalProvisioner):
    """Run the local kernel provisioner with IPC connection files.

    Jupyter writes the connection file before the kernelspec wrapper starts.
    Setting the parent KernelManager to IPC here keeps the host-side connection
    info and the in-container ipykernel connection file in sync without host
    TCP port mappings or host networking.
    """

    async def pre_launch(self, **kwargs):
        km = self.parent
        if km:
            runtime_dir = os.path.join(
                "/tmp",
                "vnc-novnc-{}".format(os.getuid()),
                "jupyter-{}-{}".format(socket_hostname(), self.kernel_id),
            )
            os.makedirs(runtime_dir, mode=0o700, exist_ok=True)
            try:
                os.chmod(runtime_dir, 0o700)
            except OSError:
                pass

            km.transport = "ipc"
            km.ip = os.path.join(runtime_dir, "kernel")

        return await super().pre_launch(**kwargs)
