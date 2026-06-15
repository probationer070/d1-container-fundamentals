# SETUP — Local Environment & Tools

> Goal: get your laptop to the point where you can **build, lint, test, run, and scan**
> the D1 image end-to-end, with the same toolchain CI uses. Everything here also
> carries forward to D2–D10, so it's worth doing properly once.

Pick the section that matches your OS, install the tools, then run the
**Verify** and **Run D1 end-to-end** sections at the bottom.

---

## 1. What you're installing and why

| Tool | Required? | Used for | Where it shows up |
|------|-----------|----------|-------------------|
| **Docker Engine + CLI** | Required | Build & run images | `make build`, `make run`, all of D1+ |
| **Buildx** (Docker plugin) | Required | Multi-stage cache, multi-arch | `make build`, CI `cache-from/to` |
| **Compose v2** (Docker plugin) | Required | Local multi-service run | `make run`, every D2+ stack |
| **Python 3.12 + pip** | Required | Run unit tests locally | `make test` |
| **make** | Required | Single entrypoint for all tasks | every `make ...` target |
| **git** | Required | Version control + image tags | Makefile derives `TAG`/`APP_VERSION` from git |
| **hadolint** | Required (D1 DoD) | Lint Dockerfiles | `make lint`, CI lint job |
| **trivy** | Recommended | CVE scan (preview of D5) | `make scan` |
| **curl / jq** | Nice to have | Poke the running API | manual verification |

You do **not** need a cloud account, Kubernetes, or any paid service for D1. It is
fully local. Keep a few GB of free disk — the naive comparison image alone pulls
the full `python:3.12` base (~1 GB).

---

## 2. macOS

There are **two independent decisions** here, not one:

- **Step A — container runtime**: pick *either* Colima *or* Docker Desktop. This
  gives you the `docker` command itself.
- **Step B — everything else** (`hadolint`, `trivy`, `make`, `python3`, `git`):
  these are normal command-line tools, completely separate from Docker. **You
  need Step B no matter which runtime you picked in Step A.**

All of these end up as plain commands in your normal Terminal — there is nothing
"inside Docker" to enter.

```bash
# Homebrew first (skip if you have it): https://brew.sh
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
```

### Step A — container runtime (pick ONE)

```bash
# --- OPTION A1 — Colima (CLI, no Docker Desktop) ---
brew install colima docker docker-compose docker-buildx
colima start --cpu 4 --memory 6 --disk 40   # give it room for image builds
# register the buildx/compose plugins for the docker CLI:
mkdir -p ~/.docker/cli-plugins
ln -sfn "$(brew --prefix)/opt/docker-buildx/bin/docker-buildx" ~/.docker/cli-plugins/docker-buildx
ln -sfn "$(brew --prefix)/opt/docker-compose/bin/docker-compose" ~/.docker/cli-plugins/docker-compose

# --- OPTION A2 — Docker Desktop (GUI) ---
# brew install --cask docker   # then launch Docker.app once to finish setup
# Docker Desktop already bundles `docker compose` and `docker buildx` — no
# extra plugin steps needed.
# (Check current Docker Desktop licensing at docker.com before using at work.)
```

### Step B — the rest of the toolchain (always required, either way)

```bash
brew install hadolint trivy git python@3.12
# `make` ships with the Xcode Command Line Tools:
xcode-select --install 2>/dev/null || true
```

Apple Silicon note: your images build natively as `arm64`. That's fine for local
testing. When you later push to a registry that serves `amd64` hosts (D3/D4), use
buildx multi-arch — already wired into the CI workflow.

---

## 3. Windows (use WSL2 — do not use raw PowerShell for this)

Containers are a Linux technology. On Windows you run the whole workflow **inside a
WSL2 Linux distro**, not in PowerShell/CMD. This gives you a real Linux environment
that matches CI.

```powershell
# In an ADMIN PowerShell, install WSL2 + Ubuntu, then reboot:
wsl --install -d Ubuntu
```

After reboot, open the **Ubuntu** terminal — **everything from here on is typed
inside that Ubuntu terminal**, not PowerShell.

