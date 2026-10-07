#!/bin/bash
set -euo pipefail


if [ -z "${LCMC_AUTH_ZITADEL_MASTERKEY:-}" ]; then
	echo "LCMC_AUTH_ZITADEL_MASTERKEY is not set" >&2
	exit 1
fi

if [ "${LCMC_AUTH_ZITADEL_INITMODE}" = "manual" ]; then

	/opt/leicraftmc/auth/zitadel/zitadel-bin init schema
	/opt/leicraftmc/auth/zitadel/zitadel-bin start-from-init --masterkeyFromEnv

elif [ "${LCMC_AUTH_ZITADEL_INITMODE}" = "auto" ]; then

	/opt/leicraftmc/auth/zitadel/zitadel-bin start-from-setup --masterkeyFromEnv

else
	echo "LCMC_AUTH_ZITADEL_INITMODE is not set to a valid value (manual or auto)" >&2
	exit 1
fi

