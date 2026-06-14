"""D1 Health API — a deliberately small service.

The point of D1 is not the app; it is how we package it. This service exists
only to give the image something real to run, with the kind of liveness/
readiness endpoints a real orchestrator (D8) and probe-based healthcheck need.
"""
import os
import time

from fastapi import FastAPI, Response, status

APP_VERSION = os.getenv("APP_VERSION", "0.0.0-dev")
GIT_SHA = os.getenv("GIT_SHA", "unknown")
_START = time.monotonic()

app = FastAPI(title="D1 Health API", version=APP_VERSION)

# In a real app this flips false during startup work / dependency outages.
_ready = True


@app.get("/")
def root():
    return {"service": "d1-health-api", "version": APP_VERSION, "git_sha": GIT_SHA}


@app.get("/healthz")
def healthz():
    """Liveness: the process is up and the event loop answers."""
    return {"status": "ok", "uptime_seconds": round(time.monotonic() - _START, 3)}


@app.get("/readyz")
def readyz(response: Response):
    """Readiness: the service is willing to take traffic."""
    if not _ready:
        response.status_code = status.HTTP_503_SERVICE_UNAVAILABLE
        return {"status": "not_ready"}
    return {"status": "ready"}


@app.get("/version")
def version():
    return {"version": APP_VERSION, "git_sha": GIT_SHA}
