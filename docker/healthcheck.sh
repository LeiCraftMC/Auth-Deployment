#!/bin/sh
# Container health: Zitadel, the login and LAVIAC all answer their liveness endpoint.
set -e

curl -fsS -o /dev/null --max-time 5 "http://localhost:${ZITADEL_PORT:-8080}/debug/healthz"
curl -fsS -o /dev/null --max-time 5 "http://localhost:${LOGIN_PORT:-12192}/ui/v2/login/healthy"
curl -fsS -o /dev/null --max-time 5 "http://localhost:${NITRO_PORT:-12191}/api/health"
