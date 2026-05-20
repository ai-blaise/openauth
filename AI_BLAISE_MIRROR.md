# OpenAuth Mirror

`ai-blaise/openauth` is the source of truth for OpenAuth changes needed by the command-center platform.

The initial platform integration consumes OpenAuth from `ai-blaise/platform` through an OIDC Backstage auth module and a Citus-backed storage adapter. This mirror keeps future auth changes in the ai-blaise namespace while retaining a clean rebase path from `anomalyco/openauth`.
