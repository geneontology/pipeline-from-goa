# Parity & products: skyhook `main` vs `current.geneontology.org`

Consolidated, **sized** inventory of what the new pipeline publishes to
`skyhook.geneontology.io/pipeline-from-goa/main/` versus what the old pipeline
serves at `current.geneontology.org`, plus the authoritative
"what-should-be-generated" list derived from the Jenkinsfile + `scripts/`.

This supersedes the scattered hierarchy snapshots (the old per-tree memories).
Keep it current; it is the source of truth for the #16 file-rename announcement
and the Zenodo sizing decision (Path 2).

## Method & provenance (refreshed 2026-06-03)

- **skyhook** tree: crawled the Apache autoindex at
  `https://skyhook.geneontology.io/pipeline-from-goa/main/` (the live published
  tree; data dated ~2026-04-22/23). Sizes are **SI-rounded** by autoindex
  (good enough for sizing, not byte-exact).
- **current** tree: `aws s3 ls --recursive s3://go-data-product-current`
  (byte-exact). This bucket is the *old* pipeline's output (the new pipeline has
  not taken over `current` yet — issue #1 switchover is still TBD).
- The skyhook ssh box (`skyhook@skyhook.berkeleybop.org`) is **wok**, which does
  **not** hold `pipeline-from-goa/`; the published tree lives on the (Cloudflare-
  fronted) host behind `skyhook.geneontology.io`, reachable only over HTTP here.

## Headline

| | files | size |
|---|---:|---:|
| skyhook `main` | 66,101 | ~21.2 GiB |
| `current.geneontology.org` | 2,487 | ~65.3 GiB |

The new tree is ~1/3 the size, mostly because the biggest old artifacts are
**intentionally gone**: `filtered_goa_uniprot_all.gaf.gz` (10.2 G),
`products/blazegraph` (17 G), `annotations/archive` (8.9 G), old per-dataset
`reports` (~6.5 G of the 8.3 G), `products/ttl` (2.1 G),
`products/upstream_and_raw_data` (1.9 G). The file *count* is far higher on
skyhook only because of the new `internal/` tree (61,099 files).

## Top-level comparison

