#!/bin/zsh
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
#   ./tools/development/apply-edge-ui.sh
#
# It is safe to run on a clean upstream checkout: new files are created, and
# the small edits to existing files are applied with `git apply --3way`, so
# they merge even when the surrounding code shifted.

set -euo pipefail

SCRIPT_DIR="${0:A:h}"
ROOT_DIR="${SCRIPT_DIR:h:h}"
PATCH_FILE="$ROOT_DIR/patches/edge-ui.patch"
BROWSER_DIR="$ROOT_DIR/browser"

# Non-interactive mode (used by CI): fail instead of prompting on conflict.
NON_INTERACTIVE=false
if [[ "${1:-}" == "--non-interactive" ]]; then
	NON_INTERACTIVE=true
fi

if [[ ! -f "$PATCH_FILE" ]]; then
	echo "Missing Edge UI patch: $PATCH_FILE"
	exit 1
fi

if [[ ! -d "$BROWSER_DIR" ]]; then
	echo "Missing browser directory: $BROWSER_DIR"
	exit 1
fi

echo "Applying Edge UI patch to $BROWSER_DIR ..."

# Idempotency: if the patch is already applied, `git apply --reverse --check`
# succeeds, so we skip rather than failing on a fresh upstream that already has
# our tooling committed.
if git -C "$ROOT_DIR" -c core.autocrlf=false apply --reverse --check "$PATCH_FILE" >/dev/null 2>&1; then
	echo "Edge UI patch is already applied; nothing to do."
	exit 0
fi

# git apply works relative to the repo root. `--3way` lets the patch merge when
# context around the edit moves between upstream revisions. `--whitespace=nowarn`
# keeps CRLF/LF noise from aborting the apply.
if ! git -C "$ROOT_DIR" -c core.autocrlf=false apply --3way --whitespace=nowarn "$PATCH_FILE"; then
	echo "Failed to apply edge-ui.patch."
	if [[ "$NON_INTERACTIVE" == "true" ]]; then
		echo "Non-interactive mode: aborting."
		exit 1
	fi
	echo "Resolve conflicts in $BROWSER_DIR, then press Enter to continue or type q to stop."
	read -r response
	if [[ "$response" == "q" || "$response" == "Q" ]]; then
		exit 1
	fi
fi

echo "Finished applying the Edge UI patch."
