#!/usr/bin/env bash
set -euo pipefail

version="${1:-}"
if ! [[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "usage: scripts/package.sh <major.minor.patch>" >&2
  exit 2
fi

root="$(cd "$(dirname "$0")/.." && pwd)"
bash "$root/scripts/check-tag.sh" "v$version"

zip="statewide-$version.zip"
rm -f "$zip"
(cd "$root" && zip -rqX "$OLDPWD/$zip" statewide -x '*.DS_Store')
echo "$zip"
