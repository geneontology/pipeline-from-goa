#!/usr/bin/env bash
#
# zenodo-publish-draft.sh -- publish an existing, reviewed Zenodo DRAFT (e.g. a good
# --no-publish rehearsal draft) and write its DOI into the tree, WITHOUT re-uploading.
# Refuses to publish a draft with no committed file. PROMPTS for typed confirmation
# (publishing is IRREVERSIBLE -- a published record cannot be deleted). LOUD-FAIL.
# Usage:  zenodo-publish-draft.sh <draft-id> <doi-output-file>
#
set -euo pipefail
id="${1:-}"; out="${2:-}"
fail(){ echo "" >&2; echo "FATAL: $*" >&2; exit 1; }
if [ -z "$id" ] || [ -z "$out" ]; then fail "usage: $0 <draft-id> <doi-output-file>"; fi
[ -n "${ZENODO_TOKEN:-}" ] || fail "export ZENODO_TOKEN (production) first"
A="Authorization: Bearer $ZENODO_TOKEN"

echo "=== draft $id: verify it has a committed file before publishing ==="
files=$(curl -fsS -H "$A" "https://zenodo.org/api/records/$id/draft/files") \
    || fail "could not GET draft $id files (already published? wrong id? bad token?)"
info=$(printf '%s' "$files" | python3 -c "
import sys, json
e = json.load(sys.stdin).get('entries', [])
g = [x for x in e if (x.get('size') or 0) > 0 and x.get('checksum')]
print(g[0]['key'], g[0]['size'], g[0]['checksum']) if g else print('')
") || fail "could not parse draft files for $id"
[ -n "$info" ] || fail "draft $id has NO committed file -- refusing to publish an empty record"
echo "  committed file: $info"

echo ""
echo "*** ABOUT TO PUBLISH draft $id -- this is IRREVERSIBLE and mints a PERMANENT DOI ***"
echo "    Review it first in the UI: https://zenodo.org/uploads/$id"
printf "Type PUBLISH to proceed (anything else aborts): "
read -r confirm || confirm=""
[ "$confirm" = "PUBLISH" ] || fail "not confirmed -- aborted, NOTHING published"

echo "=== publishing draft $id ==="
curl -fsS -X POST -H "$A" "https://zenodo.org/api/records/$id/draft/actions/publish" >/dev/null \
    || fail "publish POST failed for draft $id (transient? re-check the record state before retrying)"

echo "=== capture DOI + write into tree ==="
doi=$(curl -fsS -H "$A" "https://zenodo.org/api/records/$id" \
      | python3 -c "import sys, json; print(json.load(sys.stdin).get('doi') or '')") \
    || fail "could not read published record $id"
[ -n "$doi" ] || fail "record $id published but no top-level DOI returned"
mkdir -p "$(dirname "$out")"
printf '{\n  "doi": "%s"\n}\n' "$doi" > "$out"
python3 -c "import json,sys; assert json.load(open(sys.argv[1]))['doi']" "$out" \
    || fail "wrote $out but it failed validation"
echo ""
echo "PUBLISHED OK: draft $id  doi=$doi  ->  $out"
