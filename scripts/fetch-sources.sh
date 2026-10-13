#!/usr/bin/env bash
# Check out the pinned Yabadabadoo and RetroArch commits into workdir/src and
# apply this repository's patches. Re-running resets each tree to its pin
# first, so a stale or hand-edited checkout never reaches a build.
#
#   scripts/fetch-sources.sh [WORKDIR]
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORKDIR="${1:-$REPO_ROOT/workdir}"
LOCK="$REPO_ROOT/upstream.lock.json"

lock_get() {
    python3 -I -c 'import json,sys
v = json.load(open(sys.argv[1]))
for k in sys.argv[2:]:
    v = v[k]
print(v)' "$LOCK" "$@"
}

fetch_pinned() {
    local name="$1" dir="$WORKDIR/src/$1"
    local repo commit
    repo="$(lock_get "$name" repo)"
    commit="$(lock_get "$name" commit)"

    if [ ! -d "$dir/.git" ]; then
        mkdir -p "$dir"
        git -C "$dir" init -q
        git -C "$dir" remote add origin "$repo"
    fi
    if ! git -C "$dir" cat-file -e "$commit^{commit}" 2>/dev/null; then
        echo "=== Fetching $name $commit"
        git -C "$dir" fetch -q --depth 1 origin "$commit"
    fi
    git -C "$dir" -c advice.detachedHead=false checkout -q --force "$commit"
    git -C "$dir" clean -q -fdx
    if [ "$(git -C "$dir" rev-parse HEAD)" != "$commit" ]; then
        echo "$name: checkout is not at the pinned commit $commit" >&2
        exit 1
    fi

    local patch
    for patch in "$REPO_ROOT/patches/$name"/*.patch; do
        [ -e "$patch" ] || continue
        echo "=== Applying $name/$(basename "$patch")"
        git -C "$dir" apply --whitespace=nowarn "$patch"
    done
}

fetch_pinned yabadabadoo
fetch_pinned retroarch
echo "Sources ready in $WORKDIR/src"
