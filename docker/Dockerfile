# syntax=docker/dockerfile:1
#
# LeiCraft_MC Auth: Zitadel, the Zitadel login with the LeiCraft_MC theme and LAVIAC in one image.
# supervisord runs the three processes (docker/conf/services.ini; README.md: ports, routing,
# configuration).
#
#   docker build -t lcmc-auth .

# Zitadel and its login always come from the same tag.
ARG ZITADEL_VERSION=v4.19.4

FROM ghcr.io/zitadel/zitadel:${ZITADEL_VERSION} AS zitadel
FROM gcr.leicraftmc.de/leicraftmc/auth/laviac:latest AS laviac

# --- login: upstream apps/login built from source with login/overrides (login/README.md) ---------
# Node 22 and a glibc image like upstream's CI (.github/workflows/ci.yml, pack.yml).
FROM node:22-bookworm AS login
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

# Fails if upstream changed a file the overrides replace (login/upstream.sha256).
COPY login/apply-overrides.sh login/upstream.sha256 /lcmc/
COPY login/overrides /lcmc/overrides
RUN sh /lcmc/apply-overrides.sh /zitadel

# What `nx run @zitadel/login:build` runs: protos (buf) -> client (tsup) -> login (next build,
# standalone output in apps/login/.next/standalone).
RUN pnpm --filter @zitadel/proto run generate \
    && pnpm --filter @zitadel/client run build \
    && pnpm --filter @zitadel/login run build

# --- bundle --------------------------------------------------------------------------------------
FROM oven/bun:1-slim

RUN apt-get update && apt-get install -y --no-install-recommends curl ca-certificates tini supervisor \
    && rm -rf /var/lib/apt/lists/* \
    && useradd --system --uid 10001 --user-group --home-dir /opt/leicraftmc/auth --shell /usr/sbin/nologin leicraftmc

# Zitadel
COPY --from=zitadel /app/zitadel /opt/leicraftmc/auth/zitadel/zitadel-bin

# Login (upstream's standalone output: server, entrypoint.sh, ...), run on Bun like LAVIAC
COPY --from=login --chown=leicraftmc:leicraftmc /zitadel/apps/login/.next/standalone /opt/leicraftmc/auth/login

# LAVIAC (settings as in its image)
COPY --from=laviac /opt/leicraftmc/auth/laviac/app /opt/leicraftmc/auth/laviac/app
RUN install -d -o leicraftmc -g leicraftmc /opt/leicraftmc/auth/laviac/data /opt/leicraftmc/auth/laviac/config
ENV NITRO_ENV=production
ENV NITRO_HOST=::
ENV NITRO_PORT=12191
ENV LAVIAC_DB_PATH=/opt/leicraftmc/auth/laviac/data/db.sqlite
ENV LAVIAC_DB_AUTO_MIGRATE=true
ENV LAVIAC_DB_MIGRATION_DIR=/opt/leicraftmc/auth/laviac/app/drizzle/migrations
ENV LAVIAC_CONFIG_BASE_DIR=/opt/leicraftmc/auth/laviac/config

VOLUME /opt/leicraftmc/auth/laviac/data
VOLUME /opt/leicraftmc/auth/laviac/config

# supervisord and the login wrapper (docker/scripts/run-login.sh)
COPY docker/conf/services.ini /etc/supervisor/supervisord.conf
COPY --chmod=0755 docker/scripts /opt/leicraftmc/auth/scripts

# Zitadel 8080, login 12192 (under /ui/v2/login), LAVIAC 12191
EXPOSE 8080/tcp 12192/tcp 12191/tcp

HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=3 \
    CMD ["/opt/leicraftmc/auth/scripts/healthcheck.sh"]

USER leicraftmc
WORKDIR /opt/leicraftmc/auth

ENTRYPOINT ["/usr/bin/tini", "--", "/usr/bin/supervisord", "--configuration", "/etc/supervisor/supervisord.conf"]
