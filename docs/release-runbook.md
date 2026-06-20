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
- **Upstream GOA freshness (#21):** mirror `release_date.txt`, record the GOA
  drop date into the release, and gate on it advancing vs the last release —
  don't build on stale upstream data. 🔨
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

> **Build-then-publish; `internal/` is the staging area.** The pipeline has two
> halves: compute **everything we can** onto skyhook in the **build** half —
> final data, products, *and* the artifacts publication will consume — then run
> the **publish** half, which materializes them at their destinations: it
> generates the (per-destination) indexes and performs the mutating pushes to the
> S3 buckets / `go-public` / Zenodo. Publish computes no *new* release data, but
> it is **not** a pure copy — the per-destination indexes and the bucket sync are
> real work. `internal/`
> holds build outputs that are **not** part of the served tree: it is **never
> copied to the current/release buckets, never indexed (#22/#23), and never
> nested inside an archival tarball**. But it *is* the holding area whose contents
> feed specific publish steps — the Zenodo archive tarballs are built (excluding
> `internal/`) and dropped **into** `internal/`, then pushed to Zenodo (#19); the
> per-model Minerva JSON is staged there, then pushed to `go-public/files/go-cam/`
> (#24). Nothing in `internal/` is itself served from current/release.

### Stage structure & restart model — the hard build/publish divide

A **hard divide** separates the *production* (build) segment from the
*publication* segment, enforced by the **bless gate** (mechanism TBD): the build
segment puts **everything** on skyhook; nothing publishes until bless. Stage
granularity is chosen for Restart-from-Stage recovery.

- **Build segment (production):** the existing product stages, plus — per-model
  Minerva JSON staged into `internal/` (#24, folded into the GO-CAM stage) and,
  **last**, the now-wired **`Release archives`** stage running
  `build-release-archives.sh` (needs every product on skyhook) tarring the two
  subsets into `internal/release-archives/`.
- **— bless gate (hard divide) —**
- **Publication segment:** fine-grained stages (each a restart point), in the
  authoritative order —
  1. **Zenodo** — upload both tarballs from skyhook (run the uploader *on*
     skyhook, streaming from local disk) → mint DOIs → write
     `metadata/release-archive-doi.json` into the tree. **A new version on each
     concept per publish is the intended design** (one Zenodo version per
     release), not something to "guard" against. The only rule is: **run the mint
     only when you actually intend to publish** — so the Jenkins stage stays gated
     OFF and minting is a deliberate hand-run step (`just zenodo-mint-*`). A
     re-run/Restart would mint *another* version (recoverable, not corrupting), so
     just don't re-run the mint unless you mean to.
  2. Copy tree (minus `internal/`) → release bucket (dated) + indexes.
  3. Copy tree (minus `internal/`) → current bucket + indexes.
  4. `go-public` pushes (per-model Minerva JSON #24; union GAFs).
  5. CloudFront invalidation (current + release).

Stages 2–5 are **idempotent** (S3 sync, index regen, CloudFront) — safe to restart
freely. Stage 1 (Zenodo) deliberately mints a new version each publish — protect it
by *not running it unless publishing*, not by a guard. The DOI file and the
per-destination indexes are **publish-generated** (they can't exist before bless) —
the one nuance to "everything on skyhook first".

## Phase 4 — Bless → Archive (mint the DOI first) — #19

**Operator entry point:** the repo-root **`justfile`** wraps the whole hand-run
tail (Phases 4 + 5) in bless order with safe defaults — `just --list` /
`just bless-order` show it. **Run it ON skyhook** (the build/storage host == the
Jenkins machine): the tree is on local disk there, so there is **no mount and no
copy** — sshfs would turn every file-touch (two index passes + two full pushes)
into a network round-trip, and the tree is read twice. `just`'s `tree` defaults to
`/home/skyhook/pipeline-from-goa/main`; `mount`/`unmount` are an **off-host fallback
only**. Real mutations are only `zenodo-mint-*` and `publish`. Deps on skyhook: aws
cli + python (pystache/boto3/filechunkio); if absent, run in a container there with
the tree **bind-mounted** (still local — not sshfs).

*Run-level detail — API gotchas + the safe first-production-run procedure:
**docs/zenodo-archival.md**.*

- Build the release archive tarball(s) from the skyhook `main` tree (**excluding
  `internal/`**) — two archives, the reproducible "main" subset + the larger
  "secondary products" (golr-dominated) subset. ✅ **Wired** as the final build
  stage `Release archives` (`scripts/build-release-archives.sh`) → tarballs land
  in `internal/release-archives/`, staged for the (manual) publish tail.
- Zenodo versioned push → **mint DOI**, via `scripts/zenodo-archive-upload.py`
  (InvenioRDM Records API; the dead deposit/`zenodo-version-update.py` path is
  retired — pipeline#345). Concepts: main **1205166**, products **10946933**;
  per-record metadata is **reused** from each concept's own latest version, with
  only `version`/`publication_date` taken from `summary.txt` ("Start date:").
  DOI minted **first** so it can be referenced elsewhere. Validated end-to-end on
  the Zenodo **sandbox** (the real 10.70 GiB golr tarball through the actual
  script + a 12 GiB synthetic PUT, byte-exact commits); production is an explicit
  `--production` opt-in. **GATING before the first real mint:** rehearse with
  `--production --no-publish` for **both** concepts (`just zenodo-rehearse-main` /
  `zenodo-rehearse-products`), review the unpublished drafts in the Zenodo UI, then
  discard them — this is the only part that **cannot** be sandbox-tested (legacy-origin
  concept metadata). Full procedure + checklist: **docs/zenodo-archival.md**. 🟡
- Write `metadata/release-archive-doi.json` (the uploader's `--output`, shape
  `{"doi": ...}`) back into the tree (it travels *in* the published products). 🟡
- BDBag remote-file manifest — optional, was in old Archive. 🔨(optional)

## Phase 5 — Bless → Publish (make it current)

Authoritative ordering (Zenodo already done in Phase 4). This is **six
interleaved steps**, not two copies — faithful to the old (commented) Publish
stage, `Jenkinsfile` **L942–987**, which is the reference implementation:

1. **Index for release** — `directory_indexer.py … --prefix http://release.geneontology.org/$DATE -x -u`
   over the local skyhook tree (bakes the dated-release URL into every `index.html`). 🔨
2. **Push** the indexed tree (minus `internal/`) → **`go-data-product-release/$DATE`**. 🔨
3. **Release-root catalog** — `bucket-indexer.py` over `go-data-product-release`
   builds the top-level "capper" listing of all dated releases; PUT to the bucket
   **root**, **`s3://go-data-product-release/index.html`** (distinct from the
   per-dir indexes; must run *after* step 2 so the new dated dir is listed). 🔨
4. **Re-index for current** — `directory_indexer.py … --prefix http://current.geneontology.org -x`
   over the **same** tree again (now baking the `current` URL). 🔨
5. **Push** the re-indexed tree (minus `internal/`) → **`go-data-product-current`**. 🔨
6. **CloudFront invalidation** — **both** distributions: current
   **E3Q4YIZHZL7358** *and* release **E2HF1DWYYDLTQP**. 🔨

Details / dependencies:
- **Implemented (hand-run) in `scripts/publish-to-s3.sh`** — the standalone Phase-5
  orchestrator for the six steps above, **dry-run by default** (mutations only behind
  `--execute` + a typed `PUBLISH` confirm; the three real mutations are the two
  `s3-uploader.py` pushes, the capper PUT, and the two CloudFront invalidations).
  Reuses go-site `directory_indexer.py`, `bucket-indexer.py`, and `s3-uploader.py`.
  Pseudo-tested without any mutation: both indexer passes on a sample tree, the real
  read-only capper over `go-data-product-release` (248 dated dirs), the push previewed
  via `aws s3 sync --dryrun` (confirming `internal/` excluded — 9 of 11 sample files),
  and the CloudFront IDs validated. Decisions baked in:
  - **Content-Type = legacy.** The real push uses go-site **`s3-uploader.py`** (per
    CLAUDE.md "don't reinvent the publish tooling"): controlled MIME map, default
    `text/plain`, overrides `json`→application/json, `gz`→application/gzip,
    `obo`→text/obo, `owl`→application/rdf+xml, `ttl`→text/turtle, etc. Plain `aws s3
    sync` would guess `application/octet-stream` for `.gaf`/`.gpad`/`.gpi`/`.obo`/
    `.owl`/`.gz` (→ download, not inline). Needs `filechunkio` installed; revisiting
    the map is a later improvement.
  - **Overlay-only (first-rollout requirement).** The push **never deletes** — existing
    `go-data-product-current` objects (the OLD pipeline's files) are **preserved**, so
    `current.geneontology.org` keeps serving prior files via CloudFront through the
    cutover (the Track-B contract). Pruning stale objects is deferred.
  - **`internal/` exclusion.** Both go-site tools are passed **`--exclude internal`**
    (go-site PR #2710, merged) — `directory_indexer` prunes it from the walk (no
    listing, no dangling link) and `s3-uploader` skips it on upload, the same way in
    dry-run and execute. `publish-to-s3.sh` refuses to run if a fetched tool lacks
    `--exclude` (rather than silently publishing `internal/`). The earlier
    relocate-aside `mv` workaround is gone.
- **Why two indexer passes (the crux — #22).** `directory_indexer.py` bakes an
  **absolute URL prefix** into every `index.html` (`current.geneontology.org` vs
  `release.geneontology.org/$DATE`). The same on-disk tree therefore **cannot** be
  pushed to both buckets as-is — it must be **re-indexed per destination**. Do
  **not** collapse steps 1+2 and 4+5 into a single index-then-fan-out. Indexing
  runs over the **local** skyhook tree (near-instant; `-u` updates the dated tree);
  `internal/` is **not** indexed.
- **Order is deliberately flipped from legacy.** The old pipeline did
  **current → release**; the bless order here is **release(dated) → current**
  (Zenodo-first → release → current → invalidate). Both are valid because each push
  gets its own index pass — but the flip is a conscious choice, not an accident.
- **Capper lands at the bucket root.** Step 3's `bucket-indexer.py` output is the
  dated-release **catalog** at `…/release/index.html`, not a per-dir index. (Legacy
  PUT it via `s3cmd --cf-invalidate`; here it's a plain upload + the discrete
  step-6 invalidation.)
- **Correctly dropped from legacy:** the `snapshot` / `go-data-product-daily/$DOW`
  pushes (no snapshot branch now — skyhook *is* the snapshot equivalent), and the
  `s3cmd` capper-with-inline-CF-invalidate (→ aws-cli invalidation as its own step).
- The slow legacy piece was the `aws-js-s3-explorer` SPA walk (`s3_add_*`
  recursively re-indexes the *whole* bucket every release ≈ 45 min); retiring it for
  the fast static path + a richer listing is the **optional** #23.
- Fallback: run the finalization indexer by hand (as before) if the in-pipeline
  step isn't ready for a given release.
- Set **Cache-Control** on upload (#9).
- **`go-public` serving pushes** (publish-stage): per-model Minerva JSON →
  `go-public/files/go-cam/` for the GO API (#24); union GAFs → `go-public/skyhook-geneontology-io/`
  for OWLTools (currently pushed at build — align to publish later).
- Pinned GO-CAM path renames to land at/with cutover: `go-cams/index-json/` #12 🧊
  (plus the GO-CAM layout refresh — see #3). (#11 `release_stats/` rename was
  dropped; keeping `release_stats/`.)
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

## Cutover sequence — old → new pipeline (June 2026)

The **one-time** switchover where `pipeline-from-goa` takes over from the old
`pipeline` as the source for `current.geneontology.org` (distinct from the
per-release lifecycle in Phases 0–8, which it reuses). Two things happen
together at T‑0: the new pipeline starts **populating** `current/` (a mechanical
bless, Phases 4–5), and the breaking `/annotations/` layout goes **live to
users** (needs a grace period). Ownership: annotations grace = **operations#83**;
capacity = **operations#82**; date-gate + umbrella = **#1**; consumer file-path
contracts = **#3**.

### Track A — Readiness gates (must be green before T‑0)
- **Publish/bless tail built — the critical path** (Phases 4–5; operations#83
  work-item-1). ✅ **Built as hand-run scripts** (the build/publish split):
  `build-release-archives.sh` (wired as the "Release archives" build stage) →
  `zenodo-archive-upload.py` → `publish-to-s3.sh` (the six-step
  index/copy/capper/invalidate), driven by the repo-root `justfile`;
  dry-run-validated end-to-end and adversarially reviewed (three no-context passes).
  `internal/` excluded via go-site `--exclude` (#2710 merged), overlay-only push
  (legacy `s3-uploader.py` Content-Types), Zenodo-before-publish guard. A future
  automated Jenkins Publish stage is scaffolded **disabled/commented**. **Not yet
  run for real** — the remaining gates are operational, below. 🟡
- **Zenodo production rehearsal (#19).** Before the first real mint, run
  `--production --no-publish` for **both** concepts (`just zenodo-rehearse-main` /
  `-products`), review the unpublished drafts in the Zenodo UI, then discard — the
  only step that **cannot** be sandbox-tested (legacy-origin concepts predate
  InvenioRDM). Procedure + checklist: **docs/zenodo-archival.md**. 🔨(operator)
- **Run on skyhook + the job-name invariant.** Run the hand-run tail ON the skyhook
  host (so the tree is local). Load-bearing: the multibranch job must stay named
  `pipeline-from-goa` (branch `main`) so `$JOB_NAME == pipeline-from-goa/main` —
  `initialize()` cleans `$WORKSPACE/mnt/$JOB_NAME` while every product stage
  hardcodes `/home/skyhook/pipeline-from-goa/main`; rename the job and the build
  silently writes a *different* tree than it cleaned (verified equal 2026-06-20). 🟡
- **Prove a full clean run.** Confirm a from-scratch run yields the complete tree
  (incl. `products/json/noctua-models-json.tgz`, #17), and fill the `summary.txt`
  "note software versions" TODO before minting a permanent DOI. 🟡
- **Consumer-contract parity verified (#3).** Mostly done; #3 holds the checklist. 🟡
- **Upstream GOA freshness gate (#21).** Confirm the GOA drop is fresh
  (`release_date.txt` advanced vs the last release) before the cutover build —
  don't ship the first new-pipeline release on stale upstream data. 🔨
- **Capacity (operations#82).** Largely green (monit thresholds, HTTP health
  probe, bot mitigation); only the T+24h post-switch verification remains. 🔧🟡
- **CloudFront Function mapping generator (operations#83 wi‑3).** Emit the
  301/410 table from `goex.yaml` (canonical source; `annotations-mapping.md` is
  derived doc). 🔨
- **Announcement** to programmatic consumers (template: closed pipeline#424). 👤
- *Not a gate — already done/live:* the blazegraph-free **GO API** is live and
  ops-managed in `operations/provision/go-fastapi/`; go-fastapi#137's only
  residual is the switchover repoint to the new index location (Track D / #12).

### Track B — The cutover act (T‑0): first blessed new-pipeline release
Fixed order (also in CLAUDE.md): **Zenodo mint DOI → write
`release-archive-doi.json` → copy tree to release bucket (dated) → copy to
current bucket → CloudFront invalidate.** This is the moment `current/` becomes
new-pipeline output.
- **Publish-stage constraint — `/annotations/` must be additive.** The copy into
  `go-data-product-current` must **not** `--delete` under `/annotations/`: the
  new `gaf/`·`gpad/`·`gpi/` subdirs land *alongside* the frozen old flat files so
  both coexist (the operations#83 Phase‑1 "physical overlap" contract). A
  careless `sync --delete` would wipe the old files and break the grace period.

### Track C — `/annotations/` grace period (operations#83, ~3 months)
- **Phase 1 — physical overlap (T‑0 → ~1 mo):** old flat files frozen; new
  subdir layout coexists (no clobber, per Track B); no CDN change.
- **Phase 2 — forwarding (~1 → ~3 mo):** **deploy the CloudFront Function first**
  (1:1 → `301`, no-equivalent or 1:N MOD fan-out → `410`, else passthrough),
  *then* delete the old flat files — so there is never a bare‑`404` window; the
  delete is cleanup behind a live redirect. Before deleting, **verify the API and
  other consumers are actually reading the new files** (not pinned to old/cached
  paths).
- **Phase 3 — steady state (~3 mo+):** remove the Function; old paths → `404`.
  Done. (`release.geneontology.org` needs none of this — date-stamped dirs
  self-separate.)

### Track D — Consumer deploys (T‑0+, first days, within #83 Phase 1)
Picking up the new *release* (distinct from the annotations grace mechanism):
- golr/AmiGO deploy from `current/products/solr` + the DOI → operations#82 T+24h
  verify. 🔧
- GO API **restart** (re-fetches `index-json`); repoint only if #12 lands. 🔧
- go-stats auto-fires on `current/metadata/release-date.json` change (SNS). 🟡
- go-cam-browser regenerate + commit `public/data.json` ("ping patrick"). 👤
- Downloads page regenerate / switch to new layout (#396). 👤
- amigo / metadata **npm** packages. 👤

### Decisions to lock before putting dates on this
1. **Cutover date** — "June 2026"; pin the actual day (operations#83 wi).
2. **index-json (#12): rename or keep?** Annotations is already one breaking
   change, and we kept `release_stats` (#11) to avoid breakage. Recommend
   **keeping `go-cams/index-json/`** (defer #12) so go-fastapi needs no config
   change at cutover; revisit later.
3. **Bless trigger (#1)** — manual vs timed; intentionally open.
4. **Downloads page link target (#396)** — stable `current/` vs rolling skyhook.

## Cross-cutting tracking issues
- #1 — assemble full pipeline / switchover timing
- #2 — OWLTools file-access bug
- #3 — files in expected locations (parity)
- #9 — Cache-Control on published S3 objects
- #11 — `release_stats/` rename — **closed not-planned** (keeping `release_stats/` as-is)
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
