#!/bin/bash
# Runs Zitadel, the Zitadel login and LAVIAC in one container (tini is PID 1).
#
# The container arguments are the Zitadel command (Dockerfile default: start-from-init
# --masterkeyFromEnv --tlsMode external), like with the Zitadel image. Every output line is prefixed
# with the process name. When one process exits, the others are stopped and the container exits
# with its status, so the orchestrator restarts the bundle as a whole. SIGTERM stops all three.
set -uo pipefail

LOGIN_DIR=/opt/leicraftmc/auth/login
LAVIAC_DIR=/opt/leicraftmc/auth/laviac

run_zitadel() {
	exec /usr/local/bin/zitadel "$@"
}

# The settings of upstream's login image (apps/login/Dockerfile, pinned in login/upstream.sha256),
# exported for this process only: Zitadel reads ZITADEL_* as configuration too. Runs on Bun instead
# of upstream's Node, without upstream's SSL_CERT_DIR preload: the login talks to the Zitadel in
# this container over plain HTTP.
run_login() {
	cd "$LOGIN_DIR" || exit 1
	export HOSTNAME="::" \
		PORT="${LOGIN_PORT:-12192}" \
		NODE_ENV=production \
		ZITADEL_TLS_ENABLED=false \
		ZITADEL_API_URL="${ZITADEL_API_URL:-http://localhost:${ZITADEL_PORT:-8080}}" \
		OTEL_SERVICE_NAME="${OTEL_SERVICE_NAME:-zitadel-login}" \
		OTEL_EXPORTER_OTLP_PROTOCOL="${OTEL_EXPORTER_OTLP_PROTOCOL:-http/protobuf}"
	exec ./entrypoint.sh bun apps/login/server.js
}

run_laviac() {
	cd "$LAVIAC_DIR" || exit 1
	exec bun run "$LAVIAC_DIR/app/.output/server/index.mjs"
}

declare -A names=()

start() {
	local name=$1
	shift
	"$@" > >(exec sed -u "s/^/[$name] /") 2>&1 &
	names[$!]=$name
}

stop() {
	trap - TERM INT
	kill -TERM "${!names[@]}" 2>/dev/null
	wait "${!names[@]}" 2>/dev/null
}

trap 'echo "[bundle] stopping" >&2; stop; exit 143' TERM INT

start zitadel run_zitadel "$@"
start login run_login
start laviac run_laviac

exited=""
wait -n -p exited "${!names[@]}"
status=$?

echo "[bundle] ${names[${exited:-0}]:-a process} exited with status $status, stopping the others" >&2
stop
exit "$status"
