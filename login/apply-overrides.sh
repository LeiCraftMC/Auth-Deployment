#!/bin/sh
# Copies login/overrides/ over a zitadel/zitadel checkout (paths mirror the upstream repository).
#
# Before copying it makes sure nothing upstream changes silently:
#   - every upstream file an override replaces still has the checksum recorded in upstream.sha256
#     (the version the override was made from), otherwise upstream changes would be dropped;
#   - every file the overrides add (not listed in upstream.sha256) does not exist upstream.
#
# Usage: login/apply-overrides.sh <zitadel checkout>
set -eu

here=$(cd "$(dirname "$0")" && pwd)
checkout=${1:?usage: apply-overrides.sh <zitadel checkout>}
cd "$checkout"

if ! sha256sum --check --quiet "$here/upstream.sha256"; then
	cat >&2 <<-EOF

		Upstream changed a file that login/overrides replaces (listed above as FAILED).
		Re-apply the "LCMC:" changes of the override on top of the new upstream file, then record the
		new upstream checksums:  login/upstream-checksums.sh <zitadel tag>
	EOF
	exit 1
fi

overrides=$(cd "$here/overrides" && find . -type f | sed 's|^\./||' | sort)

for file in $overrides; do
	if ! grep -q "  $file\$" "$here/upstream.sha256" && [ -e "$file" ]; then
		echo "Upstream now contains $file, which login/overrides adds as a new file." >&2
		echo "Rename the override or merge it with the upstream file and list it in upstream.sha256." >&2
		exit 1
	fi
done

cp -R "$here/overrides/." .

echo "Applied login/overrides:"
for file in $overrides; do
	if grep -q "  $file\$" "$here/upstream.sha256"; then
		echo "  replaced  $file"
	else
		echo "  added     $file"
	fi
done
