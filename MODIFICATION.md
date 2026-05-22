# ai-blaise/openauth Modifications

The `ai-blaise/openauth` fork tracks upstream `anomalyco/openauth` (the toolbeam/openauth source of truth) and layers a thin set of platform-only modifications. This document is the canonical inventory of the additions.

## Why a fork exists

The Command Center platform (`ai-blaise/command-center`, plan v5 Section 15) requires OpenAuth as a containerized issuer service consumed at `ghcr.io/ai-blaise/openauth:<ver>-ai-blaise.<N>` with the Citus storage adapter and OIDC Backstage glue. Upstream publishes only the npm library `@openauthjs/openauth`. Owning the mirror lets us:

- Publish a stable, signed container image under the ai-blaise namespace.
- Retain a clean rebase path: every modification is additive and lives outside `packages/openauth/src`.
- Stamp every image with a deterministic `<upstream-version>-ai-blaise.<N>` tag so chart pins are reproducible.

## Modifications inventory

| Path | Kind | Purpose |
|------|------|---------|
| `.github/workflows/publish-image.yml` | additive | Builds and publishes the container image, attaches an SBOM, signs with cosign keyless when available, and tags the commit `image-publish-<full_tag>`. |
| `Dockerfile` | additive | Minimal bun-based runtime around the workspace `@openauthjs/openauth` package and the `examples/issuer/bun` entrypoint (port 3000). |
| `.dockerignore` | additive | Restricts the image build context to runtime-relevant paths. |
| `MODIFICATION.md` | additive | This document. |
| `IMAGE_PUBLICATION.md` | additive | Image pipeline operations + command-center consumption. |
| `AI_BLAISE_MIRROR.md` | additive | Existing mirror policy statement (kept). |

No upstream files are forked or strategically patched. Runtime composition (Citus adapter, OIDC Backstage module) is injected at deploy time by the platform helm chart `deploy/openauth` and the workspace package `@internal/openauth-storage-citus` in `ai-blaise/command-center`.

## ai-blaise version suffix scheme

The image tag is `<upstream-version>-ai-blaise.<N>` where:

- `<upstream-version>` is `packages/openauth/package.json .version` (currently `0.4.3`).
- `<N>` is the count of commits on the mirror default branch beyond the matching upstream package tag. The workflow tries, in order:
  1. `refs/tags/@openauthjs/openauth@<ver>` (upstream package tag),
  2. `refs/tags/v<ver>`,
  3. `refs/remotes/upstream/master`,
  4. `refs/remotes/upstream/main`.
- If no base resolves, `<N>` is `1`. Otherwise `<N> = max(git rev-list --count <base>..HEAD, 1)`. The `max(_, 1)` floor guarantees that the first ai-blaise commit publishes `ai-blaise.1`, which matches the platform pin in `deploy/openauth/values.yaml`.
- When the upstream `<ver>` bumps, `<N>` resets naturally because the new tag is reachable from upstream.

The same `<upstream-version>-ai-blaise.<N>` string is also used for the platform helm chart version under `helm/charts/openauth`.

## Rebase contract

- Modifications live only in the paths listed above. Upstream rebases must not surface conflicts inside `packages/openauth/src` because we never touch it.
- The publish workflow keys off `packages/openauth/package.json .version`, so an upstream version bump propagates automatically once it lands on this fork's default branch.
- Removing or renaming any path in the inventory must be paired with an update to this file and to `ai-blaise/command-center/contracts/fork-contracts.json`.
