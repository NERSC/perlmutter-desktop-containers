#!/usr/bin/env python3
"""Run the VNC/noVNC desktop image with safer defaults."""

import argparse
import os
import secrets
import shlex
import string
import subprocess
import sys
import tempfile
import urllib.parse


DEFAULT_IMAGE = "ghcr.io/dingp/vnc-novnc-container:debian-12-main"
DEFAULT_PASSWORD_LENGTH = 8
DEFAULT_NOVNC_PORT = "6080"
DEFAULT_VNC_PORT = "5901"
DEFAULT_JUPYTER_BASE_URL = "https://jupyter.nersc.gov"
DEFAULT_JUPYTER_HOST = "jupyter.nersc.gov"
DEFAULT_JUPYTER_HTTPS_PORT = "443"
LIST_CONFIG_KEYS = ("volume", "mount", "env", "group_add", "extra_podman_args")
BOOL_CONFIG_KEYS = ("expose_vnc", "userns_keep_id", "keep_groups", "dry_run", "slurm")
INT_CONFIG_KEYS = ("password_length",)
VALID_CONFIG_KEYS = set(
    (
        "image",
        "podman_hpc",
        "host_novnc_addr",
        "host_novnc_port",
        "novnc_port",
        "vnc_port",
        "vnc_host_addr",
        "vnc_host_port",
        "password_length",
        "expose_vnc",
        "jupyter_proxy_base_url",
        "jupyter_proxy_host",
        "jupyter_proxy_https_port",
        "jupyter_proxy_prefix",
        "jupyter_proxy_user",
        "jupyter_proxy_server",
        "pull_policy",
        "volume",
        "mount",
        "env",
        "userns",
        "userns_keep_id",
        "group_add",
        "keep_groups",
        "dry_run",
        "extra_podman_args",
        "slurm",
        "slurm_socket",
    )
)


def env_bool(name, default=False):
    value = os.environ.get(name)
    if value is None:
        return default
    return value.lower() in ("1", "true", "yes", "y", "on")


def shell_join(argv):
    return " ".join(shlex.quote(str(arg)) for arg in argv)


