# Zenodo archival — operational notes

How to run the bless-tail Zenodo step (`scripts/zenodo-archive-upload.py`,
runbook Phase 4, issue #19) safely, and the InvenioRDM Records-API behaviours
that cost time to discover. The **script header** documents the code/flow
(metadata reuse, constant-memory streamed PUT, DOIs top-level not `pids`,
sandbox-default); the **runbook** has the lifecycle summary. This file is the
operational layer: procedure, caveats, and testing.

## Records

Two separate records, the uploader run once each:

| Record | Concept | Concept DOI |
|--------|---------|-------------|
| main / reproducible archive | `1205166` | 10.5281/zenodo.1205166 |
| secondary products (golr-dominated) | `10946933` | 10.5281/zenodo.10946932 |

The split is a deliberate choice (clean reproducible-vs-products sets,
independent restart-on-fail, parallelizable) — **not** a size limit (see
Validated). Tokens: sandbox `$ZENODO_SANDBOX_TOKEN`, production `$ZENODO_TOKEN`.

## Production rehearsal (GATING step before the first real bless)

The "new version on a **legacy-origin** concept" path cannot be fully rehearsed
on sandbox: the real GO concepts predate Zenodo's InvenioRDM migration and are
legacy-serialized, whereas any sandbox concept we create is InvenioRDM-native.
The script defends against this by re-supplying a **complete** metadata block, but
the first production run must still be eyeballed with `--no-publish` first.

`--production --no-publish` runs the WHOLE production path — resolve the concept,
create the new-version draft, reuse + set metadata, clear inherited files, stream +
commit ours (with a post-commit size check) — and stops **before** the irreversible
publish, printing a reviewable draft URL. It mints **no** DOI and writes no `--output`.

Run it ON skyhook (the tarballs + `summary.txt` are local there), production token
set, for **both** concepts:

    export ZENODO_TOKEN=<PRODUCTION token>     # NOT $ZENODO_SANDBOX_TOKEN

    just zenodo-rehearse-main        # concept 1205166, go-release-archive.tgz
    just zenodo-rehearse-products    # concept 10946933, go-release-products.tgz

    # (equivalently, by hand:)
    #   python3 scripts/zenodo-archive-upload.py --production --no-publish \
    #     --concept 1205166 \
    #     --file /home/skyhook/pipeline-from-goa/main/internal/release-archives/go-release-archive.tgz \
    #     --version-from /home/skyhook/pipeline-from-goa/main/summary.txt

Each run prints `DRAFT READY (unpublished): https://zenodo.org/uploads/<id>`. Open it
and verify:

- [ ] **No error.** The run completing at all means `sanitize_metadata` accepted the
      legacy concept's native serialization — the one thing sandbox cannot prove.
- [ ] **Title** is the concept's title (reused, not blanked).
- [ ] **Creators** present (count matches the script's `creators=N` line).
- [ ] **Version** == the release date (from `summary.txt` "Start date:").
- [ ] **Resource type / rights / license** look right.
- [ ] The **file** is attached, right name, right **size** (the script already
      size-verifies on commit; confirm visually too).

When both drafts look right, **publish the reviewed drafts directly** — do **not**
discard a good draft and re-upload (it wastes a multi-GB transfer, and the draft you
reviewed is exactly what should be published):

    just tree=<copy> zenodo-publish-draft-main     <main-draft-id>
    just tree=<copy> zenodo-publish-draft-products <products-draft-id>

Each wraps `scripts/zenodo-publish-draft.sh`, which re-checks the draft has a
committed file, **prompts for a typed `PUBLISH`** (irreversible — a published record
cannot be deleted), publishes via `POST /api/records/<id>/draft/actions/publish`, then
reads the top-level `doi` and writes it into the tree
(`metadata/release-archive-doi.json` / `release-archive-products-doi.json`).

Only **discard** a draft you are *not* going to publish (a pure throwaway test):
"Delete"/"Discard" in the UI, or `DELETE /api/records/<id>/draft` (204).

> One-shot alternative — the `zenodo-mint-*` recipes upload **and** publish in one
> call. Prefer the rehearse → review → publish-draft flow above: it puts a human review
> gate on the *actual uploaded draft*. If you one-shot anyway, run it **gated** via
> `scripts/zenodo-mint.sh zenodo-mint-main <doi-file> <copy-tree>` (typed `PUBLISH`) —
> never the raw recipe directly (no confirmation; that is how an unreviewed publish
> slipped out the first time).

## Validated (sandbox, 2026-06-05)

- Constant-memory chunked PUT at **12 GiB** (synthetic) and the **real
  10.70 GiB `golr-index-contents.tgz`** end-to-end through the actual script —
  byte-exact server-side commit both times.
- Throughput from the dev host ≈ 8–12 MiB/s → an ~11 GiB record ≈ 20–26 min.
- Zenodo per-record ceiling is **50 GB / 100 files** (200 GB on request); our
  largest record (~11 GiB) is well under it. The split was never forced by size.

## Gotchas (InvenioRDM Records API)

- **New-version drafts inherit the previous version's files.** Clear them before
  adding the release tarball (the script does this).
- **Delete asymmetry:** a draft (`DELETE …/draft`) returns **204**; a *published*
  record cannot be deleted (**403**, permanent by design). Hence tests use
  `--no-publish` + draft-delete to avoid leaving data behind.
- **DOI serializer split** (also in the script header): default/legacy
  serialization exposes `doi`/`conceptdoi` at the record top level; the native
  serializer (`Accept: application/vnd.inveniordm.v1+json`) hides the DOI under
  `pids.doi.identifier`. Read the published DOI via the default serializer.
- **Don't round-trip the legacy metadata block** on write — sanitize the native
  serialization to the write schema (`resource_type {id}`, `rights [{id}]`,
  creators `person_or_org` family/given + identifiers, affiliations name(+ROR
  id)) and override only `version`/`publication_date` (from `summary.txt`
  "Start date:").

## Testing locally / at full size

- A real full-size test needs the payload on local disk. **Skyhook HTTP resets
  on long downloads** (`curl (56) Connection reset by peer`); fetch large files
  with a resumable loop (`curl -C -` retried until the local size matches the
  remote `Content-Length`), not a single GET.
- Always test with `--sandbox --no-publish` and delete the draft afterward —
  never leave a multi-GB *published* record on sandbox (you can't remove it).

## Status (#19)

- **Archive tarballs — DONE.** `scripts/build-release-archives.sh`, wired as the
  Jenkinsfile "Release archives" build stage; partition = main (`annotations go-cams
  metadata ontology release_stats reports`) + `products`, staged in
  `internal/release-archives/{go-release-archive,go-release-products}.tgz`.
- **Uploader — DONE + sandbox-validated**; the production path is **rehearsed via
  `--no-publish`** (above) before the first real mint.
- **Operator entry point** — the repo-root `justfile`: the proven flow is
  `zenodo-rehearse-*` → (review) → `zenodo-publish-draft-*` (gated
  `scripts/zenodo-publish-draft.sh`); `zenodo-mint-*` one-shot only via gated
  `scripts/zenodo-mint.sh`. A future automated bless stage is scaffolded (disabled)
  in the Jenkinsfile.
- **First production bless — DONE (2026-06-19).** main archive DOI
  `10.5281/zenodo.20943148`, secondary products `10.5281/zenodo.20941845`; published
  via the rehearse → review → publish-draft flow. The main archive is ~1.3 GiB — an
  order of magnitude below the old pipeline's ~16 GiB; the drop is the discontinued
  all-UniProt mega-GAF (`filtered_goa_uniprot_all.gaf.gz`, ~10 GiB) + `annotations/archive/`
  (~9 GiB), see `parity-and-products.md` — **not** missing content (ontology + all 171
  species' annotations are intact).
