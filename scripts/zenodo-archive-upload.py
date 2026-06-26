#!/usr/bin/env python3
"""Archive a GO release tarball as a new Zenodo version (InvenioRDM Records API).

This is the "bless"-time Zenodo step: it mints a new DOI on an existing GO
concept so the DOI can be written into metadata/release-archive-doi.json before
the tree is copied to the release/current buckets (see docs/release-runbook.md).

Design notes / why it works this way
------------------------------------
* Records API, not the dead "deposit/secret-bucket" API (pipeline#345). Flow:
  GET concept latest -> POST /versions (new draft) -> PUT metadata ->
  3-step streamed file upload -> publish -> read top-level `doi`.
* Metadata is REUSED from the concept's own latest published version: we fetch
  its InvenioRDM-native serialization, sanitize it to the write schema, and
  override only `version` + `publication_date` (from the release's summary.txt).
  Nothing about the authors/license/references/description is hardcoded here --
  whatever the concept currently carries is what the new version inherits.
* The file is streamed with a constant-memory chunked PUT (validated to ~12 GiB
  on sandbox), so a multi-GB golr/products tarball never lands in RAM or needs a
  second on-disk copy.
* DOIs live at the TOP LEVEL of the record (`doi`, `conceptdoi`), NOT under
  `pids.doi.identifier`.

SAFETY: sandbox is the DEFAULT. Production (zenodo.org, real GO concepts) only
happens with an explicit `--production` flag AND a token in $ZENODO_TOKEN. Use
`--no-publish` for a first cautious run: it uploads everything but leaves the
draft unpublished for human review in the Zenodo UI (publishing is irreversible).

Tokens (never passed on the CLI):
    sandbox     -> $ZENODO_SANDBOX_TOKEN
    production  -> $ZENODO_TOKEN
"""
import argparse
import http.client
import json
import os
import re
import sys
import time
import urllib.error
import urllib.request

SANDBOX_HOST = "sandbox.zenodo.org"
PRODUCTION_HOST = "zenodo.org"
NATIVE = "application/vnd.inveniordm.v1+json"
CHUNK = 8 * 1024 * 1024


# --------------------------------------------------------------------------- #
# Small HTTP helpers (stdlib only).
# --------------------------------------------------------------------------- #
def api(host, method, path, token, body=None, accept="application/json"):
    """JSON API call. Returns (status, parsed-json). Exits on HTTP error."""
    headers = {"Authorization": f"Bearer {token}", "Accept": accept}
    data = None
    if body is not None:
        data = json.dumps(body).encode()
        headers["Content-Type"] = "application/json"
    req = urllib.request.Request(f"https://{host}{path}", data=data,
                                 method=method, headers=headers)
    try:
        with urllib.request.urlopen(req, timeout=120) as r:
            raw = r.read()
            return r.status, (json.loads(raw) if raw else None)
    except urllib.error.HTTPError as e:
        sys.exit(f"FATAL: HTTP {e.code} {method} {path}\n"
                 f"       {e.read()[:800].decode('utf-8', 'replace')}")


def get_public(host, path, accept):
    """Unauthenticated GET (reading a concept's public metadata)."""
    req = urllib.request.Request(f"https://{host}{path}",
                                 headers={"Accept": accept, "User-Agent": "go-zenodo-upload"})
    with urllib.request.urlopen(req, timeout=60) as r:
        return json.loads(r.read())


