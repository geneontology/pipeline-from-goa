#!/bin/bash
#
# GO-CAM processing stage.
#
# Runs inside ubuntu:noble container with /workspace mounted from
# Jenkins workspace and /secrets containing credentials.
#
# Required env vars:
#   JENKINS_UID, JENKINS_GID
#   SKYHOOK_MACHINE
#   MINERVA_JSON_TARBALL_URL
#
# Required mounts:
#   /workspace -- Jenkins workspace (with gocam-py checked out)
#   /secrets/skyhook_key -- skyhook ssh key

set -euo pipefail

# WARNING: MEGAHACK -- the Jenkins host's docker network DNS is broken.
echo 'nameserver 8.8.8.8' > /etc/resolv.conf
echo 'search lbl.gov' >> /etc/resolv.conf

# Helper for retried apt-get install.
#
# archive.ubuntu.com is intermittently unreachable from this Jenkins
# host; build #77 lost the GO-CAM processing stage at 05:08 UTC when
# ~40 .deb fetches returned "Connection failed [IP: ... 80]". Same
# family of Ubuntu Noble flakiness as the awscli pip-vs-apt switch
# in commit e5a1f95 (issue #7); these system packages cannot move
# to pip (git, openssh-client, graphviz/libgraphviz-dev), so retry
# instead. Re-runs apt-get update between attempts in case the
# package index itself drifted during a partial outage.
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

# Install system dependencies.
DEBIAN_FRONTEND=noninteractive apt-get update
apt_install_retry python3 python3-pip python3-venv git openssh-client wget graphviz libgraphviz-dev

# Install uv (not available in Ubuntu apt repos).
pip3 install --break-system-packages uv

# Create jenkins user matching host UID/GID.
groupadd -g "$JENKINS_GID" jenkins || true
useradd -u "$JENKINS_UID" -g "$JENKINS_GID" -m -s /bin/bash jenkins
chown -R jenkins:jenkins /workspace
chown jenkins:jenkins /tmp

# Set up skyhook key for jenkins user.
cp /secrets/skyhook_key /home/jenkins/.skyhook_key
chown jenkins:jenkins /home/jenkins/.skyhook_key
chmod 0600 /home/jenkins/.skyhook_key

# Install gocam-py dependencies.
cd /workspace/gocam-py
chown -R jenkins:jenkins .
# Mark repo safe for git; needed because uv-dynamic-versioning uses git.
su jenkins -c 'git config --global --add safe.directory /workspace/gocam-py'
su jenkins -c 'uv sync --all-extras'

# Set up working directory structure.
su jenkins -c 'mkdir -p /tmp/gocam-work/input /tmp/gocam-work/01-gocam-models /tmp/gocam-work/02-true-gocams /tmp/gocam-work/02-pseudo-gocams /tmp/gocam-work/03-indexed-true-gocams /tmp/gocam-work/04-index-files /tmp/gocam-work/05-browser-search-docs /tmp/gocam-work/reports'

# Download and extract Minerva JSON tarball.
su jenkins -c "wget -q -O /tmp/gocam-work/minerva-models.tar.gz '${MINERVA_JSON_TARBALL_URL}'"
su jenkins -c 'tar -xzf /tmp/gocam-work/minerva-models.tar.gz -C /tmp/gocam-work/input'

# Download released GO ontology and GOC groups metadata from
# current.geneontology.org for use in step 3 (indexing).
su jenkins -c 'wget -q -O /tmp/gocam-work/go.obo https://current.geneontology.org/ontology/go.obo'
su jenkins -c 'wget -q -O /tmp/gocam-work/groups.yaml https://current.geneontology.org/metadata/groups.yaml'

# Step 1: Convert Minerva models to GO-CAM models.
su jenkins -c 'uv run python pipeline/convert_minerva_models_to_gocam_models.py --input-dir /tmp/gocam-work/input --output-dir /tmp/gocam-work/01-gocam-models --report-file /tmp/gocam-work/reports/01-convert.jsonl --verbose'