def image_inspect_ok(podman_hpc, image):
    return (
        subprocess.call(
            [podman_hpc, "image", "inspect", image],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
        == 0
    )


def prepare_image(podman_hpc, image, pull_policy):
    if not pull_policy or pull_policy == "never":
        return 0

    if pull_policy == "missing" and image_inspect_ok(podman_hpc, image):
        return 0

    print("Pre-pulling image with podman-hpc: {}".format(image), file=sys.stderr, flush=True)
    return subprocess.call([podman_hpc, "pull", image])


def run_pull_policy(pull_policy):
    if not pull_policy:
        return ""
    return "never"


def passwd_field(value, fallback):
    value = value or fallback
    value = value.replace(":", "_").replace("\n", "_")
    return value or fallback


def keep_id_passwd_entry(shell="/bin/bash"):
    uid = os.getuid()
    gid = os.getgid()
    username = passwd_field(
        os.environ.get("USER") or os.environ.get("LOGNAME"),
        "user{}".format(uid),
    )
    home = passwd_field(os.environ.get("HOME"), "/")
    return "{}:x:{}:{}:{}:{}:{}".format(username, uid, gid, username, home, shell)


def add_keep_id_args(run_args):
    run_args.append("--userns=keep-id")
    run_args.extend(["--passwd-entry", keep_id_passwd_entry()])


def default_slurm_socket():
    if os.environ.get("SCLI_SOCKET"):
        return os.environ["SCLI_SOCKET"]
    if os.environ.get("XDG_RUNTIME_DIR"):
        return os.path.join(os.environ["XDG_RUNTIME_DIR"], "scli.sock")
    home = os.environ.get("HOME", "")
    if home:
        return os.path.join(home, ".local", "run", "scli.sock")
    return ""


def add_slurm_proxy_args(run_args, slurm_socket, dry_run=False):
    socket_path = os.path.expandvars(os.path.expanduser(slurm_socket or default_slurm_socket()))
    if not socket_path:
        raise SystemExit("Unable to resolve Slurm CLI proxy socket path.")
    if "$" in socket_path:
        raise SystemExit("Slurm CLI proxy socket contains unresolved variables: {}".format(socket_path))
    if not dry_run and not os.path.exists(socket_path):
        raise SystemExit(
            "Slurm CLI proxy socket does not exist: {}\n"
            "Start scli-server on the host or pass --slurm-socket PATH.".format(socket_path)
        )
    run_args.extend(["-v", "{}:{}:rw".format(socket_path, socket_path)])
    run_args.extend(["-e", "SCLI_SOCKET={}".format(socket_path)])


def strip_yaml_comment(line):
    quote = None
    escaped = False
    for index, char in enumerate(line):
        if escaped:
            escaped = False
            continue
        if char == "\\":
            escaped = True
            continue
        if quote:
            if char == quote:
                quote = None
            continue
        if char in ("'", '"'):
            quote = char
            continue
        if char == "#":
            return line[:index]
    return line


def parse_simple_yaml_scalar(value):
    value = value.strip()
    if not value:
        return ""
    if (value[0] == value[-1]) and value[0] in ("'", '"'):
        return value[1:-1]

    lowered = value.lower()
    if lowered in ("true", "yes", "on"):
        return True
    if lowered in ("false", "no", "off"):
        return False
    if lowered in ("null", "none", "~"):
        return None
    try:
        return int(value)
    except ValueError:
        return value


def load_simple_yaml(path):
    data = {}
    current_key = None

    with open(path) as handle:
        for lineno, raw_line in enumerate(handle, 1):
            line = strip_yaml_comment(raw_line.rstrip("\n")).rstrip()
            if not line.strip():
                continue

            indent = len(line) - len(line.lstrip(" "))
            stripped = line.strip()
            if indent == 0:
                if ":" not in stripped:
                    raise ValueError("{}:{}: expected key: value".format(path, lineno))
                key, value = stripped.split(":", 1)
                key = key.strip().replace("-", "_")
                value = value.strip()
                if not key:
                    raise ValueError("{}:{}: empty key".format(path, lineno))
                if value:
                    data[key] = parse_simple_yaml_scalar(value)
                    current_key = None
                else:
                    data[key] = []
                    current_key = key
                continue

            if not stripped.startswith("- "):
                raise ValueError(
                    "{}:{}: only top-level keys and simple lists are supported without PyYAML".format(
                        path, lineno
                    )
                )
            if current_key is None:
                raise ValueError("{}:{}: list item without a list key".format(path, lineno))
            data[current_key].append(parse_simple_yaml_scalar(stripped[2:].strip()))

    return data


def load_yaml_config(path):
    if not path:
        return {}
    if not os.path.exists(path):
        raise ValueError("Configuration file does not exist: {}".format(path))

    try:
        import yaml
    except ImportError:
        data = load_simple_yaml(path)
    else:
        with open(path) as handle:
            data = yaml.safe_load(handle) or {}

    if not isinstance(data, dict):
        raise ValueError("Configuration file must contain a YAML mapping: {}".format(path))

    normalized = {}
    for key, value in data.items():
        normalized[str(key).replace("-", "_")] = value
    return normalized


def expand_config_value(value):
    if isinstance(value, str):
        return os.path.expandvars(os.path.expanduser(value))
    if isinstance(value, list):
        return [expand_config_value(item) for item in value]
    return value


def normalize_list_value(key, value):
    if value is None:
        return []
    if isinstance(value, list):
        return [str(expand_config_value(item)) for item in value]
    if isinstance(value, tuple):
        return [str(expand_config_value(item)) for item in value]
    if isinstance(value, str):
        return [str(expand_config_value(value))]
    raise ValueError("Configuration key '{}' must be a list or string".format(key))


def normalize_bool_value(key, value):
    if isinstance(value, bool):
        return value
    if isinstance(value, str):
        lowered = value.lower()
        if lowered in ("1", "true", "yes", "y", "on"):
            return True
        if lowered in ("0", "false", "no", "n", "off"):
            return False
    raise ValueError("Configuration key '{}' must be true or false".format(key))


def normalize_config(config):
    unknown = sorted(set(config) - VALID_CONFIG_KEYS)
    if unknown:
        raise ValueError("Unknown configuration key(s): {}".format(", ".join(unknown)))

    normalized = {}
    for key, value in config.items():
        if key in LIST_CONFIG_KEYS:
            normalized[key] = normalize_list_value(key, value)
        elif key in BOOL_CONFIG_KEYS:
            normalized[key] = normalize_bool_value(key, value)
        elif key in INT_CONFIG_KEYS:
            normalized[key] = int(value)
        elif value is None:
            normalized[key] = ""
        else:
            normalized[key] = str(expand_config_value(value))
    return normalized


def build_defaults(config):
    defaults = {
        "image": DEFAULT_IMAGE,
        "podman_hpc": "podman-hpc",
        "host_novnc_addr": "127.0.0.1",
        "host_novnc_port": "",
        "novnc_port": DEFAULT_NOVNC_PORT,
        "vnc_port": DEFAULT_VNC_PORT,
        "vnc_host_addr": "127.0.0.1",
        "vnc_host_port": DEFAULT_VNC_PORT,
        "password_length": DEFAULT_PASSWORD_LENGTH,
        "expose_vnc": False,
        "jupyter_proxy_base_url": DEFAULT_JUPYTER_BASE_URL,
        "jupyter_proxy_host": DEFAULT_JUPYTER_HOST,
        "jupyter_proxy_https_port": DEFAULT_JUPYTER_HTTPS_PORT,
        "jupyter_proxy_prefix": "",
        "jupyter_proxy_user": os.environ.get("USER", ""),
        "jupyter_proxy_server": "",
        "pull_policy": "missing",
        "volume": [],
        "mount": [],
        "env": [],
        "userns": "",
        "userns_keep_id": False,
        "group_add": [],
        "keep_groups": False,
        "dry_run": False,
        "extra_podman_args": [],
        "slurm": False,
        "slurm_socket": "",
    }
    defaults.update(config)

    env_defaults = {
        "image": os.environ.get("IMAGE"),
        "podman_hpc": os.environ.get("PODMAN_HPC"),
        "host_novnc_addr": os.environ.get("HOST_NOVNC_ADDR"),
        "host_novnc_port": os.environ.get("HOST_NOVNC_PORT"),
        "novnc_port": os.environ.get("NOVNC_PORT"),
        "vnc_port": os.environ.get("VNC_PORT"),
        "vnc_host_addr": os.environ.get("VNC_HOST_ADDR"),
        "vnc_host_port": os.environ.get("VNC_HOST_PORT", os.environ.get("VNC_PORT")),
        "jupyter_proxy_base_url": os.environ.get("JUPYTER_PROXY_BASE_URL"),
        "jupyter_proxy_host": os.environ.get("JUPYTER_PROXY_HOST"),
        "jupyter_proxy_https_port": os.environ.get("JUPYTER_PROXY_HTTPS_PORT"),
        "jupyter_proxy_prefix": os.environ.get(
            "JUPYTER_PROXY_PREFIX", os.environ.get("JUPYTERHUB_SERVICE_PREFIX")
        ),
        "jupyter_proxy_user": os.environ.get("JUPYTER_PROXY_USER"),
        "jupyter_proxy_server": os.environ.get("JUPYTER_PROXY_SERVER"),
        "pull_policy": os.environ.get("PODMAN_PULL_POLICY"),
        "userns": os.environ.get("PODMAN_USERNS"),
        "slurm_socket": os.environ.get("SCLI_SOCKET"),
    }
    for key, value in env_defaults.items():
        if value is not None:
            defaults[key] = value

    if "VNC_PASSWORD_LENGTH" in os.environ:
        defaults["password_length"] = int(os.environ["VNC_PASSWORD_LENGTH"])
    if "EXPOSE_VNC" in os.environ:
        defaults["expose_vnc"] = env_bool("EXPOSE_VNC", defaults["expose_vnc"])
    if "VNC_NOVNC_SLURM" in os.environ:
        defaults["slurm"] = env_bool("VNC_NOVNC_SLURM", defaults["slurm"])

    if not defaults["vnc_host_port"]:
        defaults["vnc_host_port"] = defaults["vnc_port"]

    if defaults["pull_policy"] not in ("", "always", "missing", "never", "newer"):
        raise ValueError(
            "pull_policy must be one of: always, missing, never, newer"
        )

    return defaults


def random_port():
    return str(secrets.randbelow(11848) + 49152)


def random_password(length):
    alphabet = string.ascii_letters + string.digits
    return "".join(secrets.choice(alphabet) for _ in range(length))


def jupyter_proxy_url(args, host_novnc_port):
    prefix = args.jupyter_proxy_prefix

    if not prefix:
        if not args.jupyter_proxy_user or not args.jupyter_proxy_server:
            return None
        prefix = "user/{}/{}".format(args.jupyter_proxy_user, args.jupyter_proxy_server)

    prefix = prefix.strip("/")
    proxy_path = "{}/proxy/{}".format(prefix, host_novnc_port)
    encoded_path = urllib.parse.quote(proxy_path, safe="")
    base_url = args.jupyter_proxy_base_url.rstrip("/")

    return "{}{}/vnc.html?port={}&host={}&path={}".format(
        base_url + "/",
        proxy_path,
        args.jupyter_proxy_https_port,
        args.jupyter_proxy_host,
        encoded_path,
    )


def add_podman_run_args(args, password_file):
    host_novnc_port = args.host_novnc_port or random_port()

    run_args = [
        args.podman_hpc,
        "run",
        "--rm",
        "-p",
        "{}:{}:{}".format(args.host_novnc_addr, host_novnc_port, args.novnc_port),
        "-v",
        "{}:/run/secrets/vnc-password:ro".format(password_file),
        "-e",
        "VNC_PASSWORD_PLAIN_FILE=/run/secrets/vnc-password",
        "-e",
        "VNC_PASSWORD_FILE=/tmp/vnc-auth/passwd",
        "-e",
        "NOVNC_PORT={}".format(args.novnc_port),
        "-e",
        "VNC_PORT={}".format(args.vnc_port),
    ]

    run_policy = run_pull_policy(args.pull_policy)
    if run_policy:
        run_args.append("--pull={}".format(run_policy))

    if args.expose_vnc:
        run_args.extend(
            [
                "-p",
                "{}:{}:{}".format(args.vnc_host_addr, args.vnc_host_port, args.vnc_port),
            ]
        )

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

    for volume in args.volume:
        run_args.extend(["-v", volume])

    for mount in args.mount:
        run_args.extend(["--mount", mount])

    for env in args.env:
        run_args.extend(["-e", env])

    if args.slurm:
        add_slurm_proxy_args(run_args, args.slurm_socket, args.dry_run)

    extra_args = args.extra_podman_args
    if extra_args and extra_args[0] == "--":
        extra_args = extra_args[1:]
    run_args.extend(extra_args)

    run_args.append(args.image)
    return host_novnc_port, run_args


def print_access_details(args, host_novnc_port, vnc_password):
    access_url = jupyter_proxy_url(args, host_novnc_port)

    print("Image: {}".format(args.image))
    if access_url:
        print("noVNC: {}".format(access_url))
    else:
        print(
            "noVNC: http://{}:{}/vnc.html".format(
                args.host_novnc_addr, host_novnc_port
            )
        )
        print(
            "Set JUPYTER_PROXY_PREFIX, or set JUPYTER_PROXY_USER and "
            "JUPYTER_PROXY_SERVER, to print a jupyter.nersc.gov proxy URL."
        )

    print("One-time VNC password: {}".format(vnc_password))
    if args.expose_vnc:
        print("VNC: {}:{}".format(args.vnc_host_addr, args.vnc_host_port))
    else:
        print("VNC server port is not exposed on the host.")
    print("")


def parse_args(argv):
    config_parser = argparse.ArgumentParser(add_help=False)
    config_parser.add_argument(
        "--config",
        default=os.environ.get("VNC_NOVNC_CONFIG", ""),
        help="YAML configuration file with defaults for this helper.",
    )
    config_args, remaining_argv = config_parser.parse_known_args(argv)
    try:
        config = normalize_config(load_yaml_config(config_args.config))
        defaults = build_defaults(config)
    except (OSError, ValueError) as exc:
        raise SystemExit("Configuration error: {}".format(exc))

    parser = argparse.ArgumentParser(
        description="Run the Debian VNC/noVNC desktop image with a generated one-time VNC password.",
        epilog="Additional podman-hpc arguments may be passed after --.",
        parents=[config_parser],
    )

    parser.add_argument("--image", default=defaults["image"])
    parser.add_argument("--podman-hpc", default=defaults["podman_hpc"])
    parser.add_argument("--host-novnc-addr", default=defaults["host_novnc_addr"])
    parser.add_argument("--host-novnc-port", default=defaults["host_novnc_port"])
    parser.add_argument("--novnc-port", default=defaults["novnc_port"])
    parser.add_argument("--vnc-port", default=defaults["vnc_port"])
    parser.add_argument("--vnc-host-addr", default=defaults["vnc_host_addr"])
    parser.add_argument(
        "--vnc-host-port",
        default=defaults["vnc_host_port"],
    )
    parser.add_argument(
        "--password-length",
        type=int,
        default=defaults["password_length"],
    )

    parser.add_argument("--expose-vnc", action="store_true", default=defaults["expose_vnc"])
    parser.add_argument("--no-expose-vnc", action="store_false", dest="expose_vnc")

    parser.add_argument("--jupyter-proxy-base-url", default=defaults["jupyter_proxy_base_url"])
    parser.add_argument("--jupyter-proxy-host", default=defaults["jupyter_proxy_host"])
    parser.add_argument(
        "--jupyter-proxy-https-port",
        default=defaults["jupyter_proxy_https_port"],
    )
    parser.add_argument(
        "--jupyter-proxy-prefix",
        default=defaults["jupyter_proxy_prefix"],
    )
    parser.add_argument("--jupyter-proxy-user", default=defaults["jupyter_proxy_user"])
    parser.add_argument("--jupyter-proxy-server", default=defaults["jupyter_proxy_server"])
    parser.add_argument(
        "--pull-policy",
        choices=("always", "missing", "never", "newer"),
        default=defaults["pull_policy"],
        help="Image pull policy passed to podman-hpc run as --pull=POLICY.",
    )

    parser.add_argument(
        "-v",
        "--volume",
        action="append",
        default=list(defaults["volume"]),
        help="Bind mount or volume spec passed to podman-hpc, for example /host/path:/container/path:ro. May be repeated.",
    )
    parser.add_argument(
        "--mount",
        action="append",
        default=list(defaults["mount"]),
        help="Podman --mount spec passed through to podman-hpc. May be repeated.",
    )
    parser.add_argument(
        "-e",
        "--env",
        action="append",
        default=list(defaults["env"]),
        help="Environment variable passed to podman-hpc, either NAME or NAME=VALUE. May be repeated.",
    )
    parser.add_argument("--userns", default=defaults["userns"])
    parser.add_argument("--userns-keep-id", action="store_true", default=defaults["userns_keep_id"])
    parser.add_argument("--group-add", action="append", default=list(defaults["group_add"]))
    parser.add_argument("--keep-groups", action="store_true", default=defaults["keep_groups"])
    parser.add_argument("--slurm", action="store_true", default=defaults["slurm"], help="Mount an scli-server Unix socket and set SCLI_SOCKET inside the container.")
    parser.add_argument("--no-slurm", action="store_false", dest="slurm")
    parser.add_argument("--slurm-socket", default=defaults["slurm_socket"], help="Path to the host scli-server Unix socket. Default: SCLI_SOCKET, XDG_RUNTIME_DIR/scli.sock, or ~/.local/run/scli.sock.")
    parser.add_argument("--dry-run", action="store_true", default=defaults["dry_run"], help="Print the generated command without running podman-hpc.")
    parser.add_argument("extra_podman_args", nargs=argparse.REMAINDER, default=list(defaults["extra_podman_args"]))

    args = parser.parse_args(remaining_argv)
    if not args.extra_podman_args:
        args.extra_podman_args = list(defaults["extra_podman_args"])
    if args.password_length < 1:
        parser.error("--password-length must be positive")
    return args


def main(argv=None):
    if argv is None:
        argv = sys.argv[1:]
    args = parse_args(argv)

    with tempfile.TemporaryDirectory() as tmpdir:
        password_file = os.path.join(tmpdir, "vnc-password")
        vnc_password = random_password(args.password_length)
        with open(password_file, "w") as handle:
            handle.write(vnc_password + "\n")
        os.chmod(password_file, 0o600)

        host_novnc_port, run_args = add_podman_run_args(args, password_file)
        print_access_details(args, host_novnc_port, vnc_password)

        if args.dry_run:
            print("Command:")
            print(shell_join(run_args))
            return 0

        pull_rc = prepare_image(args.podman_hpc, args.image, args.pull_policy)
        if pull_rc != 0:
            return pull_rc

        return subprocess.call(run_args)


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