def stream_put_file(host, path, token, filepath, size, attempts=3):
    """Constant-memory chunked PUT of a real file, with bounded retry on transient
    failures (5xx / connection errors). A PUT replaces the whole content, so each
    retry safely re-streams the entire file. Returns (status, body, secs)."""
    last = None
    for attempt in range(1, attempts + 1):
        conn = None
        try:
            conn = http.client.HTTPSConnection(host, timeout=900)
            conn.putrequest("PUT", path, skip_accept_encoding=True)
            conn.putheader("Authorization", f"Bearer {token}")
            conn.putheader("Content-Type", "application/octet-stream")
            conn.putheader("Content-Length", str(size))
            conn.endheaders()
            sent = 0
            t0 = time.time()
            mark = 1024 ** 3
            with open(filepath, "rb") as fh:
                while True:
                    block = fh.read(CHUNK)
                    if not block:
                        break
                    conn.send(block)
                    sent += len(block)
                    if sent >= mark:
                        el = time.time() - t0
                        print(f"      {sent/1024**3:6.1f} GiB sent  ({sent/el/1024**2:5.0f} MiB/s)",
                              flush=True)
                        mark += 1024 ** 3
            if sent != size:
                sys.exit(f"FATAL: read {sent} bytes but Content-Length was {size}")
            resp = conn.getresponse()
            body = resp.read()
            conn.close()
            if resp.status >= 500 and attempt < attempts:
                last = f"HTTP {resp.status}"
                print(f"  upload got {resp.status} (attempt {attempt}/{attempts}); "
                      f"re-streaming after backoff...", flush=True)
                time.sleep(min(30, 5 * attempt))
                continue
            return resp.status, body, time.time() - t0
        except (http.client.HTTPException, OSError) as e:
            last = repr(e)
            if conn is not None:
                try:
                    conn.close()
                except OSError:
                    pass
            if attempt >= attempts:
                sys.exit(f"FATAL: upload PUT failed after {attempts} attempts: {last}")
            print(f"  upload error (attempt {attempt}/{attempts}): {e}; "
                  f"re-streaming after backoff...", flush=True)
            time.sleep(min(30, 5 * attempt))
    sys.exit(f"FATAL: upload PUT failed after {attempts} attempts: {last}")


# --------------------------------------------------------------------------- #
# Metadata reuse.
# --------------------------------------------------------------------------- #
def sanitize_metadata(native, version):
    """Reduce a concept's InvenioRDM-native metadata to a write-safe block,
    reusing everything and overriding only version + publication_date."""
    out = {"title": native["title"],
           "publisher": native.get("publisher", "Zenodo"),
           "resource_type": {"id": native["resource_type"]["id"]},
           "version": version,
           "publication_date": version}
    if native.get("description"):
        out["description"] = native["description"]
    if native.get("rights"):
        out["rights"] = [{"id": r["id"]} for r in native["rights"] if r.get("id")]
    if native.get("references"):
        out["references"] = [{"reference": r["reference"]}
                             for r in native["references"] if r.get("reference")]
    creators = []
    for c in native.get("creators", []):
        po = c.get("person_or_org", {})
        keep = {"type": po.get("type", "personal")}
        for k in ("given_name", "family_name", "name"):
            if po.get(k):
                keep[k] = po[k]
        # personal creators are identified by family/given; drop derived `name`
        if keep["type"] == "personal" and "family_name" in keep:
            keep.pop("name", None)
        if po.get("identifiers"):
            keep["identifiers"] = po["identifiers"]
        entry = {"person_or_org": keep}
        affs = []
        for a in c.get("affiliations", []):
            aff = {}
            if a.get("name"):
                aff["name"] = a["name"]
            if a.get("id"):
                aff["id"] = a["id"]
            if aff:
                affs.append(aff)
        if affs:
            entry["affiliations"] = affs
        creators.append(entry)
    if creators:
        out["creators"] = creators
    return out


def read_version(version_from):
    """Extract the release version (YYYY-MM-DD) from a summary.txt path or URL."""
    if re.match(r"^https?://", version_from):
        text = get_text(version_from)
    else:
        with open(version_from, encoding="utf-8") as fh:
            text = fh.read()
    m = re.search(r"^Start date:\s*(\d{4}-\d{2}-\d{2})\s*$", text, re.MULTILINE)
    if not m:
        sys.exit(f"FATAL: no 'Start date: YYYY-MM-DD' line in {version_from}")
    return m.group(1)


def get_text(url):
    req = urllib.request.Request(url, headers={"User-Agent": "go-zenodo-upload"})
    with urllib.request.urlopen(req, timeout=60) as r:
        return r.read().decode("utf-8", "replace")


