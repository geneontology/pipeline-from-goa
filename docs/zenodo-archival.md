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

## Safe first-production-run procedure

The "new version on a **legacy-origin** concept" path cannot be fully rehearsed
on sandbox: the real GO concepts predate Zenodo's InvenioRDM migration and are
legacy-serialized, whereas any sandbox concept we create is InvenioRDM-native.
The script defends against this by sending a **complete** metadata block (so it
doesn't matter whether the new-version draft inherits or blanks metadata), but
the first real run should still be eyeballed:

1. Run `--production --no-publish`. Creates the new-version draft, uploads and
   commits the file, but does **not** publish.
2. Review the draft in the Zenodo UI (`https://zenodo.org/uploads/<id>`):
   metadata reused correctly, file present and the right size.
3. Publish from the UI, or re-run without `--no-publish`. **Publishing mints the
   DOI and is irreversible** — a published record cannot be deleted (see
   Gotchas).
4. The DOI is written to `--output` as `{"doi": ...}`, for
   `metadata/release-archive-doi.json`.

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

## Still to build (#19)

- Assemble the archive tarball(s) from the skyhook `main` tree (the uploader's
  input): decide the main-vs-products partition, then tar each subset.
- Wire the step into a bless stage (waits on the bless trigger; see runbook).
