# Release v0.1.0-rc.1 — 2026-06-18

## Highlights

First versioned release of `d1-health-api`. This pre-release validates the complete D3 CI/CD pipeline end-to-end: commit → lint → test → multi-arch build → GHCR push, running identically on both GitHub Actions and a self-hosted Gitea act_runner. The image is not production-ready (`rc` = release candidate); this tag exists to confirm the release workflow and tagging strategy work correctly before D4 (Harbor + cosign).

## What's new

### Multi-arch Docker image on GHCR

`ghcr.io/probationer070/d1-health-api` is now published to GitHub Container Registry on every push to `main` and on every semver tag.

```sh
# Pull the release candidate
docker pull ghcr.io/probationer070/d1-health-api:0.1.0-rc.1

# Pull the latest edge build
docker pull ghcr.io/probationer070/d1-health-api:edge
```

Supported platforms: `linux/amd64`, `linux/arm64`

### Automated CI pipeline (GitHub Actions + Gitea mirror)

Every commit to `main` runs:

| Job | What it checks |
|-----|---------------|
| `lint` | Dockerfile lint via `hadolint --failure-threshold error` |
| `test` | Python unit tests via `pytest` in an isolated venv |
| `build-push` | Multi-arch buildx build; pushes to GHCR on `push` events |

The same pipeline runs on the self-hosted Gitea act_runner (`.gitea/workflows/ci.yaml`), mirroring GitHub CI without the GHA cache layer.

### Semver release workflow

Pushing a `v*.*.*` tag triggers `.github/workflows/release.yaml`, which produces:
- A versioned GHCR tag (e.g. `0.1.0-rc.1`)
- `latest` tag — **only for stable releases** (tags without `-rc`, `-alpha`, `-beta` suffixes)

```sh
# This tag was created for this release:
git tag v0.1.0-rc.1
git push origin v0.1.0-rc.1
# → GHCR: 0.1.0-rc.1  (latest NOT updated — prerelease guard active)
```

## Improvements

- **Image size**: multi-stage build produces a `python:3.13-slim`-based runtime image; build tooling excluded from final layer
- **Tagging strategy**: `sha-<short>` + `edge` on every main push; `<semver>` on tag push; `latest` gated to stable releases only

## Bug fixes

None — this is the first release.

## Breaking changes

None.

## Known limitations

- **No cosign signing** — image signing infrastructure is seeded (`cosign` step present with `if: false` guard) but not activated. Signing will be enabled in D4.
- **No GHA cache on Gitea CI** — buildx cache is disabled on the Gitea mirror because the buildkit builder container cannot reach the Gitea cache service. Cold builds take ~3–5 min longer. Registry cache (`type=registry`) is a candidate fix for D4.
- **`latest` tag not set** — intentional for pre-releases. Push a stable tag (e.g. `v0.1.0`) to update `latest`.

## Upgrade guide

No upgrade needed — this is the first release. To run the image:

```sh
docker run --rm -p 8000:8000 ghcr.io/probationer070/d1-health-api:0.1.0-rc.1
# Health check:
curl http://localhost:8000/health
```

## Full changelog

| Commit | Message |
|--------|---------|
| `0c5737f` | feat: D1 container image fundamentals |
| `9ef581b` | ci(d3): add Gitea Actions CI mirror |
| `e456af6` | chore(d3): remove Buildx/QEMU probe — gate passed |
| `0f88784` | ci(d3): install hadolint in Gitea lint job |
| `dbce480` | ci(d3): remove type=gha cache from Gitea workflow |
