#!/usr/bin/env bash
#
# bless-precheck.sh -- pre-flight checks for the pipeline-from-goa "bless".
# READ-ONLY: `test -w` only checks permission; nothing is written or mutated.
# Run via `just tree=<copy> precheck`, or directly as below.
#
# COPY-FIRST: the bless writes into the tree (the Zenodo mint writes the DOI JSON,
# the index pass writes index.html), so point TREE at a writable COPY of the build
# tree -- never the single original (e.g. rsync /home/skyhook/.../main -> a work dir).
#
# Usage:   bless-precheck.sh [TREE]
#   TREE          release tree to publish FROM -- a COPY (arg $1 or $TREE env;
#                 default /home/skyhook/pipeline-from-goa/main)
#   SRC           (optional env) original tree -> file-count copy-integrity compare
#   CREDS         (optional env) AWS push creds JSON
#                 (default $HOME/local/share/secrets/bbop/aws/s3/aws-go-push.json)
#   REPO          (optional env) pipeline-from-goa checkout (default ~/local/src/git/pipeline-from-goa)
#   ZENODO_TOKEN  (env) production Zenodo token
#
set -u

TREE="${1:-${TREE:-/home/skyhook/pipeline-from-goa/main}}"
SRC="${SRC:-}"
CREDS="${CREDS:-$HOME/local/share/secrets/bbop/aws/s3/aws-go-push.json}"
REPO="${REPO:-$HOME/local/src/git/pipeline-from-goa}"
MAIN_CONCEPT=1205166
PRODUCTS_CONCEPT=10946933
ARCH="$TREE/internal/release-archives/go-release-archive.tgz"
PRODF="$TREE/internal/release-archives/go-release-products.tgz"

FAILED=0
pass(){ printf '  \033[32m\xe2\x9c\x93\033[0m %s\n' "$1"; }
warn(){ printf '  \033[33m\xe2\x9a\xa0\033[0m %s\n' "$1"; }
fail(){ printf '  \033[31m\xe2\x9c\x97\033[0m %s\n' "$1"; FAILED=1; }

echo "pipeline-from-goa bless pre-check"
echo "  TREE   = $TREE"
echo "  CREDS  = $CREDS"
echo "  whoami = $(whoami)"
echo

echo "=== A. reviewed scripts (REPO=$REPO) ==="
if [ -f "$REPO/scripts/publish-to-s3.sh" ]; then
    if grep -q -- '--exclude internal' "$REPO/scripts/publish-to-s3.sh"; then
        pass "publish-to-s3.sh has --exclude internal (reviewed version)"
    else
        fail "publish-to-s3.sh missing --exclude (stale checkout)"
    fi
    if grep -q 'release-archive-doi.json' "$REPO/scripts/publish-to-s3.sh"; then
        pass "Zenodo-before-publish guard present"
    else
        fail "DOI guard missing"
    fi
    if command -v git >/dev/null && git -C "$REPO" rev-parse HEAD >/dev/null 2>&1; then
        echo "  HEAD: $(git -C "$REPO" log --oneline -1)"
    fi
else
    warn "checkout not found at $REPO -- skipping script-version check"
fi

echo "=== B. copy integrity / writability ==="
if [ -d "$TREE" ]; then pass "tree exists"; else fail "tree missing: $TREE"; fi
if [ -n "$SRC" ] && [ -d "$SRC" ]; then
    sc=$(find "$SRC" 2>/dev/null | wc -l)
    cc=$(find "$TREE" 2>/dev/null | wc -l)
    if [ "$sc" = "$cc" ]; then pass "file count matches source ($cc)"
    else warn "count differs: src $sc vs copy $cc"; fi
fi
wf=0
for d in products reports annotations go-cams metadata ontology release_stats; do
    if [ ! -w "$TREE/$d" ]; then fail "NOT writable: $d/"; wf=1; fi
