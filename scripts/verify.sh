#!/usr/bin/env bash
# Verification gate: shell lint + placeholder-only content.
# Run it before every commit; CI runs the same script on push and pull request.
set -euo pipefail
cd "$(dirname "$0")/.."

# find's exit status is invisible through a process substitution, so a partial
# walk would shorten the list and still lint clean. Materialising it first lets
# set -e see the failure.
listing="$(mktemp)"
trap 'rm -f "$listing"' EXIT
find . -name '*.sh' -not -path './.git/*' -print0 > "$listing"
mapfile -d '' -t scripts < "$listing"
[ "${#scripts[@]}" -gt 0 ] || { echo "verify: no scripts found" >&2; exit 1; }
shellcheck "${scripts[@]}"


# This tree describes a vault without holding one. The way it stops doing that
# is a value from the original arriving with a mirrored change, after which the
# two trees agree and no comparison between them can notice — so the check runs
# from this side and asks only what this side can answer.
# shellcheck source=scripts/placeholder-check.sh
. scripts/placeholder-check.sh
placeholder_selftest
placeholder_check

echo "secrets-example verify OK (${#scripts[@]} scripts)"