Same two-step split as the other OSes:

- **Step A — container runtime**: get the `docker` command working inside Ubuntu.
  Two ways to do this — pick ONE.
- **Step B — everything else**: `git`, `make`, `python3`, `python3-pip`,
  `hadolint`, `trivy`. **Neither path in Step A installs any of these. Step B is
  required either way.**

### Step A — container runtime (pick ONE)

**A1 — Docker Desktop with WSL2 backend (simplest, GUI on Windows side):**

1. Install Docker Desktop on **Windows** (not inside Ubuntu).
2. In Docker Desktop → Settings → Resources → WSL Integration, enable
   integration for your Ubuntu distro.
3. That's it — `docker`, `docker compose`, and `docker buildx` now work from
   inside the Ubuntu terminal automatically. **No `apt-get install docker`,
   no `usermod`, no `service docker start` — Docker Desktop manages the daemon
   for you.**

```bash
# verify from inside Ubuntu — should just work, no extra commands needed:
docker version
```

**A2 — Docker Engine natively inside WSL (no Docker Desktop):**

```bash
sudo apt-get update
sudo apt-get install -y ca-certificates curl
curl -fsSL https://get.docker.com | sh
sudo usermod -aG docker "$USER"      # then close & reopen the Ubuntu terminal
# WSL has no systemd by default; start the daemon when you need it:
sudo service docker start
```

### Step B — the rest of the toolchain (always required, either way)

Run this inside Ubuntu regardless of whether you chose A1 or A2:

```bash
sudo apt-get update
sudo apt-get install -y ca-certificates curl git make python3 python3-pip

# hadolint:
sudo apt-get install -y hadolint || \
  (sudo wget -O /usr/local/bin/hadolint \
     https://github.com/hadolint/hadolint/releases/latest/download/hadolint-Linux-x86_64 \
   && sudo chmod +x /usr/local/bin/hadolint)

# trivy:
sudo apt-get install -y wget gnupg
wget -qO - https://aquasecurity.github.io/trivy-repo/deb/public.key | sudo gpg --dearmor -o /usr/share/keyrings/trivy.gpg
echo "deb [signed-by=/usr/share/keyrings/trivy.gpg] https://aquasecurity.github.io/trivy-repo/deb generic main" | sudo tee /etc/apt/sources.list.d/trivy.list
sudo apt-get update && sudo apt-get install -y trivy
```

Critical: keep the project files **inside the WSL filesystem** (e.g.
`~/projects/...`), not on `/mnt/c/...`. Building from the Windows-mounted drive is
slow and breaks file-permission/inotify behavior.

---

## 4. Linux (Ubuntu/Debian shown; adapt for Fedora/Arch)

Same two-step split as macOS:

- **Step A — container runtime**: Docker Engine (recommended on Linux — it's
  native here, no VM needed) *or* Docker Desktop. Pick one.
- **Step B — everything else**: `git`, `make`, `python3`, `python3-pip`,
  `hadolint`, `trivy`. **None of these come from Docker, Engine or Desktop.
  Install Step B regardless of what you chose in Step A.**

`ca-certificates` and `curl` are listed because the install commands below (for
Docker, hadolint, trivy) all fetch things over HTTPS — they're plumbing for the
*other* installs, not Docker itself.

### Step A — container runtime (pick ONE)

```bash
sudo apt-get update
sudo apt-get install -y ca-certificates curl

# --- OPTION A1 — Docker Engine (recommended on Linux) ---
# Follow the canonical steps at https://docs.docker.com/engine/install/ubuntu/
# Quick path:
curl -fsSL https://get.docker.com | sh
sudo usermod -aG docker "$USER"     # log out/in so group membership applies
# buildx & compose plugins come bundled with current Docker Engine.

# --- OPTION A2 — Docker Desktop for Linux ---
# Download the .deb from https://docs.docker.com/desktop/setup/install/linux/
# and install with: sudo apt-get install ./docker-desktop-<version>.deb
# Docker Desktop bundles compose & buildx too — no extra plugin steps.
```

