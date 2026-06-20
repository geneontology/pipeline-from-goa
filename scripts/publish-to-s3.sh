#!/bin/bash
#
# Publish the built skyhook tree to S3 -- Phase 5 of the bless tail
# (docs/release-runbook.md). This is the SIX-step index/copy/capper/invalidate
# sequence, faithful to the legacy Publish stage (the old pipeline Jenkinsfile
# L942-987):
#
#   1. directory_indexer.py over the tree with the dated-RELEASE prefix (-x -u)
#   2. push tree (minus internal/) -> go-data-product-release/$DATE
#   3. bucket-indexer.py -> release-root "capper" catalog -> PUT release/index.html
#   4. directory_indexer.py over the SAME tree with the CURRENT prefix (-x)
#   5. push tree (minus internal/) -> go-data-product-current
#   6. CloudFront invalidation -- BOTH distributions
#
# Two indexer passes are REQUIRED, not an optimization target: directory_indexer
# bakes an absolute URL prefix into every index.html (current.geneontology.org vs
# release.geneontology.org/$DATE), so the same on-disk tree cannot serve both
# buckets -- it must be re-indexed per destination.
#
# DRY-RUN BY DEFAULT. The three real mutations happen only with --execute:
#   - the two pushes -- legacy go-site s3-uploader.py (the OLD pipeline's tool;
#     controlled Content-Types via its MIME map, default text/plain; OVERLAY-ONLY,
#     it never deletes). In dry-run the push is previewed read-only with
#     `aws s3 sync --dryrun` instead (shows the file delta vs S3; no writes).
#   - the capper index.html PUT to the release bucket root (skipped in dry-run)
#   - the CloudFront invalidations (printed, not issued, in dry-run)
# directory_indexer runs without -x in dry-run (its own built-in dry mode -> no
# index.html written to the tree); bucket-indexer is read-only (list_objects) and
# always runs for real.
#
# OVERLAY-ONLY / FIRST ROLLOUT: the push never deletes. Existing objects in
# go-data-product-current (the OLD pipeline's files) are PRESERVED -- required for
# the initial cutover so current.geneontology.org keeps serving prior files via
# CloudFront. Pruning stale objects is deliberately deferred (a later decision).
#
# CONTENT-TYPE NOTE: we reuse s3-uploader.py (per CLAUDE.md "don't reinvent the
# publish tooling") for legacy-faithful Content-Types. Its MIME map defaults to
# text/plain with overrides (json->application/json, gz->application/gzip,
# obo->text/obo, owl->application/rdf+xml, ttl->text/turtle, ...). Plain aws s3
# sync would instead guess application/octet-stream for .gaf/.gpad/.gpi/.obo/.owl/
# .gz (-> download rather than inline). Revisiting the map is a later improvement.
#
# Zenodo (Phase 4: mint the DOI + write metadata/release-archive-doi.json) is a
# SEPARATE, EARLIER step -- scripts/zenodo-archive-upload.py -- run before this.
# This script does not touch Zenodo.
#
# This is a HAND-RUN operator script (the build/publish split keeps the mutating
# tail out of the automated Jenkins build), not a Jenkins stage.
#
# Requirements (host-side): aws cli, python3 + pystache + boto3 + filechunkio
# (s3-uploader.py imports filechunkio), and AWS push credentials JSON
# ({"accessKeyId":..., "secretAccessKey":...}). The go-site tooling
# (directory_indexer.py, bucket-indexer.py, s3-uploader.py,
# directory-index-template.html) is fetched fresh unless --gosite-scripts is given.
#
# The tree: point --tree at the built skyhook tree. Mount it first, e.g.:
#   sshfs -o ro -o IdentityFile=<skyhook_key> skyhook@<host>:/home/skyhook/pipeline-from-goa/main /tmp/pfg-tree
# (use a read-WRITE mount for --execute, since pass 1/4 write index.html into the tree).

