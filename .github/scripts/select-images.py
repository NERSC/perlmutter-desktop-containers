#!/usr/bin/env python3
"""Select published desktop images affected by a GitHub event."""

from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
import subprocess


ROOT = Path(__file__).resolve().parents[2]
MATRIX_FILE = ROOT / ".github/image-matrix.json"
# Files copied by every published Dockerfile, plus files that define its build.
SHARED_FILES = {
    ".dockerignore",
    ".github/workflows/build-image.yaml",
    ".github/image-matrix.json",
    ".github/scripts/select-images.py",
    "container/vnc/vnc-novnc-entrypoint",
    "container/kernel/vnc-novnc-jupyter-kernel",
}


def git_output(*args: str) -> bytes:
    return subprocess.run(
        ["git", *args], cwd=ROOT, check=True, capture_output=True
    ).stdout


def changed_files() -> set[str] | None:
    """Return changed paths, or None when the event requires a full build."""
    event_name = os.environ.get("GITHUB_EVENT_NAME", "")
    event_path = os.environ.get("GITHUB_EVENT_PATH", "")
    if event_name not in {"push", "pull_request"} or not event_path:
        return None

    event = json.loads(Path(event_path).read_text())
    try:
        if event_name == "push" and os.environ.get("GITHUB_REF") == "refs/heads/main":
            before, after = event["before"], event["after"]
            if before == "0" * 40:
                return None
            base = before
        elif event_name == "pull_request":
            base_sha = event["pull_request"]["base"]["sha"]
            after = event["pull_request"]["head"]["sha"]
            base = git_output("merge-base", base_sha, after).decode().strip()
        else:
            return None
        output = git_output("diff", "--name-only", "--no-renames", "-z", base, after)
    except (KeyError, subprocess.CalledProcessError) as error:
        print(f"Could not determine changed files ({error}); building all images.")
        return None
    return {path.decode() for path in output.split(b"\0") if path}


def affects_image(path: str, image: dict) -> bool:
    dockerfile = image["dockerfile"]
    image_dir = dockerfile.rsplit("/", 1)[0] + "/"
    if path in SHARED_FILES or path.startswith("vnc_novnc/"):
        return True
    if path.startswith(image_dir):
        return True
    if path == "container/vnc/fvwm3-config" and "/fvwm3/" in dockerfile:
        return True
    # Only the Slurm clients are compiled into the desktop images. The two
    # host server commands and their package Dockerfile have a separate job.
    slurm_source = path in {
        "container/slurm-cli-proxy/go.mod",
        "container/slurm-cli-proxy/go.sum",
    } or (
        path.endswith(".go")
        and path.startswith(
            (
                "container/slurm-cli-proxy/cmd/scli/",
                "container/slurm-cli-proxy/cmd/ssh-proxy/",
                "container/slurm-cli-proxy/internal/",
            )
        )
    )
    return slurm_source and "/xfce-slurm/" in dockerfile


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--full", action="store_true", help="select every image")
    parser.add_argument("--changed", nargs="*", help="changed paths for local checks")
    args = parser.parse_args()

    images = json.loads(MATRIX_FILE.read_text())["include"]
    paths = None if args.full else set(args.changed) if args.changed is not None else changed_files()
    selected = images if paths is None else [
        image for image in images if any(affects_image(path, image) for path in paths)
    ]
    matrix = json.dumps({"include": selected}, separators=(",", ":"))
    print("Changed paths:", "full rebuild" if paths is None else sorted(paths))
    print("Selected images:", [image["name"] for image in selected])

    if output_file := os.environ.get("GITHUB_OUTPUT"):
        with open(output_file, "a") as output:
            output.write(f"matrix={matrix}\ncount={len(selected)}\n")
    else:
        print(matrix)


if __name__ == "__main__":
    main()
