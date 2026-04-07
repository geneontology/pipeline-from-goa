#!/bin/bash
#
# Annotation download and partition stage.
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
#   /workspace -- Jenkins workspace (with go-site checked out)
#   /secrets/skyhook_key -- skyhook ssh key
#   /secrets/s3cmd.cfg -- s3cmd configuration

set -euo pipefail

# WARNING: MEGAHACK -- the Jenkins host's docker network DNS is broken.
echo 'nameserver 8.8.8.8' > /etc/resolv.conf
echo 'search lbl.gov' >> /etc/resolv.conf

# Install system dependencies.
DEBIAN_FRONTEND=noninteractive apt-get update
DEBIAN_FRONTEND=noninteractive apt-get -y install python3 python3-yaml openssh-client s3cmd

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

# Download annotations.
su jenkins -c 'ls -AlF'
su jenkins -c 'python3 scripts/download_goex_data.py /tmp/goex'

# Copy to skyhook for record.
su jenkins -c "scp -o StrictHostKeyChecking=no -o IdentitiesOnly=true -o IdentityFile=/home/jenkins/.skyhook_key /tmp/goex/*.gaf.gz skyhook@${SKYHOOK_MACHINE}:/home/skyhook/pipeline-from-goa/main/annotations/"

# Partition.
su jenkins -c 'ls -AlF /tmp/goex'
su jenkins -c 'python3 scripts/partition_and_merge_gaf.py /tmp/goex /tmp/merged union 10'
su jenkins -c 'ls -AlF /tmp/merged'

# Copy merged files to skyhook.
su jenkins -c "scp -o StrictHostKeyChecking=no -o IdentitiesOnly=true -o IdentityFile=/home/jenkins/.skyhook_key /tmp/merged/union* skyhook@${SKYHOOK_MACHINE}:/home/skyhook/pipeline-from-goa/main/TEMP/"

# Push merged files to S3.
# Copy the s3cmd config to a writable location and make it readable
# for the jenkins user (the bind-mounted /secrets/s3cmd.cfg is
# read-only).
cp /secrets/s3cmd.cfg /tmp/s3cmd.cfg
chmod a+r /tmp/s3cmd.cfg
su jenkins -c 's3cmd -c /tmp/s3cmd.cfg --acl-public put /tmp/merged/union* s3://go-public/skyhook-geneontology-io/'

# Fix ownership so jenkins user can clean up.
chown -R "$JENKINS_UID:$JENKINS_GID" /workspace || true
