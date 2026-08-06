#!/bin/bash
#
# publish-gocam-json-go-public.sh -- push the per-model Minerva JSON serving
# surface to s3://go-public/files/go-cam/ for the GO API (issue #24).
#
# WHAT THIS IS FOR. go-fastapi serves GO-CAM models by fetching INDIVIDUAL
# objects from S3 -- https://go-public.s3.amazonaws.com/files/go-cam/{id}.json
# (app/routers/models.py, ontology.py) -- and converting each via MinervaWrapper.
# That surface has no other producer. When it stops being written, the GO API
# silently freezes: AmiGO, the Alliance and the MOD pathway widgets all render
# GO-CAMs through the shared wc-gocam-viz component, whose default apiUrl is
# api.geneontology.org/api/go-cam/%ID. This is the step that keeps it fresh.
#
# SOURCE = THIS RUN'S OWN OUTPUT. Reads <tree>/internal/gocam-json-per-model/,
# staged by the build half (internal-all-gocam-products.sh) straight from the
# minerva-cli --dump-owl-json output, which derives from the single pinned
# noctua-models grab. It does NOT fetch from current.geneontology.org.
#
# The legacy job this replaces (geneontology/pipeline, branch
# issue-265-go-cam-products, never merged to master -- which is why it was
# invisible to sweeps of master) wget'd the tarball from current and untarred
# it. That ran as a de facto extension of the publish stages, so it was untidy
# rather than unsound; reading THIS run's staged output is simply cleaner, and
# it is insulated from the pending products/json/ rename (#26).
#
# OVERLAY-ONLY. Never deletes, exactly like publish-to-s3.sh. Models retired
# upstream keep their objects; pruning them is a separate, deliberate decision
# (they are ~1% of the prefix).
#
# THE ACL IS LOAD-BEARING. go-public has no bucket policy and no Public Access
# Block -- public readability comes purely from per-object ACLs (AllUsers:READ),
# which is why the legacy job used `s3cmd --acl-public` and why the arbre push
# (publish-arbre-go-public.sh) does the same. Upload WITHOUT --acl public-read
# and the objects are private; go-fastapi then gets a 403, which its code maps
# to DataNotFoundException -- i.e. a silent, indistinguishable "model not found"
# with nothing in the logs. Content-Type comes free: the aws CLI guesses
# application/json from the .json extension, matching the existing objects.
#
# DRY-RUN BY DEFAULT. The only mutation happens with --execute. In dry-run the
# push is previewed read-only with `aws s3 sync --dryrun`. Note that the preview
# lists every object it would write (~54k), so it takes a few minutes.
#
# DUAL-USE (hand-run now, Jenkins stage later -- same file, no logic change).
# Pure, flag-driven publish logic with no container/CI assumptions, so both:
#   - Human: run on skyhook (or via the repo `justfile`), e.g. `--tree ... --execute`.
#   - Jenkins (future): wrap in a stage like scripts/publish-stage.sh -- curl this
#     script, `docker run` a deps image (aws cli) with the LOCAL tree BIND-mounted
#     and the creds JSON mounted, and call it with `--execute --yes`. The
#     container/dep-install setup lives in the STAGE WRAPPER, not here.
#
# WHERE TO RUN: on skyhook itself, against the LOCAL tree -- no download, no
# mount. The source is ~54k small files read once each.
#
# Requirements (host-side): aws cli, and AWS push credentials JSON
# ({"accessKeyId":..., "secretAccessKey":...}).

set -euo pipefail

### Defaults (overridable).
TREE=""
CREDS="${HOME}/local/share/secrets/bbop/aws/s3/aws-go-push.json"
SRC_REL="internal/gocam-json-per-model"
BUCKET="go-public"
PREFIX="files/go-cam"
MIN_FILES=40000    # sanity floor: refuse to publish an obviously truncated dump
EXECUTE=0          # 0 = dry-run (default), 1 = actually mutate
ASSUME_YES=0
ALLOW_MISSING_DOI=0   # 1 = allow --execute without metadata/release-archive-doi.json present

log()  { echo "[publish-gocam-json] $*"; }
die()  { echo "[publish-gocam-json] ERROR: $*" >&2; exit 1; }

usage() {
    grep '^#' "$0" | sed 's/^# \{0,1\}//'
    cat <<'USAGE'

Usage:
  publish-gocam-json-go-public.sh --tree DIR [options]

Options:
  --tree DIR             Built (blessed) tree to publish from (required).
  --creds FILE           AWS push creds JSON (default: aws-go-push.json under ~/local/share/secrets).
  --src-rel PATH         Source dir relative to tree (default: internal/gocam-json-per-model).
  --bucket NAME          Destination bucket (default: go-public).
  --prefix PATH          Destination key prefix (default: files/go-cam).
  --min-files N          Sanity floor on the source file count (default: 40000).
  --allow-missing-doi    Allow --execute even if metadata/release-archive-doi.json is absent.
  --execute              ACTUALLY MUTATE. Without this, everything is a dry run.
  --yes                  Skip the interactive confirmation in --execute mode.
  -h, --help             This help.
USAGE
}

