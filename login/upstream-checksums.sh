#!/bin/sh
# Records the checksums of the upstream files login/overrides replaces (and the upstream login
# Dockerfile the runtime stage copies) for a Zitadel tag, after the overrides were updated to it.
#
# Usage: login/upstream-checksums.sh <zitadel tag>     e.g. login/upstream-checksums.sh v4.20.0
set -eu

here=$(cd "$(dirname "$0")" && pwd)
tag=${1:?usage: upstream-checksums.sh <zitadel tag>}
lock="$here/upstream.sha256"

files=$(awk '{ print $2 }' "$lock")
tmp=$(mktemp)

for file in $files; do
	sum=$(curl -fsSL "https://raw.githubusercontent.com/zitadel/zitadel/$tag/$file" | sha256sum | cut -d' ' -f1)
	echo "$sum  $file"
done >"$tmp"

mv "$tmp" "$lock"
echo "Updated $lock for $tag; also set ZITADEL_VERSION=$tag in login/Dockerfile."
cat "$lock"