set -euo pipefail

### Defaults (overridable).
TREE=""
DATE=""
CREDS="${HOME}/local/share/secrets/bbop/aws/s3/aws-go-push.json"
GOSITE_REF="master"
GOSITE_SCRIPTS=""
RELEASE_BUCKET="go-data-product-release"
CURRENT_BUCKET="go-data-product-current"
CURRENT_CF="E3Q4YIZHZL7358"
RELEASE_CF="E2HF1DWYYDLTQP"
RELEASE_HOST="http://release.geneontology.org"
CURRENT_HOST="http://current.geneontology.org"
EXECUTE=0          # 0 = dry-run (default), 1 = actually mutate
ASSUME_YES=0
KEEP_INTERNAL_LINK=0  # 1 = don't relocate internal/ (accept a dangling index link)

log()  { echo "[publish-to-s3] $*"; }
die()  { echo "[publish-to-s3] ERROR: $*" >&2; exit 1; }

usage() {
    grep '^#' "$0" | sed 's/^# \{0,1\}//'
    cat <<'USAGE'

Usage:
  publish-to-s3.sh --tree DIR [options]

Options:
  --tree DIR             Built tree to publish (required).
  --date YYYY-MM-DD      Dated-release stamp (default: parsed from <tree>/summary.txt).
  --creds FILE           AWS push creds JSON (default: aws-go-push.json under ~/local/share/secrets).
  --gosite-ref REF       go-site branch/tag to fetch tooling from (default: master).
  --gosite-scripts DIR   Use local go-site scripts dir instead of fetching.
  --release-bucket NAME  Default: go-data-product-release.
  --current-bucket NAME  Default: go-data-product-current.
  --keep-internal-link   Don't relocate internal/ during --execute (accept a dangling index link).
  --execute              ACTUALLY MUTATE. Without this, everything is a dry run.
  --yes                  Skip the interactive confirmation in --execute mode.
  -h, --help             This help.
USAGE
}

### Parse args.
while [ $# -gt 0 ]; do
    case "$1" in
        --tree)            TREE="$2"; shift 2;;
        --date)            DATE="$2"; shift 2;;
        --creds)           CREDS="$2"; shift 2;;
        --gosite-ref)      GOSITE_REF="$2"; shift 2;;
        --gosite-scripts)  GOSITE_SCRIPTS="$2"; shift 2;;
        --release-bucket)  RELEASE_BUCKET="$2"; shift 2;;
        --current-bucket)  CURRENT_BUCKET="$2"; shift 2;;
        --keep-internal-link) KEEP_INTERNAL_LINK=1; shift;;
        --execute)         EXECUTE=1; shift;;
        --yes)             ASSUME_YES=1; shift;;
        -h|--help)         usage; exit 0;;
        *) die "unknown argument: $1 (try --help)";;
    esac
done

[ -n "$TREE" ] || die "--tree is required"
[ -d "$TREE" ] || die "tree not found: $TREE"

### Resolve the dated-release stamp.
if [ -z "$DATE" ]; then
    [ -f "$TREE/summary.txt" ] || die "no --date and no $TREE/summary.txt to parse"
    DATE="$(awk -F': ' '/^Start date:/{print $2; exit}' "$TREE/summary.txt" | tr -d '[:space:]')"
fi
echo "$DATE" | grep -qE '^[0-9]{4}-[0-9]{2}-[0-9]{2}$' || die "date not YYYY-MM-DD: '$DATE'"

