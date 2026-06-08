# Release runbook — pipeline-from-goa

Start-to-sign-off overview of a GO data release built from the
`pipeline-from-goa` pipeline. This is the new-world analog of
`geneontology/operations` `README.pipeline-finalization.md`, covering
the whole lifecycle: from kicking off a `main` run to signing off on
the published release.

It is deliberately **complete**, not just "what runs here" — steps that
live in `operations`, in downstream apps, or with a person are on the
list too, so the whole board is visible and we can migrate items into
the pipeline as they become automatable.

## Release model

`main` is the **sole** pipeline. Its products on
`skyhook.geneontology.io/pipeline-from-goa/main/` are the canonical
tree. A *release* is that tree being **"blessed"** — published — into
the `current` (and dated `release`) locations.

- There is **no** `release` branch and **no** snapshot→release tree
  copy. The old pipeline's four-branch dance (`snapshot` →
  `snapshot-post-fail` → `snapshot-post-post-fail` → `release`) existed
  only as a manual Restart-from-Stage recovery harness for a long,
  non-resumable run; pre-QCed inputs from GOEx make it unnecessary.
- Because inputs arrive pre-QCed, the heavy QA/QC and product-rebuild
  front half is upstream; our job is acquire → derive → publish.

## Definition of done (mechanical)

A release is **mechanically complete** when the file/computer-level state below
holds. Human sign-off / community announcement and explicit verification are
deliberately **out of scope of this definition** — they're lifecycle context in
the phases below, not done-criteria.

1. **All desired files are safely:**
   - **in Zenodo** — the DOIed reproducibility subset, kept as **two separate
     records**: a reproducible "main" archive (concept 1205166) + a larger
     "secondary products" archive (concept 10946933, golr-dominated). The split
     is deliberate (clean reproducible-vs-products sets, independent
     restart-on-fail, parallelizable) — *not* an upload-size limit: streaming was
     validated to 12 GiB, well under Zenodo's 50 GB/record ceiling (#19).
   - **in `current.geneontology.org`** (bucket `go-data-product-current`).
   - **in `release.geneontology.org/XXXX-YY-ZZ`** (bucket
     `go-data-product-release`, dated).
2. **Downloads page regenerated and deployed to the main website.** This is a
   `geneontology.github.io` step (`scripts/update_downloads.py`, driven only by
   go-site `metadata/goex.yaml`, linking to skyhook annotations), tracked at
   **pipeline#396** — **not** a pipeline-from-goa product. Currently manual
   ("does not yet auto-regenerate").
