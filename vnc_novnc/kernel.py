"""Kernel wrapper for running the VNC/noVNC image with podman-hpc."""

import argparse
import os
import signal
import socket
import subprocess
import sys
import tempfile
import time
from types import SimpleNamespace

from .runner import (
    DEFAULT_IMAGE,
    DEFAULT_NOVNC_PORT,
    DEFAULT_NOVNC_TRANSPORT,
    DEFAULT_PASSWORD_LENGTH,
    DEFAULT_VNC_PORT,
    DEFAULT_JUPYTER_PROXY_SERVICE,
    add_novnc_unix_socket_args,
    add_ssh_proxy_args,
    add_slurm_proxy_args,
    build_defaults,
    add_keep_id_args,
    keep_id_passwd_entry,
    jupyter_proxy_url,
    jupyter_proxy_service_url,
    load_yaml_config,
    normalize_config,
    prepare_image,
    random_password,
    run_pull_policy,
    shell_join,
)


DEFAULT_PASSTHROUGH_ENVS = (
    "USER",
    "HOME",
    "SCRATCH",
    "CFS",
    "JUPYTERHUB_SERVICE_PREFIX",
    "JUPYTER_PROXY_BASE_URL",
    "JUPYTER_PROXY_HOST",
    "JUPYTER_PROXY_HTTPS_PORT",
    "JUPYTER_PROXY_PREFIX",
    "JUPYTER_PROXY_USER",
    "JUPYTER_PROXY_SERVER",
)


class ShutdownRequested(Exception):
    def __init__(self, signum):
        super().__init__("shutdown requested by signal {}".format(signum))
        self.signum = signum


def available_tcp_port(host):
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as sock:
        sock.bind((host, 0))
        return str(sock.getsockname()[1])


def safe_container_name():
    user = os.environ.get("USER", "user")
    safe_user = "".join(ch if ch.isalnum() or ch in "_.-" else "-" for ch in user)
    suffix = random_password(8).lower()
    return "vnc-novnc-{}-{}-{}".format(safe_user, os.getpid(), suffix)


def volume_container_path(volume):
    parts = volume.split(":", 2)
    if len(parts) < 2:
        return ""
    return parts[1]


def add_volume_args(run_args, volumes, skip_container_paths):
    seen = set()
    for volume in volumes:
        if "$" in volume:
            print("Skipping unresolved volume spec: {}".format(volume), file=sys.stderr)
            continue
        container_path = volume_container_path(volume)
        if container_path in skip_container_paths:
            continue
        if volume in seen:
            continue
        seen.add(volume)
        run_args.extend(["-v", volume])


def load_defaults(config_path):
    try:
        config = normalize_config(load_yaml_config(config_path))
        return build_defaults(config)
    except (OSError, ValueError) as exc:
        raise SystemExit("Configuration error: {}".format(exc))


