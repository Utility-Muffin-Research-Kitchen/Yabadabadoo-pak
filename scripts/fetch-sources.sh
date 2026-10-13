#!/usr/bin/env bash
# Check out the pinned Yabadabadoo and RetroArch commits into workdir/src and
# apply this repository's patches. Re-running resets each tree to its pin
# first, so a stale or hand-edited checkout never reaches a build.
#
# RetroArch gets, in this order:
#   1. Leaf's MLP1 patch set, vendored in patches/retroarch/leaf/ and applied
#      in the order SOURCE.json lists (scripts/check-patches.py checks the
#      files against it first), so Leaf can drive this RetroArch like its own;
#   2. this pak's own patches, patches/retroarch/pak/*.patch, which are written
#      to apply on top of the first set.
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
}

apply_patch() { # apply_patch NAME PATCH-FILE
    echo "=== Applying ${2#"$REPO_ROOT"/patches/}"
    git -C "$WORKDIR/src/$1" apply --whitespace=nowarn "$2"
}

fetch_pinned yabadabadoo
for patch in "$REPO_ROOT"/patches/yabadabadoo/*.patch; do
    [ -e "$patch" ] && apply_patch yabadabadoo "$patch"
done

fetch_pinned retroarch
# check-patches.py verifies the vendored files against SOURCE.json and prints
# them in apply order; a plain assignment keeps its failure fatal under set -e.
leaf_patches="$(python3 -I "$REPO_ROOT/scripts/check-patches.py" list)"
while IFS= read -r patch; do
    apply_patch retroarch "$patch"
done <<<"$leaf_patches"
for patch in "$REPO_ROOT"/patches/retroarch/pak/*.patch; do
    [ -e "$patch" ] && apply_patch retroarch "$patch"
done

echo "Sources ready in $WORKDIR/src"