### Get the go-site tooling in hand.
WORK="$(mktemp -d)"
STASHED=0
ASIDE="$(dirname "$TREE")/.pfg-internal-aside.$$"
cleanup() {
    if [ "$STASHED" = 1 ] && [ -d "$ASIDE" ]; then
        if mv "$ASIDE" "$TREE/internal"; then
            log "Restored internal/ into the tree."
        else
            log "WARNING: could not restore internal/ from $ASIDE -- move it back by hand!"
        fi
    fi
    rm -rf "$WORK"
}
trap cleanup EXIT
if [ -n "$GOSITE_SCRIPTS" ]; then
    DINDEXER="$GOSITE_SCRIPTS/directory_indexer.py"
    BINDEXER="$GOSITE_SCRIPTS/bucket-indexer.py"
    SUPLOADER="$GOSITE_SCRIPTS/s3-uploader.py"
    TEMPLATE="$GOSITE_SCRIPTS/directory-index-template.html"
else
    log "Fetching go-site tooling from ref '$GOSITE_REF'..."
    for f in directory_indexer.py bucket-indexer.py s3-uploader.py directory-index-template.html; do
        curl -fsSL "https://raw.githubusercontent.com/geneontology/go-site/${GOSITE_REF}/scripts/$f" -o "$WORK/$f" \
            || die "could not fetch $f from go-site@$GOSITE_REF"
    done
    DINDEXER="$WORK/directory_indexer.py"
    BINDEXER="$WORK/bucket-indexer.py"
    SUPLOADER="$WORK/s3-uploader.py"
    TEMPLATE="$WORK/directory-index-template.html"
fi
[ -f "$CREDS" ] || die "creds JSON not found: $CREDS"

### Use the push creds for the aws cli too (one credential source).
AWS_ACCESS_KEY_ID="$(python3 -c "import json,sys;print(json.load(open(sys.argv[1]))['accessKeyId'])" "$CREDS")"
AWS_SECRET_ACCESS_KEY="$(python3 -c "import json,sys;print(json.load(open(sys.argv[1]))['secretAccessKey'])" "$CREDS")"
export AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY

### Preflight: the real push tool (s3-uploader.py) imports cleanly (only --execute).
if [ "$EXECUTE" = 1 ]; then
    python3 -c "import boto3, filechunkio" 2>/dev/null \
        || die "real push needs python modules boto3 + filechunkio (pip install boto3 filechunkio)"
fi

### Banner.
MODE="DRY-RUN (no mutations)"; [ "$EXECUTE" = 1 ] && MODE="EXECUTE (LIVE MUTATIONS)"
cat <<BANNER
========================================================================
  publish-to-s3 -- Phase 5 bless tail
  mode:            $MODE
  tree:            $TREE
  date:            $DATE
  release:         s3://$RELEASE_BUCKET/$DATE/   (CF $RELEASE_CF, $RELEASE_HOST)
  current:         s3://$CURRENT_BUCKET/         (CF $CURRENT_CF, $CURRENT_HOST)
  push mode:       overlay-only (never deletes; preserves existing objects)
========================================================================
BANNER

if [ "$EXECUTE" = 1 ] && [ "$ASSUME_YES" != 1 ]; then
    log "About to make LIVE changes to S3 + CloudFront. (Zenodo DOI should already be minted.)"
    read -r -p "Type PUBLISH to proceed: " confirm
    [ "$confirm" = "PUBLISH" ] || die "not confirmed; aborting"
fi

### --- Step helpers ---

index_tree() { # $1=prefix  $2=up-flag(""/"-u")
    local prefix="$1" up="$2" xflag="" note="dry: no index.html written"
    if [ "$EXECUTE" = 1 ]; then xflag="-x"; note="writing index.html into tree"; fi
    log "Indexing tree: prefix='$prefix' ${up:+up=yes }($note)"
    # shellcheck disable=SC2086
    python3 "$DINDEXER" -v --inject "$TEMPLATE" --directory "$TREE" --prefix "$prefix" $xflag $up >/dev/null
}

