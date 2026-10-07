#!/bin/bash
# Zitadel (supervisord program zitadel, docker/conf/services.ini).
#
# LCMC_AUTH_ZITADEL_INITMODE decides how the database is prepared. Both modes are idempotent and run
# on every start:
# - auto (default): start-from-init. Zitadel creates its database user, the database and the grants
#   with the Postgres admin login (ZITADEL_DATABASE_POSTGRES_ADMIN_*), then its schemas, then starts.
# - manual: the user and the database exist already. Only the schema step runs, with the service
#   user (ZITADEL_DATABASE_POSTGRES_USER_*), then start-from-setup. No admin login is needed.
#
# The master key is LCMC_AUTH_ZITADEL_MASTERKEY, or ZITADEL_MASTERKEY if that is unset.
# --masterkeyFromEnv reads only ZITADEL_MASTERKEY, so it is exported under that name.
set -euo pipefail

zitadel=/opt/leicraftmc/auth/zitadel/zitadel-bin

export ZITADEL_MASTERKEY="${LCMC_AUTH_ZITADEL_MASTERKEY:-${ZITADEL_MASTERKEY:-}}"
if [ -z "$ZITADEL_MASTERKEY" ]; then
	echo "LCMC_AUTH_ZITADEL_MASTERKEY is not set" >&2
	exit 1
fi

case "${LCMC_AUTH_ZITADEL_INITMODE:-auto}" in
	auto)
		exec "$zitadel" start-from-init --masterkeyFromEnv
		;;
	manual)
		# The schema step is `init zitadel` up to v4.19.4. Later versions rename it to `init schema`
		# and keep `zitadel` as an alias. On v4.19.4, `init schema` silently runs the full init.
		"$zitadel" init zitadel
		exec "$zitadel" start-from-setup --masterkeyFromEnv
		;;
	*)
		echo "LCMC_AUTH_ZITADEL_INITMODE must be auto or manual, not '$LCMC_AUTH_ZITADEL_INITMODE'" >&2
		exit 1
		;;
esac
