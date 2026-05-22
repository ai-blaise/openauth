# Image Publication

## Pipeline

`.github/workflows/publish-image.yml` is the only image-publication entrypoint for `ai-blaise/openauth`. It runs on every push to `master` and on `workflow_dispatch`.

Flow:

1. Checkout with `fetch-depth: 0` and add `upstream = https://github.com/anomalyco/openauth.git` (idempotent).
2. Read `<ver>` from `packages/openauth/package.json`.
3. Compute `<N>` (see "Suffix scheme" below) and the full tag `<ver>-ai-blaise.<N>`.
4. Decide build path. Path A (rebuild) is taken when a `Dockerfile` is present in the repo, which is the case for this mirror. Path B (retag-only via `regclient/actions/regctl-installer`) is wired but disabled, reserved for the future case where upstream begins publishing an image we can mirror without rebuilding.
5. Authenticate to `ghcr.io` with the workflow `GITHUB_TOKEN` and build with `docker/build-push-action` + `docker/setup-buildx-action`. Push two tags:
   - `ghcr.io/ai-blaise/openauth:<ver>-ai-blaise.<N>` (immutable image pin)
   - `ghcr.io/ai-blaise/openauth:<ver>-ai-blaise.latest` (rolling pointer for diagnostics; not consumed by the platform)
6. Generate an SPDX SBOM with `anchore/sbom-action`, scoped to the pushed digest, uploaded as a workflow artifact.
7. Install `cosign` via `sigstore/cosign-installer` and sign keyless. Signing is wrapped in a guard that logs and continues if Sigstore is unreachable, so image publication does not block on signing infrastructure availability.
8. Tag the commit `image-publish-<ver>-ai-blaise.<N>` and push the tag back to `origin` (skipped if the tag already exists).

All `uses:` references are SHA-pinned. Concurrency is serialized per ref so two pushes never race the same image tag.

## Suffix scheme (`ai-blaise.<N>`)

See `MODIFICATION.md` for the full definition. The workflow's `version` step resolves the upstream base in this priority order:

1. `refs/tags/@openauthjs/openauth@<ver>` (upstream package tag),
2. `refs/tags/v<ver>`,
3. `refs/remotes/upstream/master`,
4. `refs/remotes/upstream/main`.

`<N>` is `max(git rev-list --count <base>..HEAD, 1)` and `0` when no base resolves, with the same floor applied.

## Command-center consumption

`ai-blaise/command-center` consumes the published images in two places:

- `deploy/openauth/values.yaml` pins `workload.image.repository = ghcr.io/ai-blaise/openauth` and `workload.image.tag = <ver>-ai-blaise.<N>`. The chart's `commandCenter.contract` block pins `chartVersion` to the same string.
- `gitops/apps/14-openauth.yaml` consumes the values file under sync wave 6 in the `identity` namespace. Argo CD auto-sync is disabled by policy; the chart upgrade proposal action opens PRs on `<N>` bumps.

The platform image pull does not require additional credentials when the GHCR package's visibility is set to public; otherwise the cluster pulls with the platform-owned image-pull secret.

## Operator runbook

### Triggering a publication

- Merge to `master`: publication runs automatically.
- Ad-hoc rebuild without code change: `gh workflow run publish-image.yml --ref master` (or use the Actions UI). The workflow is idempotent: existing image tags overwrite (digest changes), and the git tag push is skipped if the tag already exists.

### Verifying a publication

```bash
crane ls ghcr.io/ai-blaise/openauth | tail
crane digest ghcr.io/ai-blaise/openauth:<ver>-ai-blaise.<N>
cosign verify --certificate-oidc-issuer https://token.actions.githubusercontent.com \
  --certificate-identity-regexp '^https://github.com/ai-blaise/openauth/' \
  ghcr.io/ai-blaise/openauth:<ver>-ai-blaise.<N>
```

The SBOM is attached as a workflow artifact named `openauth-<ver>-ai-blaise.<N>-sbom.spdx.json`.

### Bumping the upstream version

1. Rebase or merge upstream into `master`.
2. The upstream bump updates `packages/openauth/package.json .version`.
3. Push to `master`. The workflow recomputes `<N>` relative to the new upstream tag and publishes `<new-ver>-ai-blaise.<N>`.
4. Update `ai-blaise/command-center/deploy/openauth/values.yaml` and the chart's `chartVersion` to the new full tag; the contract gate enforces parity.

### Failure modes

| Failure                               | Behavior                                                                                 |
| ------------------------------------- | ---------------------------------------------------------------------------------------- | --- | ----------------------------- |
| Cosign / Sigstore unreachable         | Logged in step summary, workflow continues; the image is still pushed and SBOM-attached. |
| Tag `image-publish-<full_tag>` exists | Skipped (no-op); does not fail the workflow.                                             |
| Dockerfile missing                    | Workflow fails fast in the build step. Restore `Dockerfile` from history.                |
| Upstream remote unreachable           | The `git fetch upstream` step uses `                                                     |     | true`; `<N>`falls back to`1`. |

### Audit links

- Plan v5 §10 image-publication closure: `ai-blaise/command-center contracts/fork-contracts.json` and `contracts/repository-production-contracts.json`.
- This workflow satisfies the OpenAuth half of `AUDIT.md §5 #3`.