### Parse args.
while [ $# -gt 0 ]; do
    case "$1" in
        --tree)              TREE="$2"; shift 2;;
        --creds)             CREDS="$2"; shift 2;;
        --src-rel)           SRC_REL="$2"; shift 2;;
        --bucket)            BUCKET="$2"; shift 2;;
        --prefix)            PREFIX="$2"; shift 2;;
        --min-files)         MIN_FILES="$2"; shift 2;;
        --allow-missing-doi) ALLOW_MISSING_DOI=1; shift;;
        --execute)           EXECUTE=1; shift;;
        --yes)               ASSUME_YES=1; shift;;
        -h|--help)           usage; exit 0;;
        *) die "unknown argument: $1 (try --help)";;
    esac
done

[ -n "$TREE" ] || die "--tree is required"
[ -d "$TREE" ] || die "tree not found: $TREE"

SRC="$TREE/$SRC_REL"
[ -d "$SRC" ] || die "source dir not found: $SRC (did the build half stage it? see internal-all-gocam-products.sh)"

### Sanity: the dump is ~54k files. A near-empty or truncated source would
### overlay garbage onto a live serving surface, so refuse rather than guess.
NFILES="$(find "$SRC" -maxdepth 1 -name '*.json' -type f | wc -l)"
[ "$NFILES" -ge "$MIN_FILES" ] \
    || die "only $NFILES *.json in $SRC (floor $MIN_FILES) -- truncated dump? use --min-files to override deliberately"

### Use the push creds for the aws cli (one credential source).
[ -f "$CREDS" ] || die "creds JSON not found: $CREDS"
AWS_ACCESS_KEY_ID="$(python3 -c "import json,sys;print(json.load(open(sys.argv[1]))['accessKeyId'])" "$CREDS")"
AWS_SECRET_ACCESS_KEY="$(python3 -c "import json,sys;print(json.load(open(sys.argv[1]))['secretAccessKey'])" "$CREDS")"
AWS_DEFAULT_REGION="${AWS_DEFAULT_REGION:-us-east-1}"
export AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_DEFAULT_REGION

command -v aws >/dev/null 2>&1 || die "missing the aws CLI"

### Order guard: same Zenodo-before-publish rule as publish-to-s3.sh. The DOI
### file in the tree is our cheapest available proxy for "this tree has been
### blessed" -- this is a publish-half step and must not run against an
### unblessed build.
if [ "$EXECUTE" = 1 ] && [ "$ALLOW_MISSING_DOI" != 1 ] && [ ! -f "$TREE/metadata/release-archive-doi.json" ]; then
    die "no $TREE/metadata/release-archive-doi.json -- mint the Zenodo DOI first ('just zenodo-mint-main'), or pass --allow-missing-doi"
fi

### Banner.
MODE="DRY-RUN (no mutations)"; [ "$EXECUTE" = 1 ] && MODE="EXECUTE (LIVE MUTATIONS)"
cat <<BANNER
========================================================================
  publish-gocam-json-go-public -- GO API serving surface (#24)
  mode:            $MODE
  tree:            $TREE
  source:          $SRC ($NFILES *.json)
  destination:     s3://$BUCKET/$PREFIX/
  push mode:       overlay-only (never deletes; preserves existing objects)
  object ACL:      public-read (REQUIRED -- go-public has no bucket policy)
========================================================================
BANNER

if [ "$EXECUTE" = 1 ] && [ "$ASSUME_YES" != 1 ]; then
    log "About to make LIVE changes to s3://$BUCKET/$PREFIX/ (the GO API's model source)."
    read -r -p "Type PUBLISH to proceed: " confirm
    [ "$confirm" = "PUBLISH" ] || die "not confirmed; aborting"
fi

### The push.
if [ "$EXECUTE" = 1 ]; then
    log "Syncing $NFILES objects -> s3://$BUCKET/$PREFIX/ (public-read, no --delete)..."
    aws s3 sync "$SRC/" "s3://$BUCKET/$PREFIX/" --acl public-read --only-show-errors
    log "Sync complete."
else
    log "DRY-RUN push preview (aws s3 sync --dryrun) -> s3://$BUCKET/$PREFIX/"
    log "(lists every object it would write; on a full dump this takes a few minutes)"
    aws s3 sync "$SRC/" "s3://$BUCKET/$PREFIX/" --acl public-read --dryrun
fi

log "Done. ($MODE)"