### Step B — the rest of the toolchain (always required, either way)

```bash
sudo apt-get install -y git make python3 python3-pip

# hadolint:
sudo wget -O /usr/local/bin/hadolint \
  https://github.com/hadolint/hadolint/releases/latest/download/hadolint-Linux-x86_64
sudo chmod +x /usr/local/bin/hadolint

# trivy:
wget -qO - https://aquasecurity.github.io/trivy-repo/deb/public.key | sudo gpg --dearmor -o /usr/share/keyrings/trivy.gpg
echo "deb [signed-by=/usr/share/keyrings/trivy.gpg] https://aquasecurity.github.io/trivy-repo/deb generic main" | sudo tee /etc/apt/sources.list.d/trivy.list
sudo apt-get update && sudo apt-get install -y trivy
```

---

## 5. Verify your toolchain

Open your normal Terminal (the same one you used for installation — Terminal.app
on macOS, the Ubuntu app on WSL2, your terminal emulator on Linux). **Every command
below is typed into that same terminal, one after another.** None of them require
you to "enter" Docker or any container — `docker` is just one CLI among the others.

Run this once. Every line should print a version without error.

```bash
docker version            # client AND server must both report (daemon running)
docker buildx version
docker compose version
hadolint --version
python3 --version         # expect 3.12.x  (3.11+ is fine to run tests)
pip --version
make --version
git --version
trivy --version           # optional but recommended
```

If `docker version` shows the client but errors on the server, your daemon isn't
running:
- macOS/Colima: `colima start`
- WSL native engine: `sudo service docker start`
- Docker Desktop: launch the app
- Linux: `sudo systemctl start docker`

If `docker ps` says *permission denied*, you skipped the post-install group step —
run `sudo usermod -aG docker "$USER"` and start a fresh shell.

---

## 6. Run D1 end-to-end

From the project root (`d1-container-fundamentals/`):

```bash
make help          # see all targets

# 1) Unit tests — gates the build. Expect: "4 passed".
make test

# 2) Lint the Dockerfiles. Expect: no output / exit 0 (0 warnings).
make lint

# 3) Build all three variants and print the REAL size table:
make sizes
#    Example shape (your exact MBs will vary by base-image digest):
#      d1-health-api:naive        ~1.0–1.05GB
#      d1-health-api:slim         ~190–230MB
#      d1-health-api:distroless   ~90–130MB
#    Put YOUR measured numbers in the README size table — that's the D1 deliverable.

# 4) Run it and confirm it serves + reports healthy:
make run                                  # leave this running; new terminal below
```

In a second terminal, verify the live container:

```bash
curl -s localhost:8000/healthz            # {"status":"ok","uptime_seconds":...}
curl -s localhost:8000/version            # {"version":"...","git_sha":"..."}
docker ps                                 # STATUS column should read "(healthy)"
```

The `(healthy)` status is the proof your `HEALTHCHECK` works — that exact signal is
what an orchestrator reads in D8 to decide whether to route traffic or restart.

```bash
# 5) Security scan (preview of D5). Expect a CVE report; aim for 0 HIGH/CRITICAL.
make scan
```

Stop everything with `Ctrl-C` in the `make run` terminal, then `docker compose down`.

---

## 7. Footprint & housekeeping

- Disk: the three variants + base layers total roughly **2–3 GB**. `make clean`
  removes the built images; `docker image prune` clears dangling layers.
- The `naive` image is built **only** for the comparison — don't keep it around.
- First `make sizes` pulls `python:3.12`, `python:3.12-slim`, `python:3.11-slim`,
  and the distroless base, so expect a few minutes on first run; later builds hit
  the layer cache and are fast.

---

## 8. What this unlocks next

Once this toolchain is in place you're ready for **D2** (Gitea + Postgres + Act
Runner via Compose) with zero new host tooling — D2 only adds containers, not
laptop dependencies. The first genuinely new tool arrives at **D8** (`kubectl` +
`k3s`/`kind` for orchestration). Until then, this is your whole environment.
