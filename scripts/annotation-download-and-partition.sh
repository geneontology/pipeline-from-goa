#!/bin/bash
#
# Annotation download, restructure, and partition stage.
#
# Syncs the GOEx annotation set (GAF, GPAD, GPI in both MOD-id-space
# and UniProt-id-space) from the GOEx mirror S3 bucket
# (s3://go-mirror/goex/current/), restructures into the
# pipeline-from-goa output layout, and partitions the canonical
# GAF set into the union-* files used for downstream indexing.
#
# Output layout on skyhook:
#   annotations/gaf/MNEMONIC-mod.gaf.gz       (~23 MOD-managed organisms)
#   annotations/gaf/MNEMONIC-uniprot.gaf.gz   (all 171 organisms)
#   annotations/gpad/MNEMONIC-mod.gpad.gz     (~23)
#   annotations/gpad/MNEMONIC-uniprot.gpad.gz (171)
#   annotations/gpi/MNEMONIC-mod.gpi.gz       (~23)
#   annotations/gpi/MNEMONIC-uniprot.gpi.gz   (171)
#   internal/union-gaf-partitions/union_*.gaf.gz  (10 partitions)
#
# The mod-centric filter is driven by goex.yaml: any organism whose
# `group` is not 'UniProt' gets a -mod file (in addition to its
# -uniprot file). The other ~148 UniProt-managed organisms only
# appear with a -uniprot file.
#
# EBI's `.gpa.gz` extension is normalized to `.gpad.gz` on landing.
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
#   /workspace -- Jenkins workspace (with go-site checked out for goex.yaml)
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
apt_install_retry python3 python3-pip python3-yaml openssh-client rsync s3cmd
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

# Read goex.yaml to get the MOD-centric mnemonic set: any organism
# whose `group` is not 'UniProt' is MOD-managed.
mod_mnemonics_file='/tmp/mod-mnemonics.txt'
su jenkins -c "python3 -c '
import yaml
d = yaml.safe_load(open(\"/workspace/go-site/metadata/goex.yaml\"))
codes = sorted({o[\"code_uniprot\"] for o in d[\"organisms\"] if o.get(\"group\") and o[\"group\"] != \"UniProt\"})
print(\"\n\".join(codes))
' > ${mod_mnemonics_file}"
mod_count=$(wc -l < "$mod_mnemonics_file")
echo "Identified ${mod_count} MOD-managed organisms from goex.yaml."

# Stage renamed files into a layout that mirrors the skyhook target:
# a flat dir per format under annotations/, with -mod or -uniprot
# suffix encoding the ID space. EBI's .gpa.gz is normalized to
# .gpad.gz on the way in.
mkdir -p \
    "${STAGED_BASE}/annotations/gaf" \
    "${STAGED_BASE}/annotations/gpad" \
    "${STAGED_BASE}/annotations/gpi"

# Map a downloaded file's MNEMONIC by stripping at the first underscore.
mnemonic_of() {
    basename "$1" | cut -d_ -f1
}

# Map EBI extension -> our extension. Only .gpa -> .gpad needs remapping.
normalized_ext() {
    case "$1" in
        gpa) echo 'gpad' ;;
        *)   echo "$1" ;;
    esac
}

# Stage uniprot-centric files (all 171 organisms, -uniprot suffix).
for entry in 'uniprot-centric/gaf:gaf' 'uniprot-centric/gpad:gpa' 'uniprot-centric/gpi:gpi'; do
    src_sub="${entry%%:*}"
    ext="${entry##*:}"
    out_ext=$(normalized_ext "$ext")
    staged_dir="${STAGED_BASE}/annotations/${out_ext}"
    for src in "${DOWNLOAD_BASE}/${src_sub}"/*."${ext}.gz"; do
        [ -e "$src" ] || continue
        mnem=$(mnemonic_of "$src")
        cp "$src" "${staged_dir}/${mnem}-uniprot.${out_ext}.gz"
    done
done

# Stage mod-centric files (filtered to MOD-managed organisms, -mod suffix).
for entry in 'gaf:gaf' 'gpad:gpa' 'gpi:gpi'; do
    src_sub="${entry%%:*}"
    ext="${entry##*:}"
    out_ext=$(normalized_ext "$ext")
    staged_dir="${STAGED_BASE}/annotations/${out_ext}"
    for src in "${DOWNLOAD_BASE}/${src_sub}"/*."${ext}.gz"; do
        [ -e "$src" ] || continue
        mnem=$(mnemonic_of "$src")
        if grep -qx "$mnem" "$mod_mnemonics_file"; then
            cp "$src" "${staged_dir}/${mnem}-mod.${out_ext}.gz"
        fi
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
# indexing. Source is the mod-centric (top-level) GAF set, matching
# the prior pipeline's behavior.
su jenkins -c 'python3 scripts/partition_and_merge_gaf.py /tmp/goex-download/gaf /tmp/merged union 10'
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
