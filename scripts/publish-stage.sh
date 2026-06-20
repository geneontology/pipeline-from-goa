#!/bin/bash
#
# Container wrapper that runs the Phase-5 publish tail as a Jenkins stage.
#
# *** Invoked ONLY by the gated-OFF 'Publish (DISABLED)' stage in the Jenkinsfile.
#     It runs publish-to-s3.sh with --execute (LIVE S3 + CloudFront mutations), so
#     it must never run until that stage's `when { expression { return false } }`
#     gate is deliberately edited. ***
#
# This is the "environmental adjustment" that lets the dual-use, hand-run
# scripts/publish-to-s3.sh run under Jenkins (see its header "DUAL-USE"): start as
# root to install deps and create a jenkins user with the host UID/GID (so the
# index.html files written into the bind-mounted tree get correct host ownership),
# then drop privileges and run the publish as that user.
#
# Required env:    JENKINS_UID, JENKINS_GID, TREE, TARGET_GO_SITE_BRANCH
# Required mounts: /workspace (with scripts/), /secrets/aws-push.json (creds JSON),
#                  and the LOCAL skyhook tree bind-mounted with TREE pointing at it.
#                  (publish-to-s3.sh excludes internal/ via the go-site --exclude
#                  flag now, so no parent mount or relocate is needed.)

set -euo pipefail

# WARNING: MEGAHACK -- the Jenkins host's docker network DNS is broken.
echo 'nameserver 8.8.8.8' > /etc/resolv.conf
echo 'search lbl.gov' >> /etc/resolv.conf

# Install deps (aws cli for the capper PUT + CloudFront; pystache/boto3/filechunkio
# for the go-site indexer/uploader). awscli via pip mirrors the pip-vs-apt handling
# elsewhere (issue #7).
DEBIAN_FRONTEND=noninteractive apt-get update
DEBIAN_FRONTEND=noninteractive apt-get -y install python3 python3-pip curl
pip3 install --break-system-packages pystache boto3 filechunkio awscli

# Create the jenkins user with the host UID/GID so files written into the
# bind-mounted tree (index.html) are owned correctly on the host.
groupadd -g "$JENKINS_GID" jenkins || true
useradd -u "$JENKINS_UID" -g "$JENKINS_GID" -m -s /bin/bash jenkins
chown -R jenkins:jenkins /workspace || true

# Drop privileges and run the real publish. --yes skips the typed-PUBLISH confirm
# (non-interactive); --execute makes it mutate.
su jenkins -c "bash /workspace/scripts/publish-to-s3.sh --tree '${TREE}' --creds /secrets/aws-push.json --gosite-ref '${TARGET_GO_SITE_BRANCH}' --execute --yes"

# Defensive final ownership fix.
chown -R "$JENKINS_UID:$JENKINS_GID" /workspace || true
