# Publish tail (the "bless") for pipeline-from-goa -- operator recipes.
#
# HAND-RUN, human-gated, in order. The build half (Jenkins) has already put the
# release tree on skyhook and staged the archive tarballs in
# internal/release-archives/. These recipes are SAFE BY DEFAULT: bare `just`
# lists them; `zenodo-test` is sandbox-only; `publish-dry` mutates nothing. The
# only real mutations are `zenodo-mint-*` (mints DOIs) and `publish` (which
# prompts for a typed PUBLISH). See docs/release-runbook.md (Phases 4-5).
#
# Bless order (run these by hand, reviewing between steps):
#   1. just mount                # sshfs the skyhook tree (read-write)
#   2. just zenodo-test ...      # OPTIONAL rehearsal on the Zenodo SANDBOX
#   3. just zenodo-mint-main     # PROD: mint archive DOI -> metadata/release-archive-doi.json
#   4. just zenodo-mint-products # PROD: mint the secondary-products DOI
#   5. just publish-dry          # review the full S3 + CloudFront plan (no mutations)
#   6. just publish              # PROD: index -> push -> capper -> invalidate (typed PUBLISH)
#   7. just verify ; just unmount

# --- config (override on the CLI, e.g. `just tree=/mnt/skyhook/... publish-dry`) ---
scripts          := justfile_directory() / "scripts"
tree             := "/tmp/pfg-tree"                                                          # mounted skyhook .../main
creds            := env_var('HOME') / "local/share/secrets/bbop/aws/s3/aws-go-push.json"     # AWS push creds JSON
skyhook_host     := "SET-ME"                                                                 # the private SKYHOOK_MACHINE ssh host
skyhook_key      := env_var('HOME') / "local/share/secrets/bbop/ssh-keys/id_rsa_nopass.skyhook"
main_concept     := "1205166"      # Zenodo concept: "Gene Ontology Data Archive" (main / reproducible)
products_concept := "10946933"     # Zenodo concept: "Secondary Products"
archive          := tree / "internal/release-archives/go-release-archive.tgz"
products         := tree / "internal/release-archives/go-release-products.tgz"
doi_file         := tree / "metadata/release-archive-doi.json"

# list the recipes (default)
default:
    @just --list --unsorted

# print the bless order
bless-order:
    @sed -n '/^# Bless order/,/just verify/p' {{justfile_directory()}}/justfile | sed 's/^# \{0,1\}//'

# mount the skyhook release tree read-WRITE at {{tree}} (publish writes index.html into it)
mount:
    mkdir -p {{tree}}
    sshfs -o IdentitiesOnly=true -o IdentityFile={{skyhook_key}} skyhook@{{skyhook_host}}:/home/skyhook/pipeline-from-goa/main {{tree}}

# unmount the skyhook tree
unmount:
    fusermount -u {{tree}}

# OPTIONAL rehearsal on the Zenodo SANDBOX (needs $ZENODO_SANDBOX_TOKEN); never touches production
zenodo-test file concept:
    python3 {{scripts}}/zenodo-archive-upload.py --sandbox --no-publish --concept {{concept}} --file {{file}}

# PROD: mint the archive DOI and write it into the tree (needs $ZENODO_TOKEN). IRREVERSIBLE.
zenodo-mint-main:
    python3 {{scripts}}/zenodo-archive-upload.py --production --concept {{main_concept}} --file {{archive}} --output {{doi_file}}

# PROD: mint the secondary-products DOI (needs $ZENODO_TOKEN). IRREVERSIBLE.
zenodo-mint-products:
    python3 {{scripts}}/zenodo-archive-upload.py --production --concept {{products_concept}} --file {{products}}

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
