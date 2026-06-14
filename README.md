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
make sizes         # build naive + slim + distroless, print real size table
make run           # docker compose up --build
make scan          # trivy CVE scan of the slim image (preview of D5)
```

---

## Measured image sizes

> Fill this in after running `make sizes` on your machine — these are the D1
> deliverable numbers. Sizes vary slightly by platform/arch and base-image
> digest at build time, so use **your own measured values**, not estimates.

| Variant | Size | Notes |
|---|---|---|
| `d1-health-api:naive` | _TODO_ | Full `python:3.12`, root, unoptimized cache order |
| `d1-health-api:slim` | _TODO_ | Multi-stage, `python:3.12-slim`, non-root |
| `d1-health-api:distroless` | _TODO_ | `gcr.io/distroless/python3-debian12:nonroot` |

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

---

## What's deliberately out of scope for D1

- Pushing images anywhere (D3 — registry + CI push)
- Image signing / SBOM / vuln gating as a CI *gate* (D5 — `make scan` here is
  just a manual preview)
- Multi-arch builds in CI (D3 introduces `docker/build-push-action` with
  `cache-from/to: type=gha`)
- A self-hosted CI runner (D2 stands up Gitea + a runner; D3 mirrors this
  project's pipeline to it)



---


```
park@DESKTOP-7KFUBM2:~/docker-project/d1-container-fundamentals$ make scan
docker build -f Dockerfile --build-arg APP_VERSION=0.0.0-dev --build-arg GIT_SHA=local -t d1-health-api:slim .
[+] Building 1.7s (15/15) FINISHED                          docker:default
 => [internal] load build definition from Dockerfile                  0.0s
 => => transferring dockerfile: 1.95kB                                0.0s
 => resolve image config for docker-image://docker.io/docker/dockerf  0.8s
 => CACHED docker-image://docker.io/docker/dockerfile:1.7@sha256:a57  0.0s
 => [internal] load metadata for docker.io/library/python:3.12-slim   0.6s
 => [internal] load .dockerignore                                     0.0s
 => => transferring context: 332B                                     0.0s
 => [builder 1/4] FROM docker.io/library/python:3.12-slim@sha256:d76  0.0s
 => [internal] load build context                                     0.0s
 => => transferring context: 134B                                     0.0s
 => CACHED [runtime 2/5] RUN groupadd --system app && useradd --syst  0.0s
 => CACHED [runtime 3/5] WORKDIR /app                                 0.0s
 => CACHED [builder 2/4] WORKDIR /app                                 0.0s
 => CACHED [builder 3/4] COPY app/requirements.txt .                  0.0s
 => CACHED [builder 4/4] RUN python -m venv /opt/venv  && /opt/venv/  0.0s
 => CACHED [runtime 4/5] COPY --from=builder /opt/venv /opt/venv      0.0s
 => CACHED [runtime 5/5] COPY app/ ./app/                             0.0s
 => exporting to image                                                0.0s
 => => exporting layers                                               0.0s
 => => writing image sha256:08856154cd0938c4b326f832d9c418e59966f4ac  0.0s
 => => naming to docker.io/library/d1-health-api:slim                 0.0s
trivy image --severity HIGH,CRITICAL d1-health-api:slim
2026-06-14T16:45:29+09:00       INFO    [vulndb] Need to update DB
2026-06-14T16:45:29+09:00       INFO    [vulndb] Downloading vulnerability DB...
2026-06-14T16:45:29+09:00       INFO    [vulndb] Downloading artifact...  repo="mirror.gcr.io/aquasec/trivy-db:2"
96.07 MiB / 96.07 MiB [------------------------] 100.00% 10.79 MiB p/s 9.1s
2026-06-14T16:45:40+09:00       INFO    [vulndb] Artifact successfully downloaded  repo="mirror.gcr.io/aquasec/trivy-db:2"
2026-06-14T16:45:40+09:00       INFO    [vuln] Vulnerability scanning is enabled
2026-06-14T16:45:40+09:00       INFO    [secret] Secret scanning is enabled
2026-06-14T16:45:40+09:00       INFO    [secret] If your scanning is slow, please try '--scanners vuln' to disable secret scanning
2026-06-14T16:45:40+09:00       INFO    [secret] Please see https://trivy.dev/docs/v0.71/guide/scanner/secret#recommendation for faster secret detection
2026-06-14T16:45:45+09:00       INFO    [python] Licenses acquired from one or more METADATA files may be subject to additional terms. Use `--debug` flag to see all affected packages.
2026-06-14T16:45:45+09:00       INFO    Detected OS     family="debian" version="13.5"
2026-06-14T16:45:45+09:00       INFO    [debian] Detecting vulnerabilities...      os_version="13" pkg_num=87
2026-06-14T16:45:45+09:00       INFO    Number of language-specific files num=1
2026-06-14T16:45:45+09:00       INFO    [python-pkg] Detecting vulnerabilities...
2026-06-14T16:45:45+09:00       WARN    Using severities from other vendors for some vulnerabilities. Read https://trivy.dev/docs/v0.71/guide/scanner/vulnerability#severity-selection for details.

