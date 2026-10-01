# syntax=docker/dockerfile:1
#
# The Zitadel login (apps/login of zitadel/zitadel) built from source with the LeiCraft_MC theme.
# Nothing is forked: apply-overrides.sh copies overrides/ (theme files only) over a fresh checkout
# of ZITADEL_VERSION and fails the build if upstream changed a file it replaces (upstream.sha256).
# The runtime stage is upstream's apps/login/Dockerfile, checksum-pinned the same way.
#
#   docker build -t zitadel-login-lcmc login/

ARG ZITADEL_VERSION=v4.19.2

# --- build ---------------------------------------------------------------------------------------
# Node 22 and a glibc image like upstream's CI (.github/workflows/ci.yml, pack.yml).
FROM node:22-bookworm AS build
ARG ZITADEL_VERSION
ENV CI=true \
    NEXT_TELEMETRY_DISABLED=1 \
    COREPACK_ENABLE_DOWNLOAD_PROMPT=0
RUN npm install --global corepack@latest && corepack enable

WORKDIR /zitadel
# Only what the login build needs: the root files, the login, its workspace packages, the protos.
RUN git clone --quiet --depth 1 --branch "${ZITADEL_VERSION}" --filter=blob:none --sparse \
        https://github.com/zitadel/zitadel.git . \
    && git sparse-checkout set --no-cone '/*' '!/*/' '/apps/login/' '/packages/' '/proto/'

# The login with its workspace packages (@zitadel/client, @zitadel/proto) and the root (buf).
RUN --mount=type=cache,id=pnpm-store,target=/root/.local/share/pnpm/store \
    pnpm install --frozen-lockfile --filter "@zitadel/login..." --filter "{.}"

COPY apply-overrides.sh upstream.sha256 /lcmc/
COPY overrides /lcmc/overrides
RUN sh /lcmc/apply-overrides.sh /zitadel

# What `nx run @zitadel/login:build` runs: protos (buf) -> client (tsup) -> login (next build,
# standalone output in apps/login/.next/standalone).
RUN pnpm --filter @zitadel/proto run generate \
    && pnpm --filter @zitadel/client run build \
    && pnpm --filter @zitadel/login run build

# --- runtime: upstream apps/login/Dockerfile ---------------------------------------------------
FROM node:24-alpine
WORKDIR /app
RUN addgroup --system --gid 1001 nodejs && \
    adduser --system --uid 1001 nextjs
# If /.env-file/.env is mounted into the container, its variables are made available to the server before it starts up.
RUN mkdir -p /.env-file && touch /.env-file/.env && chown -R nextjs:nodejs /.env-file

COPY --from=build --chown=nextjs:nodejs /zitadel/apps/login/.next/standalone ./

USER nextjs
ENV HOSTNAME="::" \
    PORT="3000" \
    NODE_ENV="production" \
    NODE_OPTIONS="--use-openssl-ca --require /app/load-ssl-cert-dir.cjs" \
    SSL_CERT_FILE="/etc/ssl/certs/ca-certificates.crt" \
    ZITADEL_TLS_ENABLED="false" \
    OTEL_SERVICE_NAME="zitadel-login" \
    OTEL_EXPORTER_OTLP_PROTOCOL="http/protobuf"

HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD ["/usr/local/bin/node", "/app/healthcheck.mjs", "/ui/v2/login/ready"]
ENTRYPOINT ["/app/entrypoint.sh", "node", "apps/login/server.js"]