done
[ "$wf" = 0 ] && pass "all served dirs writable as $(whoami)"

echo "=== C. tree contents (#86 output) ==="
if [ -f "$TREE/summary.txt" ]; then
    sd=$(awk -F': ' '/^Start date:/{print $2; exit}' "$TREE/summary.txt")
    pass "summary.txt (Start date: ${sd:-?})"
    if grep -q 'note software versions' "$TREE/summary.txt"; then
        warn "summary.txt still has the software-versions TODO (archived in the DOI as-is)"
    fi
else
    fail "summary.txt missing"
fi
if [ -f "$ARCH" ];  then pass "main archive     $(du -h "$ARCH"  2>/dev/null | cut -f1)"; else fail "main archive missing:     $ARCH"; fi
if [ -f "$PRODF" ]; then pass "products archive $(du -h "$PRODF" 2>/dev/null | cut -f1)"; else fail "products archive missing: $PRODF"; fi
if [ -f "$TREE/metadata/release-archive-doi.json" ]; then
    warn "DOI file already present (stale? the mint overwrites it)"
else
    pass "DOI file absent (expected pre-mint)"
fi

echo "=== D. tooling ==="
if command -v aws >/dev/null; then pass "aws ($(aws --version 2>&1 | awk '{print $1}'))"; else fail "aws cli missing"; fi
if command -v just >/dev/null; then pass "just ($(just --version 2>&1 | awk '{print $2}'))"; else fail "just missing -> sudo apt-get install -y just"; fi
if python3 -c 'import pystache, boto3, filechunkio' 2>/dev/null; then
    pass "python: pystache + boto3 + filechunkio"
else
    fail "python deps missing -> pip3 install --user --break-system-packages pystache filechunkio"
fi

echo "=== E. AWS push identity (the creds that will write S3/CloudFront) ==="
if [ -f "$CREDS" ]; then
    pass "creds JSON present"
    aki=$(python3 -c "import json,sys;print(json.load(open(sys.argv[1]))['accessKeyId'])" "$CREDS" 2>/dev/null)
    ask=$(python3 -c "import json,sys;print(json.load(open(sys.argv[1]))['secretAccessKey'])" "$CREDS" 2>/dev/null)
    arn=$(AWS_ACCESS_KEY_ID="$aki" AWS_SECRET_ACCESS_KEY="$ask" \
          aws sts get-caller-identity --query Arn --output text 2>/dev/null)
    if [ -n "$arn" ]; then pass "identity: $arn"; else fail "creds JSON did not authenticate"; fi
else
    fail "creds JSON missing: $CREDS"
fi

echo "=== F. Zenodo PRODUCTION token + concept reachability ==="
if [ -n "${ZENODO_TOKEN:-}" ]; then
    pass "ZENODO_TOKEN set (len ${#ZENODO_TOKEN})"
    # -L: a concept-record id (e.g. 1205166) 302-redirects to its latest VERSION
    # record; the uploader (urllib) follows redirects, so we follow here too and
    # check the FINAL code. (A version-record id like 10946933 answers 200 directly.)
    for c in "$MAIN_CONCEPT" "$PRODUCTS_CONCEPT"; do
        code=$(curl -sSL -o /dev/null -w '%{http_code}' -H "Authorization: Bearer $ZENODO_TOKEN" \
               "https://zenodo.org/api/records/$c" 2>/dev/null)
        if [ "$code" = "200" ]; then pass "concept $c reachable (200, redirects followed)"
        else fail "concept $c -> HTTP $code (token/access?)"; fi
    done
else
    fail "ZENODO_TOKEN not set -- export the PRODUCTION token"
fi

echo
if [ "$FAILED" = 0 ]; then
    echo "PRE-CHECK: ALL GREEN -- next:  just tree=\"$TREE\" publish-dry"
else
    echo "PRE-CHECK: ISSUES ABOVE -- resolve before anything mutating"
fi
exit "$FAILED"
