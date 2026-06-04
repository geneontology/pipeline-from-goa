#!/bin/bash
#
# Annotation download, restructure, and partition stage.
#
# Syncs the GOEx annotation set (GAF, GPAD, GPI) from the GOEx mirror
# S3 bucket (s3://go-mirror/goex/current/), lands it in the
# pipeline-from-goa output layout, and partitions the canonical GAF
# set into the union-* files used for downstream indexing.
#
# As of EBI GOEx's filename simplification (go-site#2681), EBI publishes
# per-species files already named in our target scheme --
# SPECIES-{uniprot,mod}.<ext>.gz -- with exactly one variant per species
# in the top-level dirs, plus an all-uniprot view under uniprot-centric/.
# So this stage is now essentially a passthrough copy; no mnemonic
# parsing or goex.yaml-driven MOD filtering is needed.
#
# Output layout on skyhook (model: uniprot-all + mod-where-available):
#   annotations/gaf/SPECIES-uniprot.gaf.gz    (all 171, from uniprot-centric/)
#   annotations/gaf/SPECIES-mod.gaf.gz        (~18, the EBI MOD variants)
#   annotations/gpad/SPECIES-{uniprot,mod}.gpad.gz
#   annotations/gpi/SPECIES-{uniprot,mod}.gpi.gz
#   internal/union-gaf-partitions/union_*.gaf.gz  (10 partitions)
#
# The uniprot view comes from EBI uniprot-centric/ (one -uniprot file
# per species); the mod view comes from the top-level dirs' *-mod files
# (only the species for which EBI ships a MOD variant). EBI's `.gpa.gz`
# extension is normalized to `.gpad.gz` on landing. Old pre-#2681
# names (SPECIES_taxon_proteome) are ignored: they match neither the
# *-uniprot nor *-mod glob, so a still-dirty mirror cannot leak them.
#
# The union/golr partition source is the canonical one-per-species set
# (the top-level GAF dir's new-scheme files), NOT the uniprot-all set,
# so MOD species are counted once.
#
# Runs inside ubuntu:noble container with /workspace mounted from
# Jenkins workspace and /secrets containing credentials.
#
# Required env vars:
#   JENKINS_UID, JENKINS_GID
#   SKYHOOK_MACHINE
#   AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY
#
# Required mounts:
#   /workspace -- Jenkins workspace (go-site checked out for
#                 scripts/partition_and_merge_gaf.py)
#   /secrets/skyhook_key -- skyhook ssh key
#   /secrets/s3cmd.cfg -- s3cmd configuration

set -euo pipefail

# Read directly from the S3 bucket that the Populate GOEx mirror
# stage writes to, rather than going through the CloudFront-fronted
# https://mirror.geneontology.io/ (which does not serve directory
# listings and so cannot be walked). aws s3 sync handles listing
# and skip-existing for us.
S3_MIRROR='s3://go-mirror/goex/current'
SUBDIRS=(
    'gaf'
    'gpad'
    'gpi'
    'uniprot-centric/gaf'
    'uniprot-centric/gpad'
    'uniprot-centric/gpi'
)
DOWNLOAD_BASE='/tmp/goex-download'
STAGED_BASE='/tmp/goex-staged'
CANON_GAF='/tmp/goex-canonical-gaf'
SKYHOOK_MAIN="skyhook@${SKYHOOK_MACHINE}:/home/skyhook/pipeline-from-goa/main"

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

# Install system dependencies. awscli is installed via pip because
# Ubuntu Noble dropped it from apt (see issue #7's e5a1f95 fix).
DEBIAN_FRONTEND=noninteractive apt-get update
apt_install_retry python3 python3-pip openssh-client rsync s3cmd
pip3 install --break-system-packages awscli

# Create jenkins user matching host UID/GID.
groupadd -g "$JENKINS_GID" jenkins || true
useradd -u "$JENKINS_UID" -g "$JENKINS_GID" -m -s /bin/bash jenkins
chown -R jenkins:jenkins /workspace
chown jenkins:jenkins /tmp

# Set up skyhook key for jenkins user.
cp /secrets/skyhook_key /home/jenkins/.skyhook_key
chown jenkins:jenkins /home/jenkins/.skyhook_key
chmod 0600 /home/jenkins/.skyhook_key

# go-site is checked out here for scripts/partition_and_merge_gaf.py.
cd /workspace/go-site
chown -R jenkins:jenkins .

# Sync each mirrored EBI subdir down from S3 into a parallel local
# tree. We do this as root (no need to drop privileges for read-only
# downloads), then chown for the rest of the pipeline.
mkdir -p "$DOWNLOAD_BASE"

for sub in "${SUBDIRS[@]}"; do
    target="${DOWNLOAD_BASE}/${sub}"
    src="${S3_MIRROR}/${sub}/"
    mkdir -p "$target"
    echo "=== Syncing ${src} -> ${target} ==="
    aws s3 sync "$src" "${target}/" --no-progress
done

chown -R jenkins:jenkins "$DOWNLOAD_BASE"