push_tree() { # $1=s3 dest (bucket[/path])
    local dest="$1"
    if [ "$EXECUTE" = 1 ]; then
        # Real push: legacy go-site s3-uploader.py -- controlled Content-Types
        # (MIME map, default text/plain) and OVERLAY-ONLY (never deletes, so
        # existing/old objects are preserved). internal/ is already relocated
        # aside (maybe_stash_internal), so it is not walked/uploaded.
        log "Push (s3-uploader.py, legacy MIME map, overlay-only) -> s3://$dest/"
        python3 "$SUPLOADER" -v --credentials "$CREDS" --directory "$TREE" \
            --bucket "$dest" --number "$DATE" --pipeline pipeline-from-goa >/dev/null
    else
        # Dry preview only: the file delta vs S3 (read-only). internal/ excluded.
        log "DRY-RUN push preview (aws s3 sync --dryrun) -> s3://$dest/ (exclude internal/*)"
        aws s3 sync "$TREE/" "s3://$dest/" --exclude "internal/*" --dryrun
    fi
}

build_and_put_capper() {
    local out="$WORK/top-level-index.html"
    log "Building release-root capper (read-only list of $RELEASE_BUCKET)..."
    python3 "$BINDEXER" --credentials "$CREDS" --bucket "$RELEASE_BUCKET" \
        --inject "$TEMPLATE" --prefix "$RELEASE_HOST" > "$out"
    log "Capper built ($(wc -l < "$out") lines, $(wc -c < "$out") bytes): $out"
    if [ "$EXECUTE" = 1 ]; then
        log "PUT capper -> s3://$RELEASE_BUCKET/index.html"
        aws s3 cp "$out" "s3://$RELEASE_BUCKET/index.html" --content-type text/html
    else
        log "DRY-RUN: would PUT capper -> s3://$RELEASE_BUCKET/index.html (content-type text/html)"
    fi
}

invalidate() { # $1=cf-id  $2=label
    if [ "$EXECUTE" = 1 ]; then
        log "CloudFront invalidation: $2 ($1) /*"
        aws cloudfront create-invalidation --distribution-id "$1" --paths "/*"
    else
        log "DRY-RUN: would invalidate CloudFront $2 ($1) /*"
    fi
}

maybe_stash_internal() {
    # internal/ must never be published AND must not appear in the directory
    # index. Neither directory_indexer.py nor s3-uploader.py has an --exclude, so
    # relocate internal/ out of the tree for the --execute run (index + real push
    # both then skip it). The dry-run aws-sync preview uses --exclude internal/*
    # instead. (A go-site --exclude flag would let us drop this relocation.)
    [ -d "$TREE/internal" ] || return 0
    if [ "$KEEP_INTERNAL_LINK" = 1 ]; then
        log "WARNING: --keep-internal-link: internal/ will be a DANGLING link in the published index."
        return 0
    fi
    if [ "$EXECUTE" = 1 ]; then
        log "Relocating internal/ out of the indexed tree -> $ASIDE"
        mv "$TREE/internal" "$ASIDE" \
            || die "could not relocate internal/ (is $(dirname "$TREE") writable? mount /home/skyhook). Use --keep-internal-link to override."
        STASHED=1
    else
        log "DRY-RUN: would relocate internal/ out of the tree for --execute (left in place here; push still excludes internal/*)."
    fi
}

### --- The six steps (release -> current -> invalidate) ---

maybe_stash_internal
log "STEP 1/6: index for RELEASE"
index_tree "$RELEASE_HOST/$DATE" "-u"
log "STEP 2/6: push -> release (dated)"
push_tree "$RELEASE_BUCKET/$DATE"
log "STEP 3/6: release-root capper"
build_and_put_capper
log "STEP 4/6: re-index for CURRENT"
index_tree "$CURRENT_HOST" ""
log "STEP 5/6: push -> current"
push_tree "$CURRENT_BUCKET"
log "STEP 6/6: invalidate BOTH distributions"
invalidate "$RELEASE_CF" "release"
invalidate "$CURRENT_CF" "current"

log "Done ($MODE)."
[ "$EXECUTE" = 1 ] || log "This was a DRY RUN. Re-run with --execute (and a read-write tree) to publish for real."
