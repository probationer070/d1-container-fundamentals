"""Healthcheck used by the container HEALTHCHECK instruction.

Distroless images ship no shell and no curl/wget, so we cannot write
`HEALTHCHECK CMD curl ...`. A tiny Python probe using only the stdlib works in
both slim and distroless runtimes.
"""
import sys
import urllib.request

URL = "http://127.0.0.1:8000/healthz"

try:
    with urllib.request.urlopen(URL, timeout=2) as resp:  # noqa: S310 (localhost only)
        sys.exit(0 if resp.status == 200 else 1)
except Exception:
    sys.exit(1)
