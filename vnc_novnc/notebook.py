"""Notebook-facing helpers for the VNC/noVNC container kernel."""

import os


def _read_first_line(path):
    if not path:
        return ""
    try:
        with open(path) as handle:
            return handle.readline().rstrip("\n")
    except OSError:
        return ""


def connection_info():
    """Return the noVNC connection details exported by the kernel wrapper."""

    password = os.environ.get("VNC_NOVNC_PASSWORD", "")
    if not password:
        password = _read_first_line(os.environ.get("VNC_NOVNC_PASSWORD_FILE", ""))

    return {
        "url": os.environ.get("VNC_NOVNC_ACCESS_URL", ""),
        "password": password,
        "host_port": os.environ.get("VNC_NOVNC_HOST_PORT", ""),
        "host_addr": os.environ.get("VNC_NOVNC_HOST_ADDR", ""),
        "image": os.environ.get("VNC_NOVNC_IMAGE", ""),
    }


def display_connection():
    """Display noVNC connection details in a notebook and return them as a dict."""

    info = connection_info()
    try:
        from IPython.display import HTML, display
    except ImportError:
        print("noVNC: {}".format(info["url"] or "(not set)"))
        print("One-time VNC password: {}".format(info["password"] or "(not set)"))
        return info

    if info["url"]:
        url_html = '<a href="{0}" target="_blank" rel="noopener noreferrer">{0}</a>'.format(
            info["url"]
        )
    else:
        url_html = "(not set)"

    password_html = info["password"] or "(not set)"
    display(
        HTML(
            "<div>"
            "<p><strong>noVNC:</strong> {}</p>"
            "<p><strong>One-time VNC password:</strong> <code>{}</code></p>"
            "</div>".format(url_html, password_html)
        )
    )
    return info


def install_auto_display():
    """Display noVNC connection details once, attached to the next executed cell."""

    try:
        from IPython import get_ipython
    except ImportError:
        return False

    shell = get_ipython()
    if shell is None:
        return False

    state = {"shown": False}

    def _show_once(*args, **kwargs):
        if state["shown"]:
            return
        state["shown"] = True
        try:
            shell.events.unregister("pre_run_cell", _show_once)
        except ValueError:
            pass
        display_connection()

    shell.events.register("pre_run_cell", _show_once)
    return True
