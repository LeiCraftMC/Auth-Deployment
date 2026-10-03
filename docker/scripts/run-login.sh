#!/bin/bash
# The Zitadel login (supervisord program login, docker/conf/services.ini).
#
# Its environment is every LCMC_AUTH_LOGIN_* variable of the container with the prefix removed:
# LCMC_AUTH_LOGIN_AUDIENCE becomes AUDIENCE, LCMC_AUTH_LOGIN_ZITADEL_API_URL becomes ZITADEL_API_URL.
# Apart from PATH and HOME it gets nothing else, so it never sees the Zitadel or LAVIAC variables, and
# Zitadel, which reads every ZITADEL_* variable as configuration, never sees the login's.
#
# The defaults below are the settings of upstream's login image (apps/login/Dockerfile, pinned in
# login/upstream.sha256); LCMC_AUTH_LOGIN_* overrides them. It runs on Bun instead of upstream's
# Node, without upstream's SSL_CERT_DIR preload: the login talks to the Zitadel in this container
# over plain HTTP.
set -euo pipefail

login_env=()
for name in "${!LCMC_AUTH_LOGIN_@}"; do
	login_env+=("${name#LCMC_AUTH_LOGIN_}=${!name}")
done

# The fixed assignments below (PORT, HOSTNAME, NODE_ENV, ...) are defaults, not hard overrides:
# "${login_env[@]}" is expanded after them, and env uses the last occurrence of a repeated name.
# So setting e.g. LCMC_AUTH_LOGIN_PORT appends a second PORT= that wins over the default here
# (the health check probes ${LCMC_AUTH_LOGIN_PORT:-12192} to match). The same holds for HOSTNAME etc.
exec env -i \
	PATH="$PATH" \
	HOME="$HOME" \
	HOSTNAME="::" \
	PORT=12192 \
	NODE_ENV=production \
	"${login_env[@]}" \
	./entrypoint.sh bun apps/login/server.js
