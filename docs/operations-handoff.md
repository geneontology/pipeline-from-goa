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

## Out of scope for this hand-off (separate / human)

- go-cam-browser data release (regenerate + commit `public/data.json` — "ping Patrick")
- amigo / metadata npm publishes
- downloads page (`geneontology.github.io`, driven from the pipeline session — see #396)