def build_parser(defaults):
    parser = argparse.ArgumentParser(
        description="Run the VNC/noVNC image as a Jupyter kernel with podman-hpc.",
        epilog="Kernel arguments are normally supplied by Jupyter as -f {connection_file}.",
    )
    parser.add_argument(
        "--config",
        default=os.environ.get("VNC_NOVNC_CONFIG", ""),
        help="YAML configuration file with defaults for the podman-hpc launch.",
    )
    parser.add_argument("--image", default=defaults["image"])
    parser.add_argument("--podman-hpc", default=defaults["podman_hpc"])
    parser.add_argument("--host-novnc-addr", default=defaults["host_novnc_addr"])
    parser.add_argument("--host-novnc-port", default=defaults["host_novnc_port"])
    parser.add_argument("--novnc-port", default=defaults["novnc_port"])
    parser.add_argument(
        "--novnc-transport",
        choices=("tcp", "unix"),
        default=defaults.get("novnc_transport", DEFAULT_NOVNC_TRANSPORT),
    )
    parser.add_argument("--novnc-socket", default=defaults.get("novnc_socket", ""))
    parser.add_argument("--vnc-port", default=defaults["vnc_port"])
    parser.add_argument("--password-length", type=int, default=defaults["password_length"])
    parser.add_argument("--jupyter-proxy-base-url", default=defaults["jupyter_proxy_base_url"])
    parser.add_argument("--jupyter-proxy-host", default=defaults["jupyter_proxy_host"])
    parser.add_argument(
        "--jupyter-proxy-https-port",
        default=defaults["jupyter_proxy_https_port"],
    )
    parser.add_argument("--jupyter-proxy-prefix", default=defaults["jupyter_proxy_prefix"])
    parser.add_argument("--jupyter-proxy-user", default=defaults["jupyter_proxy_user"])
    parser.add_argument("--jupyter-proxy-server", default=defaults["jupyter_proxy_server"])
    parser.add_argument(
        "--jupyter-proxy-service",
        default=defaults.get("jupyter_proxy_service", DEFAULT_JUPYTER_PROXY_SERVICE),
    )
    parser.add_argument(
        "--pull-policy",
        choices=("always", "missing", "never", "newer"),
        default=defaults["pull_policy"],
        help="Image pull policy passed to podman-hpc run as --pull=POLICY.",
    )
    parser.add_argument(
        "--gpu",
        action="store_true",
        default=defaults["gpu"],
        help="Pass --gpu to podman-hpc so host GPUs are available in the container.",
    )
    parser.add_argument("--no-gpu", action="store_false", dest="gpu")
    parser.add_argument("-v", "--volume", action="append", default=list(defaults["volume"]))
    parser.add_argument("--mount", action="append", default=list(defaults["mount"]))
    parser.add_argument("-e", "--env", action="append", default=list(defaults["env"]))
    parser.add_argument("--userns", default=defaults["userns"])
    parser.add_argument("--userns-keep-id", action="store_true", default=defaults["userns_keep_id"])
    parser.add_argument("--group-add", action="append", default=list(defaults["group_add"]))
    parser.add_argument("--keep-groups", action="store_true", default=defaults["keep_groups"])
    parser.add_argument(
        "--slurm",
        action="store_true",
        default=defaults["slurm"],
        help="Mount an scli-server Unix socket and set SCLI_SOCKET inside the container.",
    )
    parser.add_argument("--no-slurm", action="store_false", dest="slurm")
    parser.add_argument(
        "--slurm-socket",
        default=defaults["slurm_socket"],
        help="Path to the host scli-server Unix socket.",
    )
    parser.add_argument(
        "--slurm-server",
        default=defaults["slurm_server"],
        help="Path to host scli-server.",
    )
    parser.add_argument(
        "--slurm-server-log",
        default=defaults["slurm_server_log"],
        help="Path to the host scli-server startup log.",
    )
    parser.add_argument(
        "--ssh-proxy",
        action="store_true",
        default=defaults["ssh_proxy"],
        help="Mount an ssh-proxy-server Unix socket and set SSH_PROXY_SOCKET inside the container.",
    )
    parser.add_argument("--no-ssh-proxy", action="store_false", dest="ssh_proxy")
    parser.add_argument(
        "--ssh-proxy-socket",
        default=defaults["ssh_proxy_socket"],
        help="Path to the host ssh-proxy-server Unix socket.",
    )
    parser.add_argument(
        "--ssh-proxy-server",
        default=defaults["ssh_proxy_server"],
        help="Path to host ssh-proxy-server.",
    )
    parser.add_argument(
        "--ssh-proxy-server-log",
        default=defaults["ssh_proxy_server_log"],
        help="Path to the host ssh-proxy-server startup log.",
    )
    parser.add_argument("--dry-run", action="store_true", default=defaults["dry_run"])
    parser.add_argument("-f", "--connection-file", default="")
    parser.add_argument("kernel_args", nargs=argparse.REMAINDER)
    return parser


def parse_args(argv):
    config_parser = argparse.ArgumentParser(add_help=False)
    config_parser.add_argument("--config", default=os.environ.get("VNC_NOVNC_CONFIG", ""))
    config_args, _ = config_parser.parse_known_args(argv)
    defaults = load_defaults(config_args.config)
    args = build_parser(defaults).parse_args(argv)
    args.extra_podman_args = list(defaults["extra_podman_args"])
    if not args.jupyter_proxy_service or "/" in args.jupyter_proxy_service:
        raise SystemExit("--jupyter-proxy-service must be non-empty and must not contain '/'")
    return args


