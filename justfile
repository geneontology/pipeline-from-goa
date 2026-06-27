# Publish tail (the "bless") for pipeline-from-goa -- operator recipes.
#
# HAND-RUN, human-gated, in order, on the build/storage host (== the Jenkins machine,
# e.g. fryer). COPY-FIRST: the bless WRITES into the tree (the mint writes the DOI
# JSON; the index pass writes index.html), so first copy the build tree to a writable
# work dir and point `tree` at the COPY -- never mutate the single original (worst
# case = re-copy and retry). The build half (Jenkins) staged the archive tarballs in
# internal/release-archives/. These recipes are SAFE BY DEFAULT: bare `just`
# lists them; `zenodo-test` is sandbox-only; `precheck`/`publish-dry` mutate nothing.
# The only real mutations are `zenodo-mint-*` (mints DOIs) and `publish` (which
# prompts for a typed PUBLISH). See docs/release-runbook.md (Phases 4-5).
#
# Bless order, by hand, reviewing between steps. First copy + point `tree` at it:
#   rsync -a /home/skyhook/pipeline-from-goa/main/ /home/bbop/release-work/main/
#   then prefix every recipe:  just tree=/home/bbop/release-work/main <recipe>
#   0. just tree=<copy> precheck # read-only pre-flight (scripts, copy, creds, Zenodo)
#   1. just zenodo-rehearse-main / zenodo-rehearse-products  # PROD: upload -> unpublished DRAFT per concept
#   2. review BOTH drafts in the Zenodo UI (title/creators/version/file+size); see docs/zenodo-archival.md
#   3. just zenodo-publish-draft-main <id> / zenodo-publish-draft-products <id>  # publish the REVIEWED drafts (typed PUBLISH); writes the DOIs
#   4. just publish-dry          # review the full S3 + CloudFront plan (no mutations)
#   5. just publish              # PROD: index -> push -> capper -> invalidate (typed PUBLISH)
#   6. just verify
# Publish the reviewed draft -- do NOT discard a good draft and re-upload. The one-shot
# zenodo-mint-* recipes upload+publish together; run them ONLY via gated scripts/zenodo-mint.sh.

# --- config (override on the CLI, e.g. `just tree=/mnt/skyhook/... publish-dry`) ---
scripts          := justfile_directory() / "scripts"
tree             := "/home/skyhook/pipeline-from-goa/main"                                   # LOCAL tree on skyhook (run recipes ON skyhook)
creds            := env_var('HOME') / "local/share/secrets/bbop/aws/s3/aws-go-push.json"     # AWS push creds JSON
skyhook_host     := "SET-ME"                                                                 # the private SKYHOOK_MACHINE ssh host
skyhook_key      := env_var('HOME') / "local/share/secrets/bbop/ssh-keys/id_rsa_nopass.skyhook"
main_concept     := "1205166"      # Zenodo concept: "Gene Ontology Data Archive" (main / reproducible)
products_concept := "10946933"     # Zenodo concept: "Secondary Products"
archive          := tree / "internal/release-archives/go-release-archive.tgz"
products         := tree / "internal/release-archives/go-release-products.tgz"
doi_file         := tree / "metadata/release-archive-doi.json"
products_doi_file := tree / "metadata/release-archive-products-doi.json"

# list the recipes (default)
default:
    @just --list --unsorted

# print the bless order
bless-order:
    @sed -n '/^# Bless order/,/just verify/p' {{justfile_directory()}}/justfile | sed 's/^# \{0,1\}//'

# read-only pre-flight before the bless (reviewed scripts, copy writability, push creds, Zenodo reachability)
precheck:
    bash {{scripts}}/bless-precheck.sh {{tree}}

# OFF-HOST FALLBACK ONLY (prefer running ON skyhook). Set skyhook_host=<host> and tree=/tmp/pfg-tree first.
mount:
    @[ "{{skyhook_host}}" != "SET-ME" ] || { echo "set skyhook_host=<host> first (off-host fallback only)"; exit 1; }
    mkdir -p {{tree}}
    sshfs -o IdentitiesOnly=true -o IdentityFile={{skyhook_key}} skyhook@{{skyhook_host}}:/home/skyhook/pipeline-from-goa/main {{tree}}

# unmount the off-host sshfs mount
unmount:
    fusermount -u {{tree}}

# OPTIONAL rehearsal on the Zenodo SANDBOX (needs $ZENODO_SANDBOX_TOKEN + a SANDBOX concept id); never touches production
zenodo-test file concept:
    python3 {{scripts}}/zenodo-archive-upload.py --sandbox --no-publish --concept {{concept}} --file {{file}} --version-from {{tree}}/summary.txt

# PROD REHEARSAL (GATING): upload the main archive to REAL Zenodo but DON'T publish --
# leaves a draft version on concept 1205166 for UI review (validates metadata reuse vs
# the legacy concept). Needs $ZENODO_TOKEN. Discard the draft after review (see docs).
zenodo-rehearse-main:
    python3 {{scripts}}/zenodo-archive-upload.py --production --no-publish --concept {{main_concept}} --file {{archive}} --version-from {{tree}}/summary.txt

# PROD REHEARSAL (GATING): same for the secondary-products concept 10946933. Needs $ZENODO_TOKEN.
zenodo-rehearse-products:
    python3 {{scripts}}/zenodo-archive-upload.py --production --no-publish --concept {{products_concept}} --file {{products}} --version-from {{tree}}/summary.txt

# PROD: publish a REVIEWED main draft (id from zenodo-rehearse-main) + write its DOI. Gated (typed PUBLISH).
zenodo-publish-draft-main id:
    bash {{scripts}}/zenodo-publish-draft.sh {{id}} {{doi_file}}

# PROD: publish a REVIEWED products draft (id from zenodo-rehearse-products) + write its DOI. Gated.
zenodo-publish-draft-products id:
    bash {{scripts}}/zenodo-publish-draft.sh {{id}} {{products_doi_file}}

# PROD one-shot (upload+publish in one go). PREFER rehearse -> review -> publish-draft above.
# Run ONLY via the gated wrapper:  scripts/zenodo-mint.sh zenodo-mint-main {{doi_file}} {{tree}}
zenodo-mint-main:
    python3 {{scripts}}/zenodo-archive-upload.py --production --concept {{main_concept}} --file {{archive}} --version-from {{tree}}/summary.txt --output {{doi_file}}

# PROD one-shot. Gated wrapper:  scripts/zenodo-mint.sh zenodo-mint-products {{products_doi_file}} {{tree}}
zenodo-mint-products:
    python3 {{scripts}}/zenodo-archive-upload.py --production --concept {{products_concept}} --file {{products}} --version-from {{tree}}/summary.txt --output {{products_doi_file}}

# review the full S3 + CloudFront publish plan -- NO mutations
publish-dry:
    bash {{scripts}}/publish-to-s3.sh --tree {{tree}} --creds {{creds}}

# PROD: run the real publish (index -> push -> capper -> invalidate); prompts for a typed PUBLISH
publish:
    bash {{scripts}}/publish-to-s3.sh --tree {{tree}} --creds {{creds}} --execute

# quick post-publish sanity over HTTP (current + release indexes + DOI file in tree)
verify:
    @echo "current index:"  ; curl -sS -o /dev/null -w "  %{http_code}  %{url_effective}\n" https://current.geneontology.org/index.html
    @echo "release catalog:"; curl -sS -o /dev/null -w "  %{http_code}  %{url_effective}\n" https://release.geneontology.org/index.html
    @echo "DOI file in tree:"; test -f {{doi_file}} && cat {{doi_file}} || echo "  (not written yet)"
