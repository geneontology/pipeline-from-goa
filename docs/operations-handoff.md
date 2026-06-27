# Operations hand-off: golr / amigo production deploy

After the core data **publish** (the "bless") lands on `current.geneontology.org`,
the production **golr + amigo** deploy is owned by the **`operations`** repo, not
this pipeline. The deploy reads its inputs over HTTP from `current.geneontology.org`,
so publishing to `go-data-product-current` is exactly what unblocks it. This brief is
what the `operations` session needs to run that step. (See also `release-runbook.md`
for the full lifecycle; deploys deliberately live in `operations` per `CLAUDE.md`.)

## This release

- **Pipeline:** `pipeline-from-goa` `main`, build **#86**
- **Release date:** **2026-06-19**
- **Zenodo DOIs:**
  - main archive — `10.5281/zenodo.20943148`
  - secondary products — `10.5281/zenodo.20941845`
- **Published to:** `go-data-product-current` (current.geneontology.org) and
  `go-data-product-release/2026-06-19` (release.geneontology.org); both CloudFront
  distributions invalidated (`E3Q4YIZHZL7358` current, `E2HF1DWYYDLTQP` release).

## Timing gate (important)

Run the deploy **only after** the publish completes and the `current` CloudFront
invalidation settles. The deploy's three inputs — in particular
`metadata/release-archive-doi.json` — exist on `current` **only post-publish**: the
DOI json was minted into the publish *copy*, not the skyhook build (it 404s on
skyhook by design). Deploying before the publish reads a stale/missing DOI json.

## Inputs the deploy reads (`operations/ansible/update-golr.yaml`)

| URL (on `current.geneontology.org`) | what |
| --- | --- |
| `/products/solr/golr-index-contents.tgz` | the golr/solr index (~13.1 GB) |
| `/products/solr/golr_timestamp.log` | load timestamp |
| `/metadata/release-archive-doi.json` | `{"doi": "10.5281/zenodo.20943148"}` |

`update-golr.yaml` targets host `amigo-golr` by default.

## Run order (in the `operations` repo)

1. **`ansible/update-golr.yaml`** — loads golr from `current` (the three inputs above).
2. **`ansible/amigo-golr-up-production.yml`** — brings up the amigo/golr production
   stack (`amigo.geneontology.org`, `golr.geneontology.org`).

> Confirm the exact `ansible-playbook` invocation + hosts inventory inside the
> `operations` session; the playbook names and inputs above are verified, the precise
> command line is owned there.

## Pre-deploy sanity (curl `current`)

```bash
curl -sI  http://current.geneontology.org/products/solr/golr-index-contents.tgz   # expect 200
curl -s   http://current.geneontology.org/products/solr/golr_timestamp.log         # expect the 2026-06-19 load
curl -s   http://current.geneontology.org/metadata/release-archive-doi.json        # expect doi 10.5281/zenodo.20943148
```

## Downstream consumer updates (track these — not "out of scope")

The golr/amigo/api deploy above is the operations-owned core, but the release is
not done until the downstream consumer surfaces reflect it too. These live in
other repos / with other people, but they belong on the release board (see
`release-runbook.md` "Definition of done") — listed here so the operations
session sees the whole board, not just golr/amigo/api.

| Surface | Action this release | Owner | Tracking |
| --- | --- | --- | --- |
| **go-stats / `stats.html`** | **None.** `release_stats/` (the go-stats output, e.g. `go-stats-summary.json` carrying the `release_date`, and `aggregated-go-stats-summaries.json`) is generated **in the pipeline** (Phase 2) and published with the tree; `geneontology.org/stats.html` fetches `release_stats/` dynamically. Supersedes the old SNS-triggered post-publish go-stats step — no separate action. | pipeline | — |
| **Downloads page** | Regenerate / repoint the by-organism annotation downloads to `current`; now served **in-site** at `geneontology.org/docs/download-go-annotations/downloads/` (links use the new `annotations/gaf/`·`gpi/` layout). | `geneontology.github.io` | #396, gh.io#930 |
| **Downloads old-URL forward** | CloudFront **Function** 301 `/products/pages/downloads.html` → the in-site page. Associate **after** gh.io#930 deploys, else it 301s to a 404. | **operations** | operations#86 |
| **go-cam-browser data** | Regenerate + commit `public/data.json` (`data-release-YYYY-MM-DD` branch → merge → Pages auto-deploy). "ping Patrick". | `go-cam-browser` | per-release |
| **npm packages** | `amigo` / metadata / `dbxrefs` — **only if their content changed** this release; not automatic per data release. | software | conditional |
| **Release notes / announcement** | Only when there is a change or error. | human | — |
