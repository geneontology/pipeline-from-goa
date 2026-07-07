#!/bin/bash
#
# Publish the PANTHER arbre.tgz to go-public S3 over plain HTTP so the
# golr indexer can read it. arbre.tgz is gzip, and the golr consumer
# (OWLTools) cannot read skyhook-HTTPS gzip -- EOFException / URL
# mangling, owlcollab/owltools#171 (geneontology/pipeline-from-goa#2) --
# exactly like the union GAFs. So, like them, it is served from
# go-public over plain HTTP and GOLR_INPUT_PANTHER_TREES points there.
#
# Mirrors the s3cmd push in annotation-download-and-partition.sh.
#
# Runs as root in an ephemeral ubuntu:noble container. Read-only with
# respect to /workspace (it only reads arbre.tgz), so there is no need
# to create a jenkins user or chown anything.
#
# Required mounts:
#   /workspace          -- Jenkins workspace (arbre.tgz at go-site/arbre.tgz)
#   /secrets/s3cmd.cfg  -- s3cmd configuration (read-only)

set -euo pipefail

# WARNING: MEGAHACK -- the Jenkins host's docker network DNS is broken.
echo 'nameserver 8.8.8.8' > /etc/resolv.conf
echo 'search lbl.gov' >> /etc/resolv.conf

# Install s3cmd (retry: transient apt mirror failures).
for _i in 1 2 3; do
    if apt-get update && apt-get install -y --no-install-recommends s3cmd ca-certificates; then
        break
    fi
    sleep 5
done

# Copy the s3cmd config somewhere writable/readable (the bind mount is ro).
cp /secrets/s3cmd.cfg /tmp/s3cmd.cfg
chmod 0600 /tmp/s3cmd.cfg

# Push to go-public with a public-read ACL, mirroring the union-GAF push.
s3cmd -c /tmp/s3cmd.cfg --acl-public put /workspace/go-site/arbre.tgz s3://go-public/skyhook-geneontology-io/
