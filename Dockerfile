FROM ghcr.io/zitadel/zitadel:latest AS zitadel
FROM gcr.leicraftmc.de/leicraftmc/auth/laviac:latest AS laviac
FROM gcr.leicraftmc.de/leicraftmc/auth/login-ui:latest AS login-ui

FROM oven/bun:1-slim

RUN apt-get update && apt-get install -y --no-install-recommends curl ca-certificates \
    && rm -rf /var/lib/apt/lists/*

COPY --from=zitadel /etc/passwd /etc/passwd
COPY --from=zitadel /etc/ssl/certs /etc/ssl/certs
COPY --from=zitadel /app/zitadel /app/zitadel

HEALTHCHECK NONE
EXPOSE 8080

USER zitadel
ENTRYPOINT ["/app/zitadel"]