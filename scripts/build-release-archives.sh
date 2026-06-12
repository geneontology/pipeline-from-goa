#!/bin/bash
#
# Build the release archive tarballs from the skyhook main tree.
#
# Part of the BUILD half (build-then-publish; see docs/release-runbook.md
# Phase 4 + the "internal/ is staging" callout). It produces two archives in the
# internal/ staging area on skyhook; the PUBLISH half later streams them to
# Zenodo via scripts/zenodo-archive-upload.py.
#
# Partition (confirmed):
#   internal/release-archives/go-release-archive.tgz   -- "main" / reproducible
#       = annotations go-cams metadata ontology release_stats reports
#       (Zenodo concept 1205166, "Gene Ontology Data Archive")
#   internal/release-archives/go-release-products.tgz  -- "products" / secondary
#       = products/   (Zenodo concept 10946933, "Secondary Products")
#
# internal/ is NEVER archived (it is staging) -- excluded simply by tarring only
# the named top-level dirs. The tarballs themselves land IN internal/, so they
# are not part of the served tree either.
#
# The full tree already lives on skyhook (local disk there), so we tar IN PLACE
# on skyhook over ssh -- no multi-GB pull into the container.
#
# Required env vars: JENKINS_UID, JENKINS_GID, SKYHOOK_MACHINE
# Required mounts:   /secrets/skyhook_key

set -euo pipefail

# WARNING: MEGAHACK -- the Jenkins host's docker network DNS is broken.
echo 'nameserver 8.8.8.8' > /etc/resolv.conf
echo 'search lbl.gov' >> /etc/resolv.conf

DEBIAN_FRONTEND=noninteractive apt-get update
DEBIAN_FRONTEND=noninteractive apt-get -y install openssh-client

# Create jenkins user matching host UID/GID (consistent with sibling stages).
groupadd -g "$JENKINS_GID" jenkins || true
useradd -u "$JENKINS_UID" -g "$JENKINS_GID" -m -s /bin/bash jenkins

# Skyhook key under the jenkins home, mode 0600 (ssh requires it).
cp /secrets/skyhook_key /home/jenkins/.skyhook_key
chown jenkins:jenkins /home/jenkins/.skyhook_key
chmod 0600 /home/jenkins/.skyhook_key

# The tar work runs ON skyhook (where the tree is). Pipe a script to `bash -s`
# rather than inlining a multi-layer-quoted command. The heredoc is quoted, so
# it is expanded by skyhook's shell, not here.
cat > /tmp/remote-build-archives.sh <<'REMOTE'
set -euo pipefail
cd /home/skyhook/pipeline-from-goa/main
mkdir -p internal/release-archives

# pigz if available (parallel -- much faster on ~10 GiB), else gzip.
COMP="$(command -v pigz || command -v gzip)"
echo "Compressor: ${COMP}"

echo "Building go-release-archive.tgz (reproducible main subset)..."
tar --use-compress-program="${COMP}" \
    -cf internal/release-archives/go-release-archive.tgz \
    annotations go-cams metadata ontology release_stats reports

echo "Building go-release-products.tgz (products/)..."
tar --use-compress-program="${COMP}" \
    -cf internal/release-archives/go-release-products.tgz \
    products

echo "Release archives built:"
ls -lh internal/release-archives/*.tgz
REMOTE
chmod a+r /tmp/remote-build-archives.sh

# Drop privileges for the ssh work (the key lives under the jenkins home).
SSH_OPTS="-o StrictHostKeyChecking=no -o IdentitiesOnly=true -o IdentityFile=/home/jenkins/.skyhook_key"
su jenkins -c "cat /tmp/remote-build-archives.sh | ssh ${SSH_OPTS} skyhook@${SKYHOOK_MACHINE} 'bash -s'"
