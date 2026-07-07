# Defining-assumptions audit — the durable independent-agent check

## Why this exists

The pipeline's correctness rests on a few invariants (data provenance, one
ontology per run, reproducibility). A real bug — GOlr built from
`snapshot.geneontology.org`'s frozen ontology instead of our own, live in
production AmiGO for weeks (go-ontology#32154, #30) — sat **latent for ~18
months**. It was *tracked* (pipeline#394, closed on a partial fix), *rule-documented*
(the CLAUDE.md data-provenance directive), and *audited* (#3 — but for file paths,
not provenance) — and still shipped, because **nothing checked the code against the
rules end to end.**

A static lint is deliberately **not** used: our wiring assembles inputs across Groovy
vars, `docker -e` env passing, runtime `curl` of scripts, go-public re-hosts of
skyhook GAFs, and `$SKYHOOK_MACHINE` indirection — a grep either drowns in false
positives or is gamed by the next indirection. The durable check is an **independent
agent** (a fresh Claude with no stake in recent changes) that reads and reasons about
the whole data path. It **recommends**; a human triages and fixes — it does not
auto-edit.

## When to run

- **Pre-bless** — a release-readiness gate (Track A); no release ships un-audited.
- **Scheduled (weekly)** — catches latent debt + drift. A diff-scoped check would have
  sailed past the 18-month bug (nothing changed those lines), so the load-bearing run
  is **full end-to-end**, not diff-scoped.
- **On-demand** — `just audit` / `gh workflow run assumptions-audit.yaml`.
- A PR-diff pass is optional fast feedback at introduction; the full sweep is the
  backstop.

## The defining assumptions (the checklist the agent verifies)

1. **Input provenance.** Every input traces to EBI GOEx (incl. the `go-mirror` S3
   buffer) / this run's own skyhook output / a canonical GO git repo at run time.
   Nothing from our serving sites (`snapshot`/`current.geneontology.org`,
   `go-data-product-*`, `skyhook.berkeleybop.org`, `experimental.geneontology.io`)
   except the Exception Registry below.
2. **One ontology per run.** The GOEx-acquired ontology (→ skyhook `ontology/`) is the
   single copy every consumer (golr, minerva, validation, go-stats) uses.
3. **Own-output hops.** Each stage reads *this run's* skyhook tree — **respecting
   stage order** (a consumer stage must run *after* its producer). Trace acquire →
   derive → products → publish.
4. **Docker images.** Every `docker run` image is from a trusted source and **pinned**
   (a specific version tag or `@sha256` digest — not `:latest`/rolling).
5. **Reproducibility.** No input depends on un-pinned mutable state: floating docker
   tags (hard); unpinned in-container `apt`/`pip`/`npm`/`uv` installs (hard);
   serving-site reads (hard); moving `master`/`main` git grabs (soft — capture the
   SHA); unpinned upstream URLs (soft).
6. **Bless/publish invariants.** Overlay-only, order-correct, `internal/` excluded with
   the fetch-time backstop, Zenodo-before-publish gate.
7. **Exception drift.** The serving-site / mutable-external reads are *exactly* the
   Exception Registry — flag any new one.

## Exception Registry

The agent must **not** flag these, and **must** flag any serving-site / mutable-external
read that is **not** on this list. Keeping this table current *is* how Assumption 7 is
enforced.

| # | Exception | Where | Status |
|---|---|---|---|
| 1 | reacto-NEO ontojournal from legacy `skyhook.berkeleybop.org` | `internal-all-gocam-products.sh` | accepted interim (roadmap: port NEO in-pipeline) |
| 2 | prior-release stats/ontology/refs from `current` for go-stats **diffing** (`-s -n -p -r` + aggregated summaries) | `produce-derivatives.sh` | accepted (decision pending) |
| 3 | union GAFs re-hosted on go-public S3 (plain http) | `Jenkinsfile` `GOLR_INPUT_GAFS` | accepted — OWLTools can't read skyhook-HTTPS gzip (owltools#171 / #2) |
| 4 | NCBITaxon auto-download from OBO Foundry | `gocam-processing.sh` | soft — documented, foreign (non-GO); track toward a pinned source |
| 5 | `master`/`main` git grabs (go-site, go-stats, minerva, gocam-py, noctua-models) | `Jenkinsfile` `TARGET_*_BRANCH` | soft — allowed by provenance rule 3, but pin the resolved SHA (esp. noctua-models) |

## Agent prompt

**How to run it (semi-manual, human-triggered):** `just audit` prints the prompt below;
spawn a fresh **independent** agent (no stake in recent changes) with it against a clean
checkout at the repo root. The agent produces a PASS/VIOLATION report per assumption; **a
human triages, files, and fixes** — it does not auto-edit. A periodic nudge to do this
lands on the board via `.github/workflows/audit-reminder.yaml` (monthly; it only
*reminds* — it does not run the audit).

> You are an INDEPENDENT end-to-end assumptions auditor for pipeline-from-goa. Read
> `CLAUDE.md` fully (esp. "Data provenance", "Release model", "Jenkins CI"). Audit the
> `Jenkinsfile` + every `scripts/*` (+ any Dockerfiles). Verify the 7 defining
> assumptions in `docs/assumptions-audit.md`, classifying each finding against the
> Exception Registry there. Cover docker images (source + pinning) and reproducibility,
> not just hostnames — read and reason about the data path, do not pattern-match.
> Return PASS/VIOLATION per assumption with file:line + a concrete fix, then a
> prioritized list of net-new issues. Do NOT edit files.

## Open findings (last run: 2026-07-06)

- **Provenance — #30.** snapshot ontology reads: validation/minerva/golr `go-amigo.owl`
  + go-reports `-c go.obo` repointed to skyhook — **committed (718d64e), on main;** the
  next full build (Scan Repository Now) picks it up. Watch at build time: `go-amigo.owl`
  is read by OWLTools, and while it is plain (non-gzip) `.owl` and should be fine over
  skyhook-HTTPS, verify it doesn't hit owltools#171; if it does, push it to go-public S3
  and point plain-HTTP (mirror `GOLR_INPUT_GAFS`). **PANTHER** `GOLR_INPUT_PANTHER_TREES`
  still on snapshot (documented inline in the Jenkinsfile): it needs a **stage reorder**
  (build PANTHER trees before Produce-derivatives) + a go-public push (gzip → owltools#171)
  — the remaining #30 sub-item, not the #32154 cause.
- **Reproducibility / docker — #31.** floating `ubuntu:noble` (7 stages), unpinned
  in-container toolchain, noctua-models at `master`, NCBITaxon OBO download, two dead
  env vars.
