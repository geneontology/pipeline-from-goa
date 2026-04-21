#!/bin/bash
#
# Populate the GOEx mirror.
#
# Best-effort: mirrors a curated set of EBI GOEx subdirectories to
# s3://go-mirror/goex/current/<subdir>/ and invalidates the
# corresponding CloudFront paths so the new content is visible at
# https://mirror.geneontology.io/goex/current/<subdir>/.
#
# Mirrored subdirectories (six in total):
#   gaf/, gpad/, gpi/                        (MOD-id-space artifacts)
#   uniprot-centric/{gaf,gpad,gpi}/          (UniProt-id-space artifacts)
#
# This script is invoked from a stage that wraps it in try/catch in
# the Jenkinsfile, so a failure here is non-fatal -- the rest of
# the pipeline will fall back to whatever is currently in the
# mirror from the last successful populate run.
#
# Required env vars:
#   JENKINS_UID, JENKINS_GID
#   AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY
#   GOEX_MIRROR_CLOUDFRONT_DISTRIBUTION_ID
#
# Required mounts:
#   /workspace -- Jenkins workspace

# Note: not using `set -e` because we manage exit codes ourselves
# inside the retry loop.
set -uo pipefail

EBI_BASE='https://ftp.ebi.ac.uk/pub/contrib/goa/goex/current'
LOCAL_BASE='/tmp/goex-mirror-staging'
S3_BASE='s3://go-mirror/goex/current'
DOWNLOAD_ATTEMPTS=5
DOWNLOAD_BACKOFF_SECONDS=60
SANITY_MIN_CANONICAL_GAFS=100

# Six EBI subdirectories to mirror, in walk order.
MIRROR_PATHS=(
    'gaf'
    'gpad'
    'gpi'
    'uniprot-centric/gaf'
    'uniprot-centric/gpad'
    'uniprot-centric/gpi'
)

# WARNING: MEGAHACK -- the Jenkins host's docker network DNS is broken.
echo 'nameserver 8.8.8.8' > /etc/resolv.conf
echo 'search lbl.gov' >> /etc/resolv.conf

# Helper for retried apt-get install. Same pattern as
# scripts/gocam-processing.sh -- archive.ubuntu.com is intermittently
# unreachable from this Jenkins host.
apt_install_retry() {
    local _i
    for _i in 1 2 3; do
        if DEBIAN_FRONTEND=noninteractive apt-get -y install "$@"; then
            return 0
        fi
        echo "apt-get install attempt ${_i} failed; sleeping 30s before retry"
        sleep 30
        DEBIAN_FRONTEND=noninteractive apt-get update || true
    done
    return 1
}

# Install system dependencies. awscli was removed from Ubuntu Noble's
# repos; install via pip instead.
DEBIAN_FRONTEND=noninteractive apt-get update
apt_install_retry python3 python3-pip wget
pip3 install --break-system-packages awscli

# Create jenkins user matching host UID/GID.
groupadd -g "$JENKINS_GID" jenkins || true
useradd -u "$JENKINS_UID" -g "$JENKINS_GID" -m -s /bin/bash jenkins
chown -R jenkins:jenkins /workspace
chown jenkins:jenkins /tmp

# Set up local staging tree.
mkdir -p "$LOCAL_BASE"
chown -R jenkins:jenkins "$LOCAL_BASE"

# Mirror one EBI subdirectory to a local staging directory using
# wget. --timestamping skips files that haven't changed; -nc avoids
# clobbering on retries; -nd flattens into the target so layout is
# controlled by --directory-prefix.
mirror_subdir() {
    local sub="$1"
    local target="${LOCAL_BASE}/${sub}"
    local url="${EBI_BASE}/${sub}/"

    mkdir -p "$target"
    chown -R jenkins:jenkins "$target"

    local n
    for n in $(seq 1 "$DOWNLOAD_ATTEMPTS"); do
        echo "=== Mirror ${sub} attempt ${n} of ${DOWNLOAD_ATTEMPTS} ==="
        if su jenkins -c "wget --quiet --tries=3 --timestamping --recursive --level=1 --no-parent --no-directories --no-host-directories --execute robots=off --reject 'index.html*,robots.txt' --directory-prefix='${target}' '${url}'"; then
            echo "Mirror ${sub} succeeded on attempt ${n}."
            return 0
        fi
        if [ "$n" -eq "$DOWNLOAD_ATTEMPTS" ]; then
            echo "All ${DOWNLOAD_ATTEMPTS} mirror attempts for ${sub} failed."
            return 1
        fi
        echo "Mirror ${sub} attempt ${n} failed. Sleeping ${DOWNLOAD_BACKOFF_SECONDS}s before retry."
        sleep "$DOWNLOAD_BACKOFF_SECONDS"
    done
    return 1
}

for sub in "${MIRROR_PATHS[@]}"; do
    if ! mirror_subdir "$sub"; then
        echo "Aborting populate: could not mirror ${sub}."
        exit 1
    fi
done

# Sanity check: refuse to push a suspiciously empty cache to the
# mirror, which would clobber a working state. The canonical gaf/
# count is the most stable signal across releases.
canonical_gaf_count=$(find "${LOCAL_BASE}/gaf" -name '*.gaf.gz' -type f | wc -l)
echo "Downloaded ${canonical_gaf_count} canonical GAF files to ${LOCAL_BASE}/gaf."
if [ "$canonical_gaf_count" -lt "$SANITY_MIN_CANONICAL_GAFS" ]; then
    echo "Refusing to sync: too few canonical GAFs (${canonical_gaf_count} < ${SANITY_MIN_CANONICAL_GAFS}). Mirror left untouched."
    exit 1
fi

# Push each mirrored subdir to its S3 destination.
# `aws s3 sync` only uploads files where size or mtime differ.
for sub in "${MIRROR_PATHS[@]}"; do
    src="${LOCAL_BASE}/${sub}/"
    dest="${S3_BASE}/${sub}/"
    echo "Syncing ${src} to ${dest} ..."
    aws s3 sync "$src" "$dest" --no-progress
done

# Invalidate CloudFront for all mirrored paths in a single call.
if [ -n "${GOEX_MIRROR_CLOUDFRONT_DISTRIBUTION_ID:-}" ] && \
   [ "$GOEX_MIRROR_CLOUDFRONT_DISTRIBUTION_ID" != 'null' ]; then
    invalidation_paths=()
    for sub in "${MIRROR_PATHS[@]}"; do
        invalidation_paths+=("/goex/current/${sub}/*")
    done
    echo "Invalidating CloudFront paths: ${invalidation_paths[*]}"
    aws cloudfront create-invalidation \
        --distribution-id "$GOEX_MIRROR_CLOUDFRONT_DISTRIBUTION_ID" \
        --paths "${invalidation_paths[@]}"
else
    echo 'GOEX_MIRROR_CLOUDFRONT_DISTRIBUTION_ID not set; skipping invalidation.'
fi

echo 'Mirror populate complete.'