Report Summary

┌──────────────────────────────────────────────────────────────────────────────────┬────────────┬─────────────────┬─────────┐
│                                      Target                                      │    Type    │ Vulnerabilities │ Secrets │
├──────────────────────────────────────────────────────────────────────────────────┼────────────┼─────────────────┼─────────┤
│ d1-health-api:slim (debian 13.5)                                                 │   debian   │       12        │    -    │
├──────────────────────────────────────────────────────────────────────────────────┼────────────┼─────────────────┼─────────┤
│ opt/venv/lib/python3.12/site-packages/annotated_doc-0.0.4.dist-info/METADATA     │ python-pkg │        0        │    -    │
├──────────────────────────────────────────────────────────────────────────────────┼────────────┼─────────────────┼─────────┤
│ opt/venv/lib/python3.12/site-packages/annotated_types-0.7.0.dist-info/METADATA   │ python-pkg │        0        │    -    │
├──────────────────────────────────────────────────────────────────────────────────┼────────────┼─────────────────┼─────────┤
│ opt/venv/lib/python3.12/site-packages/anyio-4.13.0.dist-info/METADATA            │ python-pkg │        0        │    -    │
├──────────────────────────────────────────────────────────────────────────────────┼────────────┼─────────────────┼─────────┤
│ opt/venv/lib/python3.12/site-packages/click-8.4.1.dist-info/METADATA             │ python-pkg │        0        │    -    │
├──────────────────────────────────────────────────────────────────────────────────┼────────────┼─────────────────┼─────────┤
│ opt/venv/lib/python3.12/site-packages/fastapi-0.136.3.dist-info/METADATA         │ python-pkg │        0        │    -    │
├──────────────────────────────────────────────────────────────────────────────────┼────────────┼─────────────────┼─────────┤
│ opt/venv/lib/python3.12/site-packages/h11-0.16.0.dist-info/METADATA              │ python-pkg │        0        │    -    │
├──────────────────────────────────────────────────────────────────────────────────┼────────────┼─────────────────┼─────────┤
│ opt/venv/lib/python3.12/site-packages/httptools-0.8.0.dist-info/METADATA         │ python-pkg │        0        │    -    │
├──────────────────────────────────────────────────────────────────────────────────┼────────────┼─────────────────┼─────────┤
│ opt/venv/lib/python3.12/site-packages/idna-3.18.dist-info/METADATA               │ python-pkg │        0        │    -    │
├──────────────────────────────────────────────────────────────────────────────────┼────────────┼─────────────────┼─────────┤
│ opt/venv/lib/python3.12/site-packages/pip-25.0.1.dist-info/METADATA              │ python-pkg │        0        │    -    │
├──────────────────────────────────────────────────────────────────────────────────┼────────────┼─────────────────┼─────────┤
│ opt/venv/lib/python3.12/site-packages/pydantic-2.13.4.dist-info/METADATA         │ python-pkg │        0        │    -    │
├──────────────────────────────────────────────────────────────────────────────────┼────────────┼─────────────────┼─────────┤
│ opt/venv/lib/python3.12/site-packages/pydantic_core-2.46.4.dist-info/METADATA    │ python-pkg │        0        │    -    │
├──────────────────────────────────────────────────────────────────────────────────┼────────────┼─────────────────┼─────────┤
│ opt/venv/lib/python3.12/site-packages/python_dotenv-1.2.2.dist-info/METADATA     │ python-pkg │        0        │    -    │
├──────────────────────────────────────────────────────────────────────────────────┼────────────┼─────────────────┼─────────┤
│ opt/venv/lib/python3.12/site-packages/pyyaml-6.0.3.dist-info/METADATA            │ python-pkg │        0        │    -    │
├──────────────────────────────────────────────────────────────────────────────────┼────────────┼─────────────────┼─────────┤
│ opt/venv/lib/python3.12/site-packages/starlette-1.3.1.dist-info/METADATA         │ python-pkg │        0        │    -    │
├──────────────────────────────────────────────────────────────────────────────────┼────────────┼─────────────────┼─────────┤
│ opt/venv/lib/python3.12/site-packages/typing_extensions-4.15.0.dist-info/METADA- │ python-pkg │        0        │    -    │
│ TA                                                                               │            │                 │         │
├──────────────────────────────────────────────────────────────────────────────────┼────────────┼─────────────────┼─────────┤
│ opt/venv/lib/python3.12/site-packages/typing_inspection-0.4.2.dist-info/METADATA │ python-pkg │        0        │    -    │
├──────────────────────────────────────────────────────────────────────────────────┼────────────┼─────────────────┼─────────┤
│ opt/venv/lib/python3.12/site-packages/uvicorn-0.49.0.dist-info/METADATA          │ python-pkg │        0        │    -    │
├──────────────────────────────────────────────────────────────────────────────────┼────────────┼─────────────────┼─────────┤
│ opt/venv/lib/python3.12/site-packages/uvloop-0.22.1.dist-info/METADATA           │ python-pkg │        0        │    -    │
├──────────────────────────────────────────────────────────────────────────────────┼────────────┼─────────────────┼─────────┤
│ opt/venv/lib/python3.12/site-packages/watchfiles-1.2.0.dist-info/METADATA        │ python-pkg │        0        │    -    │
├──────────────────────────────────────────────────────────────────────────────────┼────────────┼─────────────────┼─────────┤
│ opt/venv/lib/python3.12/site-packages/websockets-16.0.dist-info/METADATA         │ python-pkg │        0        │    -    │
├──────────────────────────────────────────────────────────────────────────────────┼────────────┼─────────────────┼─────────┤
│ usr/local/lib/python3.12/site-packages/pip-25.0.1.dist-info/METADATA             │ python-pkg │        0        │    -    │
└──────────────────────────────────────────────────────────────────────────────────┴────────────┴─────────────────┴─────────┘
Legend:
- '-': Not scanned
- '0': Clean (no security findings detected)