| dir | sky # | sky sz | cur # | cur sz | verdict |
|---|---:|---:|---:|---:|---|
| annotations | 583 | 714 M | 1342 | 19.3 G | **restructured** (#15/#16) + current carries `archive/` + `goa_uniprot_all` |
| go-cams | 2014 | 37.7 M | 6 | 4.8 M | skyhook adds `json/` (per-model); current has only `index-json/` |
| internal | 61099 | 492 M | 0 | – | **NEW** (intentional) |
| metadata | 116 | 1.2 M | 128 | 1.9 M | near-parity; current has generated extras (see gaps) |
| ontology | 194 | 7.1 G | 227 | 7.2 G | near-parity (per-subdir `index.html` + a few files) |
| products | 2012 | 11.1 G | 321 | 30.5 G | skyhook = solr/panther/go-cam; current adds discontinued |
| release_stats | 13 | 16.7 M | 14 | 18.4 M | **parity** (current +1 = publish-time `index.html`) |
| reports | 69 | 1.7 G | 447 | 8.3 G | **restructured** (GOEx QC vs old per-dataset) |
| index.html | – | – | 1 | 1.2 K | publish-time artifact (not a gap) |
| summary.txt | 1 | 345 B | 1 | 326 B | ✓ |

## What the pipeline *should* generate (derived from Jenkinsfile + scripts)

| stage / script | skyhook outputs |
|---|---|
| `initialize()` | dir skeleton; `summary.txt`; `metadata/{date,dow}.txt`, `release-date.json` |
| Ontology download | `ontology/**` (mirror of EBI GOEx `ontology/`) |
| `annotation-download-and-partition.sh` | `annotations/{gaf,gpad,gpi}/MNEMONIC-{mod,uniprot}.<ext>.gz`; `internal/union-gaf-partitions/union_*.gaf.gz` (10); (+ S3 `go-public/skyhook-geneontology-io/union_*`) |
| `produce-derivatives.sh` | `products/solr/golr-index-contents.tgz` + `golr_timestamp.log`; `release_stats/*` (go-stats) |
| `gocam-processing.sh` | `go-cams/json/*`; `products/indexed-go-cams/*`; `go-cams/index-json/*` (6); `products/go-cam-search/go-cam-browser-search-docs.json`; `reports/go-cam/*` |
| `internal-all-gocam-products.sh` | `internal/all-true-go-cams-json/*`; `internal/all-true-go-cams-yaml/*`; `internal/all-go-cams-gpad/unified.gpad.gz` + `model/*` |
| QC reports download | `reports/groups/*_gorule_report.*`; `reports/go-rules/gorules_test_errors.*`; `reports/*` (rest) |
| Metadata + README | `metadata/**` (rsync of `go-site/metadata/`); `annotations/README.txt` |
| PANTHER trees | `products/panther/arbre.tgz` |

Note: `initialize()` also `mkdir`s `products/json/`, but **no stage populates it**
— it is empty on skyhook (see gaps).

## Delta, classified

### Intentional / known — NOT gaps
- **`internal/`** — new (61,099 files; `all-go-cams-gpad/model/` is 54,385 of them).
- **`go-cams/json/` (2008), `products/indexed-go-cams/` (2008), `products/go-cam-search/`** — new per-model GO-CAM publishing.
- **`reports/` restructure** — new `go-cam/`, `groups/` (60 EBI gorule reports, 1.7 G), `go-rules/` replace the old flat per-dataset reports (`assigned-by-*`, `*-owltools-check.txt`, `*.report.json`, `*.gaferences.json`, `paint_*`, `noctua_*`, `sparta-report.json`, …).
- **`annotations/` restructure** — `{gaf,gpad,gpi}/MNEMONIC-{mod,uniprot}` replaces flat `cgd.gaf.gz`, `mgi.gaf.gz`, … (see `docs/annotations-mapping.md`; announced in #16).
- **Discontinued products** (current-only, deliberately not reproduced): `products/blazegraph` (17 G), `products/gaferencer`, `products/ttl` (2.1 G), `products/upstream_and_raw_data` (1.9 G).
- **Discontinued annotations** (current-only, deliberately not reproduced): `filtered_goa_uniprot_all.gaf.gz` (10.2 G) + `_noiea` variants — the single all-UniProt mega-GAF, replaced by the expanded per-proteome file base; `annotations/archive/` (1265 files, a 2025-08-22 one-time snapshot of *retired* datasets, e.g. `aspgd` — historical, not a live product).

### Publish-time — produced during bless, not in the build tree
- `index.html` at every level (built by `directory_indexer.py`).
- `metadata/release-archive-doi.json` (written after Zenodo mints the DOI).

### Gaps & decisions — status (resolved 2026-06-03)
1. **`filtered_goa_uniprot_all.gaf.gz` (10.2 G) + `_noiea`** — **DISCONTINUED.** The expanded per-proteome file base replaces the single all-UniProt mega-GAF; the new pipeline deliberately has no equivalent.
2. **`annotations/archive/` (1265 files, 8.9 G)** — **legacy, not a generative gap.** A one-time 2025-08-22 snapshot of *retired* datasets (e.g. `aspgd` — the full old per-dataset report + gaf/gpad/gpi sets) on the old bucket. The pipeline needn't reproduce it; carrying it forward to the new `current` is a one-time curation/migration choice, not pipeline work.
3. **`products/json/noctua-models-json.tgz`** — **MUST PRODUCE (confirmed not produced anywhere today).** Tracked: **#17**. pipeline-from-goa only *consumes* it (`MINERVA_JSON_TARBALL_URL`); pipeline-raw-go-cam has the tar+publish **commented out**; only the old `geneontology/pipeline` made it (`minerva-cli --dump-owl-json` → tar → `products/json/`). The dump mechanism already exists in `scripts/internal-all-gocam-products.sh`. **Ordering caveat:** the consumer (`gocam-processing.sh`) runs *before* the dump (`internal-all-gocam-products.sh`) in the current stage order, so producing it needs an earlier/dedicated stage or a reorder. (`go-cam-cx2`/`networkx`: treat as discontinued unless a consumer surfaces.)
4. **Generated metadata derivatives** (`db-xrefs.json`/`.legacy`, `GO.xrf_abbs`, `groups.ttl`, `users.ttl`, `eco-usage-constraints.json`) — **DONE & VERIFIED 2026-06-04 (#18).** Added as `scripts/produce-metadata-derivatives.sh` and wired into the metadata stage; the 2026-06-04 run produced all six on skyhook `metadata/`, which is now at full parity vs current (only the deliberately-dropped `.tmp.jsonld` intermediates and the publish-time `index.html`/`release-archive-doi.json` remain current-only). The TTLs are ~30% smaller in bytes than current but that is benign — byte-identical source YAML and equivalent graphs (groups 125 vs 124 statements; users 527 vs 524), just newer-ROBOT (v1.9.10) `oboInOwl` IRI abbreviation. Background: `go-site/metadata/` ships only the *source* YAML; the derived forms are generated by `go-site/scripts/` (`db-xrefs-yaml2legacy.js`, `yaml2turtle.sh`) which the script now runs.
5. **Downloads page** — **NOT a pipeline product; lives in `geneontology.github.io`** (`scripts/update_downloads.py`), tracked at **pipeline#396**. Corrected 2026-06-04: it feeds **only** on go-site `metadata/goex.yaml` (pulled from raw), emits a `downloads.html`, and links GAFs into skyhook — i.e. the website's job, so the original "`products/pages` → GitHub Pages takes over" stands; do not add a downloads-page generator here. **Known bug:** `update_downloads.py` predates the #15 annotations restructure — it links `annotations/{code}.gaf.gz` and `annotations/{code}-uniprot.gaf.gz` (flat) and emits a "MOD" `{code}.gaf.gz` link for *every* organism, but current skyhook is `annotations/gaf/{code}-mod.gaf.gz` (only ~23 MOD orgs) + `annotations/gaf/{code}-uniprot.gaf.gz`; GPI links to EBI, not skyhook `annotations/gpi/`. Fix lives in the website repo. (go-site `downloads-page-gen.py` is the OLD/superseded tool.)
6. **`ontology/`** — near-parity (skyhook 194 vs current 227); the diff is per-subdir `index.html` (publish-time) plus a handful of files (e.g. `external2go/wikipedia2go`, some `README`/`Makefile`/`.tmp`). File-level diff deferred unless it matters.

## Zenodo sizing (Path 2)

Biggest skyhook dirs (the archive's bulk):

| dir | files | size |
|---|---:|---:|
| products/solr | 2 | 11.0 G |
| ontology/extensions | 33 | 5.8 G |
| reports/groups | 60 | 1.7 G |
| ontology/imports | 45 | 674 M |
| annotations/gaf | 194 | 316 M |
| annotations/gpad | 194 | 299 M |
| internal/union-gaf-partitions | 10 | 261 M |
| ontology/{go-base,go,go-basic}.owl | 3 | ~390 M |
| annotations/gpi | 194 | 100 M |
| internal/all-go-cams-gpad | 54385 | 83 M |
| internal/all-true-go-cams-yaml | 3352 | 78 M |

**Implication:** total ~21.2 G, but `products/solr/golr-index-contents.tgz`
alone is ~11 G — over half. That maps cleanly onto the historical "main +
products" Zenodo split: archive the bulk tree (~10 G without solr) as the main
record, and the solr index (~11 G) as the separate "products" record (the old
products record was solr + the now-gone blazegraph journals). With
`filtered_goa_uniprot_all` and blazegraph gone, the main archive is ~10 G —
materially friendlier to upload than the old one that broke (#345).