# Step 2: Filter true GO-CAM models from pseudo GO-CAMs.
su jenkins -c 'uv run python pipeline/filter_true_gocam_models.py --input-dir /tmp/gocam-work/01-gocam-models --output-dir /tmp/gocam-work/02-true-gocams --pseudo-gocam-output-dir /tmp/gocam-work/02-pseudo-gocams --report-file /tmp/gocam-work/reports/02-filter.jsonl --verbose'

# Step 3: Add query index (OAK lookups) to models.
# Uses released GO ontology via pronto adapter.
# NCBITaxon is not a GO product, so it still auto-downloads from
# OBO Foundry (sqlite:obo:ncbitaxon).
su jenkins -c 'uv run python pipeline/add_query_index_to_models.py --input-dir /tmp/gocam-work/02-true-gocams --output-dir /tmp/gocam-work/03-indexed-true-gocams --report-file /tmp/gocam-work/reports/03-index.jsonl --go-adapter-descriptor pronto:/tmp/gocam-work/go.obo --goc-groups-yaml /tmp/gocam-work/groups.yaml --verbose'

# Step 4: Generate index files (~6 JSON files).
su jenkins -c 'uv run python pipeline/generate_index_files.py --input-dir /tmp/gocam-work/03-indexed-true-gocams --output-dir /tmp/gocam-work/04-index-files --report-file /tmp/gocam-work/reports/04-index-files.jsonl --verbose'

# Step 5: Generate GO-CAM Browser search docs (1 JSON file).
su jenkins -c 'uv run python pipeline/generate_go_cam_browser_search_docs.py --input-dir /tmp/gocam-work/03-indexed-true-gocams --output /tmp/gocam-work/05-browser-search-docs/go-cam-browser-search-docs.json --report-file /tmp/gocam-work/reports/05-browser-search.jsonl --verbose'

# Lastly: Generate summary report (1 Excel file).
su jenkins -c "uv run python pipeline/generate_log_summary.py --logs-dir /tmp/gocam-work/reports --output /tmp/gocam-work/reports/summary.xlsx --metadata 'Release date=${START_DATE}' --metadata 'Pipeline name=pipeline-from-goa' --metadata 'Pipeline branch=${BRANCH_NAME}' --verbose"

# Helper for retried scp.
scp_retry() {
    local flags="$1"
    local src="$2"
    local dst="$3"
    local _i
    for _i in 1 2 3; do
        if su jenkins -c "scp $flags -o StrictHostKeyChecking=no -o IdentitiesOnly=true -o IdentityFile=/home/jenkins/.skyhook_key $src $dst"; then
            return 0
        fi
        sleep 5
    done
    return 1
}

# Upload release artifacts to skyhook.
scp_retry "-r" "/tmp/gocam-work/02-true-gocams/*"        "skyhook@${SKYHOOK_MACHINE}:/home/skyhook/pipeline-from-goa/main/go-cams/json/"
scp_retry "-r" "/tmp/gocam-work/03-indexed-true-gocams/*" "skyhook@${SKYHOOK_MACHINE}:/home/skyhook/pipeline-from-goa/main/products/indexed-go-cams/"
scp_retry "-r" "/tmp/gocam-work/04-index-files/*"        "skyhook@${SKYHOOK_MACHINE}:/home/skyhook/pipeline-from-goa/main/go-cams/index-json/"
scp_retry ""   "/tmp/gocam-work/05-browser-search-docs/go-cam-browser-search-docs.json" "skyhook@${SKYHOOK_MACHINE}:/home/skyhook/pipeline-from-goa/main/products/go-cam-search/"
scp_retry "-r" "/tmp/gocam-work/reports/*"               "skyhook@${SKYHOOK_MACHINE}:/home/skyhook/pipeline-from-goa/main/reports/go-cam/"

# Fix ownership so jenkins user can clean up.
chown -R "$JENKINS_UID:$JENKINS_GID" /workspace || true
