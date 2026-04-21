#!/usr/bin/env python3
"""
Download GOEx per-organism artifact files (GAF, GPAD, or GPI) for
every organism listed in metadata/goex.yaml.

Companion to geneontology/go-site:scripts/download_goex_data.py,
which is hard-wired to .gaf.gz and the EBI top-level GAF URL. This
helper is parameterized by --base-url and --extension so it can
mirror the four additional EBI subdirectories the pipeline-from-goa
restructure needs:

  uniprot-centric/gaf/   (.gaf.gz)
  uniprot-centric/gpad/  (.gpa.gz)
  uniprot-centric/gpi/   (.gpi.gz)
  gpad/                  (.gpa.gz)
  gpi/                   (.gpi.gz)

For .gaf.gz files the upstream script is still preferred where
applicable; this one exists because the upstream lacks an
--extension flag. Drop this script if go-site grows that feature.

Filename format mirrors EBI's: {code}_{taxon_id}_{proteome_id}.{ext}.gz

Usage:
    download_goex_files.py --base-url URL --extension EXT [--metadata PATH] OUTPUT_DIR

Examples:
    download_goex_files.py \
        --base-url https://mirror.geneontology.io/goex/current/uniprot-centric/gpad/ \
        --extension gpa.gz \
        /tmp/goex-download/uniprot-centric/gpad

Notes:
    - Skips files already present at OUTPUT_DIR (idempotent across retries).
    - Per-file 404 is logged and counted but does not abort.
    - Exits non-zero only if an unrecoverable error occurs (e.g. bad metadata)
      or if zero files were downloaded AND zero already existed.
"""

import argparse
import sys
import urllib.request
import urllib.error
from pathlib import Path
from typing import List, Tuple

import yaml


DEFAULT_METADATA_FILE = "/workspace/go-site/metadata/goex.yaml"
USER_AGENT = "GOEX-Downloader/1.0 (pipeline-from-goa)"
CHUNK_SIZE = 8192


def parse_taxon_id(s: str) -> str:
    return s.split(":")[-1]


def parse_proteome_id(s: str) -> str:
    return s.split(":")[-1]


def construct_filename(organism: dict, extension: str) -> str:
    code = organism["code_uniprot"]
    taxon = parse_taxon_id(organism["taxon_id"])
    proteome = parse_proteome_id(organism["uniprot_proteome_id"])
    return f"{code}_{taxon}_{proteome}.{extension}"


def download_one(url: str, dest: Path) -> Tuple[bool, str]:
    """Returns (ok, status). status is 'ok', 'skipped', '404', or 'error: <msg>'."""
    if dest.exists():
        return True, "skipped"
    tmp = dest.with_suffix(dest.suffix + ".tmp")
    req = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
    try:
        with urllib.request.urlopen(req) as resp, open(tmp, "wb") as out:
            while True:
                chunk = resp.read(CHUNK_SIZE)
                if not chunk:
                    break
                out.write(chunk)
        tmp.rename(dest)
        return True, "ok"
    except urllib.error.HTTPError as e:
        if tmp.exists():
            tmp.unlink()
        if e.code == 404:
            return False, "404"
        return False, f"error: HTTP {e.code}"
    except Exception as e:  # noqa: BLE001 - want to log everything
        if tmp.exists():
            tmp.unlink()
        return False, f"error: {e}"


def main() -> int:
    p = argparse.ArgumentParser(description="Download GOEx per-organism files for one extension.")
    p.add_argument("output_dir", help="Directory to write files into")
    p.add_argument("--base-url", required=True, help="URL prefix (must end with /)")
    p.add_argument("--extension", required=True, help="File extension without leading dot, e.g. 'gaf.gz', 'gpa.gz', 'gpi.gz'")
    p.add_argument("--metadata", default=DEFAULT_METADATA_FILE, help="Path to goex.yaml")
    args = p.parse_args()

    if not args.base_url.endswith("/"):
        args.base_url += "/"

    out = Path(args.output_dir)
    out.mkdir(parents=True, exist_ok=True)

    with open(args.metadata) as f:
        organisms: List[dict] = yaml.safe_load(f)["organisms"]

    n_ok = n_skipped = n_404 = n_err = 0
    for o in organisms:
        filename = construct_filename(o, args.extension)
        url = args.base_url + filename
        dest = out / filename
        ok, status = download_one(url, dest)
        if status == "ok":
            n_ok += 1
        elif status == "skipped":
            n_skipped += 1
        elif status == "404":
            n_404 += 1
            print(f"  404 {filename}", file=sys.stderr)
        else:
            n_err += 1
            print(f"  {status} {filename}", file=sys.stderr)

    print(
        f"summary: {n_ok} downloaded, {n_skipped} skipped (already present), "
        f"{n_404} not found, {n_err} errors out of {len(organisms)} organisms",
    )

    if n_ok == 0 and n_skipped == 0:
        print("ERROR: no files were downloaded or already present.", file=sys.stderr)
        return 1
    if n_err > 0:
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main())