3. **Data products for external interfaces are in place, and any necessary
   service updates/restarts are done** for:
   - **amigo / golr**
   - **go api** — a normal release is picked up by **restarting** go-fastapi: it
     caches the GO-CAM `index-json` once per process and re-fetches on restart
     (go-fastapi #160 / commit `702b83f`). A config change is a one-time event
     only at the #12 path rename, not every release.
   - **go-cam-browser**
4. **Necessary npm packages updated** (likely amigo / dbxrefs).
5. **Release notes** — only when there is a change or error.

## Legend

| Mark | Meaning |
|------|---------|
| ✅ | Automated now (pipeline-from-goa `main`) |
| 🟡 | Partial / needs finishing |
| 🔨 | To build **in this pipeline** (the publish/archive tail) |
| 🔧 | `operations` repo / ansible — separate, but tracked here |
| 👤 | External app / human step (other repos / people) |
| ⚰️ | Legacy — not reproduced (being decommissioned) |
| 🧊 | Pinned cross-repo cutover (tracked issue) |

## Phase 0 — Trigger & run identity
- Kick off `main` (cron + manual). ✅ *(cron is the Feb-31 never-fires stub; real schedule TBD)*
- Pin date/day; write `metadata/{date,dow}.txt`, `release-date.json`, `summary.txt`. ✅
  - `summary.txt` still has a "TODO: note software versions". 🟡

## Phase 1 — Acquire pre-QCed inputs from GOEx
- Populate GOEx mirror S3 buffer (#7). ✅
- Ontology → skyhook. ✅
- Annotations download + partition (mod/uniprot, `union_*`). ✅
- QC reports (go-rules-by-group / tests-go-rules split). ✅
- Metadata + `annotations/README.txt`. ✅
- PANTHER `arbre.tgz`. ✅

## Phase 2 — Derive products
- Solr index `golr-index-contents.tgz` + timestamp + release-only Solr sanity gate. ✅
- `release_stats/` via go-stats. ✅
- GO-CAM processing (json, index-json, search-docs, reports). ✅
- `internal/` all-GO-CAM products. ✅
- Not reproduced: `products/{blazegraph,gaferencer,ttl,upstream_and_raw_data,pages}/`. ⚰️
  - The downloads page is **not** a pipeline product — it is generated in
    `geneontology.github.io` (`scripts/update_downloads.py`, goex.yaml-driven),
    tracked at pipeline#396. See Phase 7. 👤
- Loose ends: `MINERVA_JSON_TARBALL_URL` and the reacto-neo journal are still pulled
  from `current.geneontology.org` / `skyhook.berkeleybop.org` (self/legacy references
  to repoint once we are the source). 🟡

## Phase 3 — Pre-release QC / readiness
- Consolidated run-error surface (the "grep exception" readiness signal). 🔨🟡
- Files-in-expected-locations / parity check (#3). 🟡
- Human approval / wait gate — deferred for now, add later. 🔨(later)

## Phase 4 — Bless → Archive (mint the DOI first) — #19

*Run-level detail — API gotchas + the safe first-production-run procedure:
**docs/zenodo-archival.md**.*

- Build the release archive tarball(s) from the skyhook `main` tree — two
  archives, the reproducible "main" subset + the larger "secondary products"
  (golr-dominated) subset. 🔨
- Zenodo versioned push → **mint DOI**, via `scripts/zenodo-archive-upload.py`
  (InvenioRDM Records API; the dead deposit/`zenodo-version-update.py` path is
  retired — pipeline#345). Concepts: main **1205166**, products **10946933**;
  per-record metadata is **reused** from each concept's own latest version, with
  only `version`/`publication_date` taken from `summary.txt` ("Start date:").
  DOI minted **first** so it can be referenced elsewhere. Validated end-to-end on
  the Zenodo **sandbox** (the real 10.70 GiB golr tarball through the actual
  script + a 12 GiB synthetic PUT, byte-exact commits); production is an explicit
  `--production` opt-in, still to be wired into a bless stage and run. 🟡
- Write `metadata/release-archive-doi.json` (the uploader's `--output`, shape
  `{"doi": ...}`) back into the tree (it travels *in* the published products). 🟡
- BDBag remote-file manifest — optional, was in old Archive. 🔨(optional)

## Phase 5 — Bless → Publish (make it current)

Authoritative ordering (Zenodo already done in Phase 4):

1. Copy tree → **`go-data-product-release`** (dated, e.g. `/$DATE`) + build indexes. 🔨
2. Copy tree → **`go-data-product-current`** + build indexes. 🔨
3. **CloudFront invalidation** — current **E3Q4YIZHZL7358**, release **E2HF1DWYYDLTQP**. 🔨

Details / dependencies:
- Index generation reuses the existing go-site tools as-is: `directory_indexer.py`
  (per-dir `index.html`, needs `-x`), `bucket-indexer.py` (release-bucket top-level
  `index.html`). Acknowledged as not ideal; kept for now.
- Set **Cache-Control** on upload (#9).
- Pinned renames to land at/with cutover: `release_stats/` #11 🧊,
  `go-cams/index-json/` #12 🧊.
- Switchover timing — when `pipeline-from-goa` takes over populating `current` (#1). (decision)
- Announcement of file name/location changes (#16). 👤

## Phase 6 — Deploy data services *(separate — likely in `operations`, tracked here)*
- golr prod — `update-golr.yaml -e target_host=amigo-golr-production` (→ grill.lbl.gov). 🔧
  - Reads input over HTTP from `current.geneontology.org/products/solr/` + the DOI JSON,
    so it works unchanged once Phase 5 lands those.
- amigo prod app — `amigo-golr-up-production.yml`. 🔧
- go api (go-fastapi): a normal release is picked up by **restarting** the
  service — it caches the GO-CAM `index-json` once per process and re-fetches on
  restart (go-fastapi #160 / commit `702b83f`). A config change
  (`app/conf/config.yaml` + provision template) is needed only at the one-time
  `index-json` path-rename cutover (#12), not every release. 🔧🧊
- ~~sparql / `rdf.geneontology.org` prod / graphstore / Cloudflare DNS~~ — ⚰️ legacy,
  decommissioning; no outward-facing Blazegraph concern. (Blazegraph may persist
  internally with Minerva — not the pipeline's concern.)

## Phase 7 — Downstream app releases *(external / human)*
- Downloads page: regenerate `downloads.html` in `geneontology.github.io` via
  `scripts/update_downloads.py` (reads go-site `metadata/goex.yaml`, links to
  skyhook annotations) → deploy via the website. Tracked at **pipeline#396**;
  currently manual. **Stale-link bug:** the script's GAF links predate the #15
  annotations restructure (`annotations/{code}.gaf.gz` /`{code}-uniprot.gaf.gz`)
  and must move to `annotations/gaf/{code}-mod.gaf.gz` (~23 MOD orgs only) and
  `annotations/gaf/{code}-uniprot.gaf.gz`; GPI currently links to EBI, not skyhook. 👤
- go-cam-browser "ping patrick": regenerate committed `public/data.json` →
  `data-release-YYYY-MM-DD` branch → merge → GitHub Pages auto-deploy. 👤
- amigo / metadata **npm** packages. 👤
- Confirm GO API product switch. 👤

## Phase 8 — Sign-off
- Success/failure notifications (`post{}` emails). ✅(basic)
- Release notes (`go-site/releases/$DATE`). 👤
- Inform pipeline channel (Suzi / Pascale). 👤
- Final smoke checks — `current` up, golr/amigo serving new data, DOI resolves. 🟡

## Cross-cutting tracking issues
- #1 — assemble full pipeline / switchover timing
- #2 — OWLTools file-access bug
- #3 — files in expected locations (parity)
- #9 — Cache-Control on published S3 objects
- #11 — `release_stats/` rename (pinned cutover) 🧊
- #12 — `go-cams/index-json/` move (pinned cutover) 🧊
- #16 — announcement of file name/location changes
- #19 — bless tail: Zenodo archiving + DOI minting (Phase 4)

## What's actually left to build here

The net-new pipeline code is **Phase 4 (Archive)** and **Phase 5 (Publish)**.
Phase 4's Zenodo archival step is now scripted and sandbox-validated
(`scripts/zenodo-archive-upload.py`, #19); what remains there is assembling the
archive tarball(s) and wiring it into a bless stage. Phase 6 mostly falls out
for free once Publish populates `current.geneontology.org`. Build order:
Publish → Archive → (optional) Deploy hooks.
