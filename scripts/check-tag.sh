#!/usr/bin/env bash
set -euo pipefail

tag="${1:-${GITHUB_REF_NAME:-}}"
if [ -z "$tag" ]; then
  echo "usage: scripts/check-tag.sh v<version>" >&2
  exit 2
fi

root="$(cd "$(dirname "$0")/.." && pwd)"
manifest="$(sed -n "s/^version '\(.*\)'$/\1/p" "$root/statewide/fxmanifest.lua")"
want="${tag#v}"

if [ -z "$manifest" ]; then
  echo "statewide/fxmanifest.lua has no version line" >&2
  exit 1
fi
if [ "$want" != "$manifest" ]; then
  echo "tag $tag does not match fxmanifest.lua version $manifest" >&2
  exit 1
fi
echo "tag $tag matches fxmanifest.lua version $manifest"
