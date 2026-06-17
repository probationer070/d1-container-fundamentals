# D1 — Container Image Fundamentals

> **What**: A tiny FastAPI health-check service, packaged three different ways
> (naive, optimized slim, distroless) to demonstrate production-grade image
> engineering — not the app itself.
> **Why this way**: Multi-stage builds + dependency-layer caching + non-root +
> shell-free healthchecks are the baseline every later project (D2–D10) builds
> on. Getting this right once means every subsequent Dockerfile inherits the
> same discipline.
> **Learned / next**: see [ADRs](#decision-records-adrs) below. Next project
> (D2) reuses this same `.dockerignore` / tagging convention for a multi-service
> Compose stack (Gitea).

---

## Architecture

```
                 ┌────────────────────────────┐
                 │  builder stage              │
                 │  python:3.12-slim           │
                 │  - copy requirements.txt    │
                 │  - pip install into venv    │
                 └──────────────┬───────────────┘
                                 │ COPY --from=builder
                                 ▼
                 ┌────────────────────────────┐
                 │  runtime stage              │
                 │  python:3.12-slim           │
                 │  - non-root user "app"      │
                 │  - venv + app/ only         │
                 │  - HEALTHCHECK (python probe)│
                 │  - exec-form CMD (uvicorn)  │
                 └────────────────────────────┘
```

Three Dockerfiles, same app:

| File | Purpose |
|---|---|
| `Dockerfile` | **Primary** — multi-stage, `python:3.12-slim`, non-root, healthcheck. This is the one CI builds. |
| `Dockerfile.distroless` | Smallest attack surface variant — `gcr.io/distroless/python3-debian12:nonroot`. Documents the Python-version-match gotcha (builder pinned to 3.11 to match Debian 12's distroless Python). |
| `Dockerfile.naive` | **Anti-pattern, on purpose.** The "before" image for the size comparison — full `python:3.12`, root, `COPY . .` before install, shell-form CMD, no healthcheck. Never deploy this; it exists only so `make sizes` has a baseline to compare against. |

---

## App endpoints

| Endpoint | Purpose |
|---|---|
| `GET /` | Service identity (name, version, git sha) |
| `GET /healthz` | Liveness — process is up |
| `GET /readyz` | Readiness — willing to take traffic |
| `GET /version` | Reports `APP_VERSION` / `GIT_SHA` baked in at build time |

`/healthz` is what `app/healthcheck.py` polls for the container `HEALTHCHECK`,
and what an orchestrator (D8) will poll for liveness/readiness probes.

---

## Run it

See [`SETUP.md`](./SETUP.md) for installing the toolchain (Docker, hadolint,
trivy, make, python3, git) on macOS / Windows(WSL2) / Linux.

```bash
make help          # list all targets
make test          # pytest — gates the build
make lint          # hadolint on both Dockerfiles, 0 warnings expected
make sizes         # build naive + slim + distroless, print real size table - should be run Docker Desktop
make run           # docker compose up --build
make scan          # trivy CVE scan of the slim image (preview of D5)
```

---

## Measured image sizes

| Variant | Size | Notes |
|---|---|---|
| `d1-health-api:naive` | 1.17GB | Full `python:3.12`, root, unoptimized cache order |
| `d1-health-api:slim` | 169MB | Multi-stage, `python:3.12-slim`, non-root |
| `d1-health-api:distroless` | 89.1MB | `gcr.io/distroless/python3-debian12:nonroot` |

---

## Definition of Done

| Criterion | Status |
|-----------|--------|
| Naive vs optimised size comparison table in README | ✅ |
| `hadolint` 0 warnings — `make lint` | ✅ |
| 0 critical CVEs — `make scan` | ✅ |

---

## Decision Records (ADRs)

**ADR-1: Multi-stage build with a venv, not `pip install --user`.**
A venv keeps the dependency tree isolated and copyable as a single directory
(`COPY --from=builder /opt/venv /opt/venv`), independent of where `site-packages`
lives for the base image's Python. This made the runtime stage copy trivial and
kept the builder's compiler toolchain (gcc, headers — pulled in transitively by
some wheels) entirely out of the final image.

**ADR-2: Distroless builder pinned to `python:3.11-slim`, not `3.12-slim`.**
`gcr.io/distroless/python3-debian12` ships whatever CPython Debian 12 (bookworm)
provides — that's 3.11, not 3.12. A venv built with 3.12 would reference a 3.12
interpreter that doesn't exist in the distroless layer. Pinning the builder to
match the distroless base's Python version is the fix; this is documented inline
in `Dockerfile.distroless` because it's an easy mistake to repeat in later
projects.

**ADR-3: Shell-free healthcheck (`app/healthcheck.py`), not `curl`.**
Distroless images ship no shell and no `curl`/`wget`, so
`HEALTHCHECK CMD curl -f http://localhost:8000/healthz || exit 1` simply cannot
run there. A small stdlib-only Python probe works identically in `slim` and
`distroless`, so both Dockerfiles share the same healthcheck mechanism — one
less thing to diverge between variants.

**ADR-4: Exec-form `CMD`/`ENTRYPOINT`, not shell-form.**
`CMD uvicorn app.main:app ...` (shell form) runs as `/bin/sh -c "uvicorn ..."`,
so `SIGTERM` goes to the shell, not uvicorn — the process often doesn't shut
down cleanly until SIGKILL. `CMD ["uvicorn", "app.main:app", ...]` (exec form)
makes uvicorn PID 1 and lets it handle SIGTERM directly. This matters for D8:
clean shutdown is what makes rolling updates not drop in-flight requests.

**ADR-5: Distroless over Alpine for the minimal variant.**
Alpine uses `musl libc` instead of glibc. Python wheels built for glibc may
link glibc symbols absent in musl — causing import errors at runtime that don't
appear at build time (the wheel installs cleanly; it crashes when it runs).
Distroless uses Debian's glibc, so wheels built against `python:3.12-slim` are
binary-compatible with no recompilation. For a statically-linked Go or Rust
binary, Alpine is an excellent choice; for Python, distroless is safer.

**ADR-6: `COPY` dependency manifest first, then install, then `COPY` source.**
When `COPY . .` precedes `pip install`, any single-line code change invalidates the install layer and forces a full dependency reinstall on every build. Copying only `requirements.txt` first, running the install, then copying source keeps the expensive install layer cached as long as dependencies don't change. On a project with heavy wheels this is the difference between a 30-second and a 3-minute CI build. The same principle applies in every language: `package.json` before `npm install`, `go.mod` before `go mod download`.

---

## Common Pitfalls

- **`FROM ubuntu` + `apt install` everything** — build tools end up in the final image; image bloats to GB range with no multi-stage separation.
- **`COPY . .` before `pip install`** — any single-line code change invalidates the dependency layer, triggering a full reinstall on every build. Always copy the manifest first, install, then copy source (see cache-ordering comment in `Dockerfile`).
- **Secrets in build `ARG`** — visible in `docker image history` even after the layer is "overwritten." Use BuildKit `--secret` mount or inject at runtime via env; never bake credentials into image layers.
- **`latest` or floating base image tags** — `python:3.12-slim` today and tomorrow are different digests; the build is not reproducible. Pin to a digest (`@sha256:...`) for production; at minimum use a minor-version tag, not `3-slim`.

---

## What's deliberately out of scope for D1

- Pushing images anywhere (D3 — registry + CI push)
- Image signing / SBOM / vuln gating as a CI *gate* (D5 — `make scan` here is
  just a manual preview)
- Multi-arch builds in CI (D3 introduces `docker/build-push-action` with
  `cache-from/to: type=gha`)
- A self-hosted CI runner (D2 stands up Gitea + a runner; D3 mirrors this
  project's pipeline to it)
