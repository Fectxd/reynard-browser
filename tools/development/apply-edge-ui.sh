#!/bin/sh
#
# apply-edge-ui.sh
#
# Replays the Edge UI customisation (tools/edge-ui/edge-ui.patch plus the
# binary files in tools/edge-ui/overlay/) onto the app sources in browser/.
# The Gecko engine (engine/, patches/) is not touched; that is handled by
# apply-patches.sh as upstream does.
#
# Usage
# -----
#   ./tools/development/apply-edge-ui.sh [--non-interactive] [--from-upstream <ref>]
#
#   --from-upstream <ref>  First reset browser/, engine/ and patches/ to <ref>
#                          (e.g. upstream/main),
#                          then apply the patch. This is what CI does, so every
#                          build proves the patch still applies to the latest
#                          upstream instead of re-building already-edited files.
#   --non-interactive      Fail instead of prompting on conflicts (CI).
#
# Without --from-upstream the script is idempotent: if the patch is already
# applied to the working tree it only refreshes the overlay files.

set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT_DIR=$(CDPATH= cd -- "$SCRIPT_DIR/../.." && pwd)
EDGE_DIR="$ROOT_DIR/tools/edge-ui"
PATCH_FILE="$EDGE_DIR/edge-ui.patch"
OVERLAY_DIR="$EDGE_DIR/overlay"

NON_INTERACTIVE=false
UPSTREAM_REF=""
while [ $# -gt 0 ]; do
	case "$1" in
		--non-interactive)
			NON_INTERACTIVE=true
			;;
		--from-upstream)
			shift
			UPSTREAM_REF=${1:?--from-upstream needs a ref}
			;;
		*)
			echo "Unknown argument: $1"
			exit 2
			;;
	esac
	shift
done

if [ ! -f "$PATCH_FILE" ]; then
	echo "Missing Edge UI patch: $PATCH_FILE"
	exit 1
fi

cd "$ROOT_DIR"

copy_overlay() {
	if [ -d "$OVERLAY_DIR" ]; then
		echo "Copying overlay files from tools/edge-ui/overlay/."
		cp -R "$OVERLAY_DIR/." "$ROOT_DIR/"
	fi
	python3 -I "$EDGE_DIR/merge-strings.py" "$EDGE_DIR/strings.json" \
		"$ROOT_DIR/browser/Reynard/Resources/Localizable.xcstrings"
}

if [ -n "$UPSTREAM_REF" ]; then
	echo "Resetting browser/ to $UPSTREAM_REF ($(git rev-parse --short "$UPSTREAM_REF"))."
	git rm -r -q --cached browser >/dev/null
	rm -rf browser
	git checkout "$UPSTREAM_REF" -- browser
	# Keep the Gecko engine pin and engine patches in step with that upstream
	# revision too, so the app and engine sources always match.
	git checkout "$UPSTREAM_REF" -- engine patches
elif git -c core.autocrlf=false apply --reverse --check "$PATCH_FILE" >/dev/null 2>&1; then
	echo "Edge UI patch is already applied."
	copy_overlay
	exit 0
fi

echo "Applying $PATCH_FILE"
# --3way lets hunks merge when upstream moved the surrounding code; the
# pre-image blobs come from this repository's history.
if ! git -c core.autocrlf=false apply --3way --whitespace=nowarn "$PATCH_FILE"; then
	echo "Failed to apply edge-ui.patch."
	git diff --name-only --diff-filter=U || true
	if [ "$NON_INTERACTIVE" = "true" ]; then
		echo "Non-interactive mode: aborting. Rebase the patch onto the new upstream and run tools/edge-ui/regenerate-patch.sh."
		exit 1
	fi
	echo "Resolve conflicts in browser/, then press Enter to continue or type q to stop."
	read response
	if [ "$response" = "q" ] || [ "$response" = "Q" ]; then
		exit 1
	fi
fi

copy_overlay
echo "Finished applying the Edge UI patch."
