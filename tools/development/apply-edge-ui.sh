#!/bin/sh
#
# apply-edge-ui.sh
#
# Re-applies the Edge-style overflow-menu ("≡") instrumentation to the
# browser app Swift sources. The upstream `engine/firefox` submodule is NOT
# touched by this patch; only the app-side `browser/Reynard/...` Swift files
# are modified, so this runs independently of `apply-patches.sh`.
#
# Why this exists
# ---------------
# The Edge UI lives in `browser/Reynard/...`, which is part of this repo (the
# app), not the Gecko engine submodule. On every upstream sync the app sources
# can change, so we keep the Edge UI customisation as a single replayable
# unified-diff and apply it on top of whatever upstream shipped. Because the
# app stack is compiled by `tools/release/build-app.sh` against the
# `Reynard.xcodeproj` (whose `Reynard` folder uses synchronized root groups),
# any new Swift file we add under `browser/Reynard/...` is picked up
# automatically; no `project.pbxproj` edit is ever needed.
#
# Usage
# -----
#   ./tools/development/apply-edge-ui.sh [--non-interactive]
#
# Idempotent: if the patch is already applied it exits 0 immediately.

set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT_DIR=$(CDPATH= cd -- "$SCRIPT_DIR/../.." && pwd)
PATCH_FILE="$ROOT_DIR/patches/edge-ui.patch"
BROWSER_DIR="$ROOT_DIR/browser"

# Non-interactive mode (used by CI): fail instead of prompting on conflict.
NON_INTERACTIVE=false
for argument in "$@"; do
	case "$argument" in
		--non-interactive)
			NON_INTERACTIVE=true
			;;
	esac
done

if [ ! -f "$PATCH_FILE" ]; then
	echo "Missing Edge UI patch: $PATCH_FILE"
	exit 1
fi

if [ ! -d "$BROWSER_DIR" ]; then
	echo "Missing browser directory: $BROWSER_DIR"
	exit 1
fi

echo "Applying Edge UI patch."
echo "  patch:  $PATCH_FILE"
echo "  target: $BROWSER_DIR"

# Idempotency: if the patch is already applied, `git apply --reverse --check`
# succeeds, so we skip rather than failing on a fresh tree that already has our
# tooling committed. We must not let `set -e` abort on the non-zero (not
# applied) case, hence the `if`.
if git -C "$ROOT_DIR" -c core.autocrlf=false apply --reverse --check "$PATCH_FILE" >/dev/null 2>&1; then
	echo "Edge UI patch is already applied; nothing to do."
	exit 0
fi

# git apply works relative to the repo root. `--3way` lets the patch merge when
# context around the edit moves between upstream revisions. `--whitespace=nowarn`
# keeps CRLF/LF noise from aborting the apply.
if ! git -C "$ROOT_DIR" -c core.autocrlf=false apply --3way --whitespace=nowarn "$PATCH_FILE"; then
	echo "Failed to apply edge-ui.patch."
	if [ "$NON_INTERACTIVE" = "true" ]; then
		echo "Non-interactive mode: aborting."
		exit 1
	fi
	echo "Resolve conflicts in $BROWSER_DIR, then press Enter to continue or type q to stop."
	read response
	if [ "$response" = "q" ] || [ "$response" = "Q" ]; then
		exit 1
	fi
fi

echo "Finished applying the Edge UI patch."