def kernel_args(args):
    command = ["python3", "-m", "ipykernel_launcher"]
    if args.connection_file:
        command.extend(["-f", args.connection_file])
    passed = list(args.kernel_args)
    if passed and passed[0] == "--":
        passed = passed[1:]
    command.extend(passed)
    return command


def build_podman_args(args, password_file, access_url, host_novnc_port, container_name):
    run_args = [
        args.podman_hpc,
        "run",
        "--rm",
        "--jupyter",
        "--name",
        container_name,
        "--workdir",
        os.getcwd(),
        "-v",
        "{}:/run/secrets/vnc-password:ro".format(password_file),
        "-e",
        "VNC_PASSWORD_PLAIN_FILE=/run/secrets/vnc-password",
        "-e",
        "VNC_PASSWORD_FILE=/tmp/vnc-auth/passwd",
        "-e",
        "VNC_NOVNC_PASSWORD_FILE=/run/secrets/vnc-password",
        "-e",
        "VNC_NOVNC_ACCESS_URL={}".format(access_url),
        "-e",
        "VNC_NOVNC_HOST_ADDR={}".format(args.host_novnc_addr),
        "-e",
        "VNC_NOVNC_HOST_PORT={}".format(host_novnc_port),
        "-e",
        "VNC_NOVNC_IMAGE={}".format(args.image),
        "-e",
        "NOVNC_PORT={}".format(args.novnc_port),
        "-e",
        "VNC_PORT={}".format(args.vnc_port),
    ]
    if args.novnc_transport == "tcp":
        run_args.extend(
            [
                "-p",
                "{}:{}:{}".format(args.host_novnc_addr, host_novnc_port, args.novnc_port),
            ]
        )
    else:
        add_novnc_unix_socket_args(
            run_args,
            args.novnc_socket,
            dry_run=args.dry_run,
            volumes=["/tmp:/tmp"] + list(args.volume),
            mounts=args.mount,
            implicit_same_path_mounts=("/tmp", os.environ.get("HOME", "")),
        )

    run_policy = run_pull_policy(args.pull_policy)
    if run_policy:
        run_args.append("--pull={}".format(run_policy))

    if args.gpu:
        run_args.append("--gpu")

    if args.userns_keep_id:
        add_keep_id_args(run_args)
    elif args.userns:
        run_args.append("--userns={}".format(args.userns))
        if args.userns == "keep-id":
            run_args.extend(["--passwd-entry", keep_id_passwd_entry()])

    group_add = list(args.group_add)
    if args.keep_groups and "keep-groups" not in group_add:
        group_add.append("keep-groups")
    for group in group_add:
        run_args.append("--group-add={}".format(group))

    for env_name in DEFAULT_PASSTHROUGH_ENVS:
        if env_name in os.environ:
            run_args.extend(["-e", env_name])
    for env_spec in args.env:
        run_args.extend(["-e", env_spec])

    skip_paths = set(("/tmp", os.environ.get("HOME", "")))
    add_volume_args(run_args, args.volume, skip_paths)

    for mount in args.mount:
        run_args.extend(["--mount", mount])

    if args.slurm:
        slurm_visible_volumes = ["/tmp:/tmp"] + list(args.volume)
        add_slurm_proxy_args(
            run_args,
            args.slurm_socket,
            args.dry_run,
            args.slurm_server,
            args.slurm_server_log,
            volumes=slurm_visible_volumes,
            mounts=args.mount,
        )

    if args.ssh_proxy:
        ssh_proxy_visible_volumes = ["/tmp:/tmp"] + list(args.volume)
        add_ssh_proxy_args(
            run_args,
            args.ssh_proxy_socket,
            args.dry_run,
            args.ssh_proxy_server,
            args.ssh_proxy_server_log,
            volumes=ssh_proxy_visible_volumes,
            mounts=args.mount,
        )

    extra_args = list(getattr(args, "extra_podman_args", []))
    if extra_args and extra_args[0] == "--":
        extra_args = extra_args[1:]
    run_args.extend(extra_args)

    run_args.append(args.image)
    run_args.extend(["vnc-novnc-jupyter-kernel"])
    run_args.extend(kernel_args(args))
    return run_args


