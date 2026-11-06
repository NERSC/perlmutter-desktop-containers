#!/usr/bin/env python3
"""Compatibility wrapper for the packaged VNC/noVNC runner."""

from vnc_novnc.runner import main


if __name__ == "__main__":
    raise SystemExit(main())
