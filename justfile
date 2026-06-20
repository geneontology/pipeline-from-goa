# Publish tail (the "bless") for pipeline-from-goa -- operator recipes.
#
# HAND-RUN, human-gated, in order. RUN THESE ON SKYHOOK (the build/storage host ==
# the Jenkins machine): the release tree is already on its local disk, so there is
# no mount and no copy -- `tree` below is that local path. The build half (Jenkins)
# has already put the tree there and staged the archive tarballs in
# internal/release-archives/. These recipes are SAFE BY DEFAULT: bare `just`
# lists them; `zenodo-test` is sandbox-only; `publish-dry` mutates nothing. The
# only real mutations are `zenodo-mint-*` (mints DOIs) and `publish` (which
# prompts for a typed PUBLISH). See docs/release-runbook.md (Phases 4-5).
#
# Bless order (run these ON skyhook, by hand, reviewing between steps).
# (off-host only: `just mount` first to sshfs the tree; on skyhook the tree is local.)
#   1. just zenodo-test ...      # OPTIONAL rehearsal on the SANDBOX (needs a SANDBOX concept id)
#   2. just zenodo-mint-main     # PROD: mint archive DOI -> metadata/release-archive-doi.json
#   3. just zenodo-mint-products # PROD: mint the secondary-products DOI
#   4. just publish-dry          # review the full S3 + CloudFront plan (no mutations)
#   5. just publish              # PROD: index -> push -> capper -> invalidate (typed PUBLISH)
#   6. just verify

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

# PROD: mint the archive DOI and write it into the tree (needs $ZENODO_TOKEN). IRREVERSIBLE.
zenodo-mint-main:
    python3 {{scripts}}/zenodo-archive-upload.py --production --concept {{main_concept}} --file {{archive}} --version-from {{tree}}/summary.txt --output {{doi_file}}

# PROD: mint the secondary-products DOI (needs $ZENODO_TOKEN). IRREVERSIBLE.
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
