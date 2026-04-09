#!/bin/bash
#
# Populate the GOEx mirror.
#
# Best-effort: downloads all GOEx GAF files from the EBI FTP and
# uploads them to s3://go-mirror/goex/current/gaf/, then invalidates
# the corresponding CloudFront paths so the new content is visible
# at https://mirror.geneontology.io/goex/current/gaf/.
#
# This script is invoked from a stage that wraps it in try/catch in
# the Jenkinsfile, so a failure here is non-fatal -- the rest of
# the pipeline will fall back to whatever is currently in the
# mirror from the last successful populate run.
#
# Runs inside the ubuntu:noble container with /workspace mounted
# from the Jenkins workspace (which has go-site cloned at
# /workspace/go-site-for-mirror for download_goex_data.py and
# its metadata/goex.yaml manifest).
#
# Required env vars:
#   JENKINS_UID, JENKINS_GID
#   AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY
#   GOEX_MIRROR_CLOUDFRONT_DISTRIBUTION_ID
#
# Required mounts:
#   /workspace -- Jenkins workspace (with go-site cloned)

# Note: not using `set -e` because we manage exit codes ourselves
# inside the retry loop.
set -uo pipefail

LOCAL_DIR='/tmp/goex-mirror-staging'
S3_DEST='s3://go-mirror/goex/current/gaf/'
CF_INVALIDATE_PATH='/goex/current/gaf/*'
DOWNLOAD_ATTEMPTS=5
DOWNLOAD_BACKOFF_SECONDS=60

# WARNING: MEGAHACK -- the Jenkins host's docker network DNS is broken.
echo 'nameserver 8.8.8.8' > /etc/resolv.conf
echo 'search lbl.gov' >> /etc/resolv.conf

# Install system dependencies.
DEBIAN_FRONTEND=noninteractive apt-get update
DEBIAN_FRONTEND=noninteractive apt-get -y install python3 python3-yaml awscli

# Create jenkins user matching host UID/GID.
groupadd -g "$JENKINS_GID" jenkins || true
useradd -u "$JENKINS_UID" -g "$JENKINS_GID" -m -s /bin/bash jenkins
chown -R jenkins:jenkins /workspace
chown jenkins:jenkins /tmp

# Set up local download directory.
mkdir -p "$LOCAL_DIR"
chown -R jenkins:jenkins "$LOCAL_DIR"

cd /workspace/go-site-for-mirror || exit 1
chown -R jenkins:jenkins .

# Download all GOEx GAFs from EBI. download_goex_data.py is
# incremental: each retry only re-attempts the files that are still
# missing locally, so we get cheap progress on flaky connections.
for n in $(seq 1 "$DOWNLOAD_ATTEMPTS"); do
    echo "=== Download attempt $n of $DOWNLOAD_ATTEMPTS ==="
    if su jenkins -c "python3 scripts/download_goex_data.py $LOCAL_DIR"; then
        echo "Download succeeded on attempt $n."
        break
    fi
    if [ "$n" -eq "$DOWNLOAD_ATTEMPTS" ]; then
        echo "All $DOWNLOAD_ATTEMPTS download attempts failed. Aborting populate."
        exit 1
    fi
    echo "Download attempt $n failed. Sleeping ${DOWNLOAD_BACKOFF_SECONDS}s before retry."
    sleep "$DOWNLOAD_BACKOFF_SECONDS"
done

# Sanity check: refuse to push a suspiciously empty cache to the
# mirror, which would clobber a working state.
file_count=$(find "$LOCAL_DIR" -name '*.gaf.gz' -type f | wc -l)
echo "Downloaded $file_count GAF files to $LOCAL_DIR."
if [ "$file_count" -lt 100 ]; then
    echo "Refusing to sync: too few files ($file_count < 100). Mirror left untouched."
    exit 1
fi

# Push to s3://go-mirror/goex/current/gaf/ with the official AWS CLI.
# `aws s3 sync` only uploads files where size or mtime differ.
echo "Syncing $file_count files to $S3_DEST ..."
aws s3 sync "$LOCAL_DIR/" "$S3_DEST" --no-progress

# Invalidate the CloudFront cache for the goex/gaf path so the
# new content is visible at https://mirror.geneontology.io/...
if [ -n "${GOEX_MIRROR_CLOUDFRONT_DISTRIBUTION_ID:-}" ] && \
   [ "$GOEX_MIRROR_CLOUDFRONT_DISTRIBUTION_ID" != "null" ]; then
    echo "Invalidating CloudFront paths $CF_INVALIDATE_PATH ..."
    aws cloudfront create-invalidation \
        --distribution-id "$GOEX_MIRROR_CLOUDFRONT_DISTRIBUTION_ID" \
        --paths "$CF_INVALIDATE_PATH"
else
    echo "GOEX_MIRROR_CLOUDFRONT_DISTRIBUTION_ID not set; skipping invalidation."
fi

echo "Mirror populate complete."