# --------------------------------------------------------------------------- #
def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--concept", required=True,
                    help="Concept (or any version) record id on the target server")
    ap.add_argument("--file", required=True, help="Tarball to archive")
    ver = ap.add_mutually_exclusive_group(required=True)
    ver.add_argument("--version", help="Release version string, e.g. 2026-06-04")
    ver.add_argument("--version-from", help="summary.txt path/URL to read 'Start date:' from")
    ap.add_argument("--output", default="release-archive-doi.json",
                    help="Where to write {\"doi\": ...} (default: release-archive-doi.json)")
    ap.add_argument("--remote-name", help="Filename to store in Zenodo (default: basename of --file)")
    env = ap.add_mutually_exclusive_group()
    env.add_argument("--sandbox", action="store_true", default=True,
                     help="Use sandbox.zenodo.org (DEFAULT)")
    env.add_argument("--production", action="store_true",
                     help="Use zenodo.org -- REAL GO concepts. Explicit opt-in.")
    ap.add_argument("--no-publish", action="store_true",
                    help="Upload but DON'T publish; leave draft for human review")
    args = ap.parse_args()

    production = args.production
    host = PRODUCTION_HOST if production else SANDBOX_HOST
    token_env = "ZENODO_TOKEN" if production else "ZENODO_SANDBOX_TOKEN"
    token = os.environ.get(token_env)
    if not token:
        sys.exit(f"FATAL: ${token_env} not set (required for "
                 f"{'PRODUCTION' if production else 'sandbox'})")

    if not os.path.isfile(args.file):
        sys.exit(f"FATAL: no such file: {args.file}")
    size = os.path.getsize(args.file)
    fname = args.remote_name or os.path.basename(args.file)
    version = args.version or read_version(args.version_from)

    banner = "PRODUCTION (zenodo.org)" if production else "sandbox (sandbox.zenodo.org)"
    print("=" * 64)
    print(f"  Zenodo archive upload -> {banner}")
    print(f"  concept={args.concept}  version={version}")
    print(f"  file={args.file}  ({size:,} bytes) as {fname}")
    if args.no_publish:
        print("  --no-publish: draft will be left UNPUBLISHED for review")
    print("=" * 64)

    # 1. Resolve the concept's latest published version + its native metadata.
    latest = get_public(host, f"/api/records/{args.concept}", NATIVE)
    latest_id = latest["id"]
    meta = sanitize_metadata(latest["metadata"], version)
    # native serializer keeps the DOI under pids, not top-level
    latest_doi = latest.get("doi") or latest.get("pids", {}).get("doi", {}).get("identifier")
    print(f"  latest published version: id={latest_id} "
          f"version={latest['metadata'].get('version')!r} doi={latest_doi}")
    print(f"  reusing metadata: title={meta['title']!r} "
          f"creators={len(meta.get('creators', []))} rights={meta.get('rights')}")

    # 2. New version draft.
    _, draft = api(host, "POST", f"/api/records/{latest_id}/versions", token)
    draft_id = draft["id"]
    print(f"  new draft id={draft_id}")

    # 3. Set metadata (re-supplied in full; robust to InvenioRDM blanking).
    api(host, "PUT", f"/api/records/{draft_id}/draft", token,
        body={"metadata": meta, "access": {"record": "public", "files": "public"}})

    # 4. Clear any inherited files, then stream ours in (3-step).
    _, files = api(host, "GET", f"/api/records/{draft_id}/draft/files", token)
    for ent in (files or {}).get("entries", []):
        api(host, "DELETE", f"/api/records/{draft_id}/draft/files/{ent['key']}", token)
    api(host, "POST", f"/api/records/{draft_id}/draft/files", token, body=[{"key": fname}])
    print(f"  streaming {size/1024**3:.2f} GiB ...")
    st, rb, el = stream_put_file(
        host, f"/api/records/{draft_id}/draft/files/{fname}/content", token, args.file, size)
    if st not in (200, 201):
        sys.exit(f"FATAL: upload PUT status={st}: {rb[:400]}")
    api(host, "POST", f"/api/records/{draft_id}/draft/files/{fname}/commit", token)
    _, fm = api(host, "GET", f"/api/records/{draft_id}/draft/files/{fname}", token)
    if fm.get("size") != size:
        sys.exit(f"FATAL: size mismatch after commit: zenodo={fm.get('size')} local={size}")
    print(f"  uploaded + committed ({size/el/1024**2:.0f} MiB/s avg); size verified.")

    # 5. Publish (unless review mode).
    if args.no_publish:
        print(f"\n  DRAFT READY (unpublished): https://{host}/uploads/{draft_id}")
        print("  Review in the Zenodo UI, then publish there or re-run without --no-publish.")
        return
    api(host, "POST", f"/api/records/{draft_id}/draft/actions/publish", token)
    rec = get_public(host, f"/api/records/{draft_id}", "application/json")
    doi = rec.get("doi")
    if not doi:
        sys.exit("FATAL: published but no top-level doi on record")
    with open(args.output, "w", encoding="utf-8") as fh:
        json.dump({"doi": doi}, fh, indent=2)
        fh.write("\n")
    print(f"\n  PUBLISHED  version doi={doi}  conceptdoi={rec.get('conceptdoi')}")
    print(f"  record: https://{host}/records/{draft_id}")
    print(f"  wrote {args.output}: {{\"doi\": \"{doi}\"}}")


if __name__ == "__main__":
    main()