def print_connection(access_url, password, host_novnc_port, novnc_transport):
    print("VNC/noVNC container kernel", file=sys.stderr)
    print("noVNC: {}".format(access_url), file=sys.stderr)
    print("One-time VNC password: {}".format(password), file=sys.stderr)
    if novnc_transport == "tcp":
        print("Host noVNC port: {}".format(host_novnc_port), file=sys.stderr)
    else:
        print("noVNC transport: Unix socket", file=sys.stderr)


def terminate_process_group(process, timeout=10):
    if process.poll() is not None:
        return
    try:
        os.killpg(process.pid, signal.SIGTERM)
    except OSError:
        process.terminate()
    deadline = time.time() + timeout
    while process.poll() is None and time.time() < deadline:
        time.sleep(0.1)
    if process.poll() is None:
        try:
            os.killpg(process.pid, signal.SIGKILL)
        except OSError:
            process.kill()


def cleanup_container(podman_hpc, container_name):
    for command in (
        [podman_hpc, "stop", "--time", "10", container_name],
        [podman_hpc, "rm", "--force", container_name],
    ):
        subprocess.call(
            command,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )


def run_podman_kernel(run_args, podman_hpc, container_name):
    handled_signals = [
        signum
        for signum in (
            signal.SIGINT,
            signal.SIGTERM,
            getattr(signal, "SIGHUP", None),
        )
        if signum is not None
    ]
    previous_handlers = {}

    def request_shutdown(signum, frame):
        raise ShutdownRequested(signum)

    for signum in handled_signals:
        previous_handlers[signum] = signal.getsignal(signum)
        signal.signal(signum, request_shutdown)

    process = subprocess.Popen(run_args, start_new_session=True)
    try:
        return process.wait()
    except ShutdownRequested as exc:
        cleanup_container(podman_hpc, container_name)
        terminate_process_group(process)
        return 128 + exc.signum
    finally:
        if process.poll() is None:
            cleanup_container(podman_hpc, container_name)
            terminate_process_group(process)
        for signum, handler in previous_handlers.items():
            signal.signal(signum, handler)


def main(argv=None):
    if argv is None:
        argv = sys.argv[1:]
    args = parse_args(argv)

    proxy_args = SimpleNamespace(
        jupyter_proxy_prefix=args.jupyter_proxy_prefix,
        jupyter_proxy_user=args.jupyter_proxy_user,
        jupyter_proxy_server=args.jupyter_proxy_server,
        jupyter_proxy_base_url=args.jupyter_proxy_base_url,
        jupyter_proxy_https_port=args.jupyter_proxy_https_port,
        jupyter_proxy_host=args.jupyter_proxy_host,
    )
    host_novnc_port = ""
    if args.novnc_transport == "tcp":
        host_novnc_port = args.host_novnc_port or available_tcp_port(args.host_novnc_addr)
        access_url = jupyter_proxy_url(proxy_args, host_novnc_port)
    else:
        access_url = jupyter_proxy_service_url(proxy_args, args.jupyter_proxy_service)
    if not access_url:
        if args.novnc_transport == "tcp":
            access_url = "http://{}:{}/vnc.html".format(args.host_novnc_addr, host_novnc_port)
        else:
            access_url = "/{}/vnc.html".format(args.jupyter_proxy_service.strip("/"))

    with tempfile.TemporaryDirectory() as tmpdir:
        password_file = os.path.join(tmpdir, "vnc-password")
        password = random_password(args.password_length)
        with open(password_file, "w") as handle:
            handle.write(password + "\n")
        os.chmod(password_file, 0o600)

        container_name = safe_container_name()
        run_args = build_podman_args(
            args,
            password_file,
            access_url,
            host_novnc_port,
            container_name,
        )
        print_connection(access_url, password, host_novnc_port, args.novnc_transport)

        if args.dry_run:
            print(shell_join(run_args))
            return 0

        pull_rc = prepare_image(args.podman_hpc, args.image, args.pull_policy)
        if pull_rc != 0:
            return pull_rc

        return run_podman_kernel(run_args, args.podman_hpc, container_name)


if __name__ == "__main__":
    raise SystemExit(main())