d1-health-api:slim (debian 13.5)

Total: 12 (HIGH: 10, CRITICAL: 2)

┌──────────────┬────────────────┬──────────┬──────────────┬───────────────────┬───────────────┬──────────────────────────────────────────────────────────────┐
│   Library    │ Vulnerability  │ Severity │    Status    │ Installed Version │ Fixed Version │                            Title                             │
├──────────────┼────────────────┼──────────┼──────────────┼───────────────────┼───────────────┼──────────────────────────────────────────────────────────────┤
│ libncursesw6 │ CVE-2025-69720 │ HIGH     │ affected     │ 6.5+20250216-2    │               │ ncurses: ncurses: Buffer overflow vulnerability may lead to  │
│              │                │          │              │                   │               │ arbitrary code execution.                                    │
│              │                │          │              │                   │               │ https://avd.aquasec.com/nvd/cve-2025-69720                   │
├──────────────┼────────────────┤          │              ├───────────────────┼───────────────┼──────────────────────────────────────────────────────────────┤
│ libsqlite3-0 │ CVE-2026-11822 │          │              │ 3.46.1-7+deb13u1  │               │ SQLite before 3.53.2 contains memory corruption              │
│              │                │          │              │                   │               │ vulnerabilities in the ...                                   │
│              │                │          │              │                   │               │ https://avd.aquasec.com/nvd/cve-2026-11822                   │
│              ├────────────────┤          │              │                   ├───────────────┼──────────────────────────────────────────────────────────────┤
│              │ CVE-2026-11824 │          │              │                   │               │ SQLite before 3.53.2 contains a heap-based buffer overflow   │
│              │                │          │              │                   │               │ vulnerabili ...                                              │
│              │                │          │              │                   │               │ https://avd.aquasec.com/nvd/cve-2026-11824                   │
├──────────────┼────────────────┤          │              ├───────────────────┼───────────────┼──────────────────────────────────────────────────────────────┤
│ libtinfo6    │ CVE-2025-69720 │          │              │ 6.5+20250216-2    │               │ ncurses: ncurses: Buffer overflow vulnerability may lead to  │
│              │                │          │              │                   │               │ arbitrary code execution.                                    │
│              │                │          │              │                   │               │ https://avd.aquasec.com/nvd/cve-2025-69720                   │
├──────────────┤                │          │              │                   ├───────────────┤                                                              │
│ ncurses-base │                │          │              │                   │               │                                                              │
│              │                │          │              │                   │               │                                                              │
│              │                │          │              │                   │               │                                                              │
├──────────────┤                │          │              │                   ├───────────────┤                                                              │
│ ncurses-bin  │                │          │              │                   │               │                                                              │
│              │                │          │              │                   │               │                                                              │
│              │                │          │              │                   │               │                                                              │
├──────────────┼────────────────┼──────────┼──────────────┼───────────────────┼───────────────┼──────────────────────────────────────────────────────────────┤
│ perl-base    │ CVE-2026-42496 │ CRITICAL │ fix_deferred │ 5.40.1-6          │               │ perl-archive-tar: perl-archive-tar: Path traversal via       │
│              │                │          │              │                   │               │ crafted symlinks allows arbitrary file access                │
│              │                │          │              │                   │               │ https://avd.aquasec.com/nvd/cve-2026-42496                   │
│              ├────────────────┤          ├──────────────┤                   ├───────────────┼──────────────────────────────────────────────────────────────┤
│              │ CVE-2026-8376  │          │ affected     │                   │               │ Perl versions through 5.43.10 have a heap buffer overflow    │
│              │                │          │              │                   │               │ when compili ......                                          │
│              │                │          │              │                   │               │ https://avd.aquasec.com/nvd/cve-2026-8376                    │
│              ├────────────────┼──────────┼──────────────┤                   ├───────────────┼──────────────────────────────────────────────────────────────┤
│              │ CVE-2026-42497 │ HIGH     │ fix_deferred │                   │               │ Archive::Tar versions before 3.08 for Perl extract hardlinks │
│              │                │          │              │                   │               │ to attack ...                                                │
│              │                │          │              │                   │               │ https://avd.aquasec.com/nvd/cve-2026-42497                   │
│              ├────────────────┤          ├──────────────┤                   ├───────────────┼──────────────────────────────────────────────────────────────┤
│              │ CVE-2026-48959 │          │ affected     │                   │               │ IO::Uncompress::Unzip versions before 2.220 for Perl allow   │
│              │                │          │              │                   │               │ CPU exhaust ...                                              │
│              │                │          │              │                   │               │ https://avd.aquasec.com/nvd/cve-2026-48959                   │
│              ├────────────────┤          │              │                   ├───────────────┼──────────────────────────────────────────────────────────────┤
│              │ CVE-2026-48962 │          │              │                   │               │ perl-IO-Compress: perl-IO-Compress: Arbitrary code execution │
│              │                │          │              │                   │               │ via attacker-controlled output glob                          │
│              │                │          │              │                   │               │ https://avd.aquasec.com/nvd/cve-2026-48962                   │
│              ├────────────────┤          ├──────────────┤                   ├───────────────┼──────────────────────────────────────────────────────────────┤
│              │ CVE-2026-9538  │          │ fix_deferred │                   │               │ Archive::Tar versions before 3.10 for Perl allow memory      │
│              │                │          │              │                   │               │ exhaustion via ...                                           │
│              │                │          │              │                   │               │ https://avd.aquasec.com/nvd/cve-2026-9538                    │
└──────────────┴────────────────┴──────────┴──────────────┴───────────────────┴───────────────┴──────────────────────────────────────────────────────────────┘
p
```