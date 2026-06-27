#!/usr/bin/env bash
#
# zenodo-mint.sh -- run a production mint recipe (upload + PUBLISH in one go) and
# HARD-VERIFY it minted a DOI. PROMPTS for typed confirmation first (IRREVERSIBLE).
# LOUD-FAIL on any issue.
# Usage:  zenodo-mint.sh <recipe> <doi-file> <TREE-copy>
#
set -euo pipefail
recipe="${1:-}"; doifile="${2:-}"; TREE="${3:-${TREE:-}}"
REPO="${REPO:-$HOME/local/src/git/pipeline-from-goa}"
fail(){ echo "" >&2; echo "FATAL: $*" >&2; exit 1; }
if [ -z "$recipe" ] || [ -z "$doifile" ] || [ -z "$TREE" ]; then fail "usage: $0 <recipe> <doi-file> <TREE>"; fi
[ -n "${ZENODO_TOKEN:-}" ] || fail "export ZENODO_TOKEN (production) first"

echo "*** ABOUT TO MINT via '$recipe' -- uploads the tarball and PUBLISHES it ***"
echo "    This is IRREVERSIBLE and mints a PERMANENT DOI that cannot be deleted."
printf "Type PUBLISH to proceed (anything else aborts): "
read -r confirm || confirm=""
[ "$confirm" = "PUBLISH" ] || fail "not confirmed -- aborted, NOTHING minted"

echo "=== just tree=$TREE $recipe ==="
rm -f "$doifile"   # a stale file must not masquerade as success
if ! ( cd "$REPO" && just tree="$TREE" "$recipe" ); then
    fail "recipe '$recipe' FAILED -- mint did not complete. Check Zenodo state before re-running."
fi
[ -f "$doifile" ] || fail "recipe returned 0 but $doifile was NOT written -- treat as FAILED."
doi=$(python3 -c "import json,sys;print(json.load(open(sys.argv[1]))['doi'])" "$doifile") \
    || fail "$doifile is not valid JSON with a 'doi'."
[ -n "$doi" ] || fail "$doifile has an empty doi."
echo ""
echo "MINTED OK: $recipe  doi=$doi  ->  $doifile"