# Stage files into the skyhook target layout: a flat dir per format
# under annotations/. EBI already names files SPECIES-{uniprot,mod},
# so staging is a passthrough copy with .gpa.gz -> .gpad.gz extension
# normalization only.
mkdir -p \
    "${STAGED_BASE}/annotations/gaf" \
    "${STAGED_BASE}/annotations/gpad" \
    "${STAGED_BASE}/annotations/gpi"

# Copy one EBI file to a staged dir, normalizing the extension.
#   $1 src file   $2 staged dir   $3 EBI ext   $4 output ext
stage_copy() {
    local src="$1" staged="$2" ebi_ext="$3" out_ext="$4" base out
    base=$(basename "$src")
    out="${base%."${ebi_ext}".gz}.${out_ext}.gz"
    cp "$src" "${staged}/${out}"
}

# Per-format spec: <fmt>:<EBI ext>:<output ext>. EBI uses .gpa for GPAD.
for spec in 'gaf:gaf:gaf' 'gpad:gpa:gpad' 'gpi:gpi:gpi'; do
    fmt="${spec%%:*}"
    rest="${spec#*:}"
    ebi_ext="${rest%%:*}"
    out_ext="${rest##*:}"
    staged_dir="${STAGED_BASE}/annotations/${fmt}"

    # uniprot view: all species, from EBI uniprot-centric/.
    for src in "${DOWNLOAD_BASE}/uniprot-centric/${fmt}"/*-uniprot."${ebi_ext}".gz; do
        [ -e "$src" ] || continue
        stage_copy "$src" "$staged_dir" "$ebi_ext" "$out_ext"
    done

    # mod view: only where EBI ships a MOD variant, from the top-level dir.
    for src in "${DOWNLOAD_BASE}/${fmt}"/*-mod."${ebi_ext}".gz; do
        [ -e "$src" ] || continue
        stage_copy "$src" "$staged_dir" "$ebi_ext" "$out_ext"
    done
done

chown -R jenkins:jenkins "$STAGED_BASE"

# Quick visibility into what we're about to ship.
echo '=== Staged file counts ==='
for d in \
    "${STAGED_BASE}/annotations/gaf" \
    "${STAGED_BASE}/annotations/gpad" \
    "${STAGED_BASE}/annotations/gpi" \
    ; do
    printf '%-60s %5d\n' "$d" "$(find "$d" -type f | wc -l)"
done

# Build the canonical one-per-species GAF set for partitioning: the
# top-level GAF dir's new-scheme files (one variant per species). This
# deliberately excludes the uniprot-all duplicates and any stale
# pre-#2681 names.
mkdir -p "$CANON_GAF"
for src in "${DOWNLOAD_BASE}/gaf"/*-uniprot.gaf.gz "${DOWNLOAD_BASE}/gaf"/*-mod.gaf.gz; do
    [ -e "$src" ] || continue
    cp "$src" "${CANON_GAF}/"
done
chown -R jenkins:jenkins "$CANON_GAF"
echo "Canonical GAFs for partitioning: $(find "$CANON_GAF" -type f | wc -l)"

# Helper for retried rsync. Use rsync (not scp) because the per-dir
# file lists are large enough to risk ARG_MAX issues and rsync handles
# trailing-slash semantics cleanly.
rsync_retry() {
    local src="$1"
    local dst="$2"
    local _i
    for _i in 1 2 3; do
        if su jenkins -c "rsync -a -e 'ssh -o StrictHostKeyChecking=no -o IdentitiesOnly=true -o IdentityFile=/home/jenkins/.skyhook_key' '$src' '$dst'"; then
            return 0
        fi
        sleep 5
    done
    return 1
}

# Upload to skyhook in the new layout: three flat format dirs.
rsync_retry "${STAGED_BASE}/annotations/gaf/"   "${SKYHOOK_MAIN}/annotations/gaf/"
rsync_retry "${STAGED_BASE}/annotations/gpad/"  "${SKYHOOK_MAIN}/annotations/gpad/"
rsync_retry "${STAGED_BASE}/annotations/gpi/"   "${SKYHOOK_MAIN}/annotations/gpi/"

# Partition the canonical GAF set into union-* files for downstream
# indexing.
su jenkins -c "cd /workspace/go-site && python3 scripts/partition_and_merge_gaf.py '${CANON_GAF}' /tmp/merged union 10"
su jenkins -c 'ls -AlF /tmp/merged'

# Copy merged files to skyhook.
rsync_retry '/tmp/merged/' "${SKYHOOK_MAIN}/internal/union-gaf-partitions/"

# Push merged files to S3.
# Copy the s3cmd config to a writable location and make it readable
# for the jenkins user (the bind-mounted /secrets/s3cmd.cfg is
# read-only).
cp /secrets/s3cmd.cfg /tmp/s3cmd.cfg
chmod a+r /tmp/s3cmd.cfg
su jenkins -c 's3cmd -c /tmp/s3cmd.cfg --acl-public put /tmp/merged/union* s3://go-public/skyhook-geneontology-io/'

# Fix ownership so jenkins user can clean up.
chown -R "$JENKINS_UID:$JENKINS_GID" /workspace || true
