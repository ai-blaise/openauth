# syntax=docker/dockerfile:1.7
# ai-blaise OpenAuth mirror image (Path A rebuild).
#
# Why this exists: upstream toolbeam/openauth is a library distributed via npm.
# The Command Center platform (ai-blaise/command-center) consumes OpenAuth as a
# containerized issuer service on port 3000. This Dockerfile produces the
# container that ghcr.io/ai-blaise/openauth:<ver>-ai-blaise.<N> resolves to.
#
# The runtime entrypoint is examples/issuer/bun/issuer.ts. Operators override
# providers and storage at deploy time through the platform helm chart
# (deploy/openauth/values.yaml). The image bundles the workspace package
# @openauthjs/openauth so adapters injected at runtime resolve correctly.
ARG BUN_VERSION=1.1.42

FROM oven/bun:${BUN_VERSION}-alpine AS deps
WORKDIR /workspace
COPY package.json bun.lockb* tsconfig.json ./
COPY packages/openauth/package.json packages/openauth/package.json
COPY examples/issuer/bun/package.json examples/issuer/bun/package.json
COPY www/package.json www/package.json
RUN --mount=type=cache,target=/root/.bun/install/cache \
    bun install --frozen-lockfile --production=false || bun install

FROM deps AS build
COPY packages/openauth packages/openauth
COPY examples/subjects.ts examples/subjects.ts
COPY examples/issuer/bun examples/issuer/bun
WORKDIR /workspace/packages/openauth
RUN bun run build

FROM oven/bun:${BUN_VERSION}-alpine AS runtime
ENV NODE_ENV=production \
    PORT=3000 \
    OPENAUTH_PORT=3000
WORKDIR /app
RUN addgroup -S openauth && adduser -S openauth -G openauth
COPY --from=build /workspace/package.json ./package.json
COPY --from=build /workspace/packages/openauth ./packages/openauth
COPY --from=build /workspace/examples/issuer/bun ./examples/issuer/bun
COPY --from=build /workspace/examples/subjects.ts ./examples/subjects.ts
COPY --from=build /workspace/node_modules ./node_modules
USER openauth
EXPOSE 3000
LABEL org.opencontainers.image.source="https://github.com/ai-blaise/openauth" \
      org.opencontainers.image.title="openauth" \
      org.opencontainers.image.description="ai-blaise mirror of OpenAuth (bun runtime)" \
      org.opencontainers.image.licenses="MIT"
CMD ["bun", "run", "examples/issuer/bun/issuer.ts"]
