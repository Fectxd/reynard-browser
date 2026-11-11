#!/bin/sh
#
# regenerate-patch.sh
#
# Rebuilds tools/edge-ui/edge-ui.patch from the current working tree.
# The patch is the diff of browser/ against the upstream commit this branch is
# based on (merge-base with upstream/main). Binary files are never put in the
# patch; they live under tools/edge-ui/overlay/ and are copied by
# apply-edge-ui.sh instead.
#
# Usage: ./tools/edge-ui/regenerate-patch.sh [upstream-ref]   (default: upstream/main)

set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
UPSTREAM_REF=${1:-upstream/main}
PATCH_FILE="$ROOT_DIR/tools/edge-ui/edge-ui.patch"

cd "$ROOT_DIR"
BASE=$(git merge-base HEAD "$UPSTREAM_REF")

# Include new, not-yet-committed files in the diff.
git add -A -N browser

git -c core.autocrlf=false diff --no-color --no-ext-diff "$BASE" -- browser \
	':(exclude)browser/Reynard/Resources/Localizable.xcstrings' \
	':(exclude,glob)browser/**/*.png' \
	':(exclude,glob)browser/**/*.jpg' \
	':(exclude,glob)browser/**/*.pdf' > "$PATCH_FILE"

# Edge strings are merged by key (see merge-strings.py), not patched.
python3 -I - "$BASE" <<'PY'
import json, subprocess, sys
path = "browser/Reynard/Resources/Localizable.xcstrings"
base = json.loads(subprocess.check_output(["git", "show", f"{sys.argv[1]}:{path}"]))["strings"]
with open(path, encoding="utf-8") as handle:
    current = json.load(handle)["strings"]
edge = {key: value for key, value in current.items() if base.get(key) != value}
with open("tools/edge-ui/strings.json", "w", encoding="utf-8") as handle:
    json.dump({"strings": dict(sorted(edge.items()))}, handle, ensure_ascii=False, indent=2)
    handle.write("\n")
print(f"Wrote tools/edge-ui/strings.json ({len(edge)} strings).")
PY

echo "Wrote $PATCH_FILE against $(git rev-parse --short "$BASE") ($UPSTREAM_REF)."
echo "$(grep -c '^diff --git' "$PATCH_FILE") files."
