#!/bin/bash
#
# Internal all-GO-CAM products stage.
#
# Produces the unfiltered "all" GO-CAM products for internal use:
#   - all-go-cams-json/   (gocam-py JSON, all models)
#   - all-go-cams-yaml/   (gocam-py YAML, all models)
#   - all-go-cams-gpad/   (unified + per-model GPADs)
#
# Input is TTL models from S3 (Noctua crontab export), NOT the
# Minerva JSON tarball used by the "true" GO-CAM pipeline.
#
# Runs inside ubuntu:noble container with /workspace mounted from
# Jenkins workspace and /secrets containing credentials.
#
# Required env vars:
#   JENKINS_UID, JENKINS_GID
#   SKYHOOK_MACHINE
#   AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY
#   TARGET_GO_SITE_BRANCH
#   TARGET_MINERVA_BRANCH
#
# Required mounts:
#   /workspace -- Jenkins workspace (with gocam-py checked out)
#   /secrets/skyhook_key -- skyhook ssh key

set -euo pipefail

# WARNING: MEGAHACK -- the Jenkins host's docker network DNS is broken.
echo 'nameserver 8.8.8.8' > /etc/resolv.conf
echo 'search lbl.gov' >> /etc/resolv.conf

###
### Phase 1: Setup
###

DEBIAN_FRONTEND=noninteractive apt-get update
DEBIAN_FRONTEND=noninteractive apt-get -y install \
    openjdk-21-jdk-headless maven \
    python3 python3-pip python3-venv python3-yaml \
    git openssh-client wget perl pigz

# Install uv and awscli (not in Ubuntu apt repos).
pip3 install --break-system-packages uv
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

# Working directory on tmpfs.
WORK=/tmp/all-gocam-work
su jenkins -c "mkdir -p $WORK"

###
### Phase 2: Build minerva-cli
###

cd /workspace/minerva
chown -R jenkins:jenkins .
su jenkins -c './build-cli.sh'

MINERVA_CLI="/workspace/minerva/minerva-cli/bin/minerva-cli.sh"
chmod +x "$MINERVA_CLI"

###
### Phase 3: Pull TTL models from S3
###

su jenkins -c "mkdir -p $WORK/models"
su jenkins -c "aws s3 cp s3://go-data-product-live-go-cam/ttl/ $WORK/models/ --recursive --exclude '*' --include '*.ttl'"

###
### Phase 4: GPAD generation (minerva-cli)
###

# Ontology from our own pipeline output on skyhook.
GO_LEGO_OWL="https://skyhook.geneontology.io/pipeline-from-goa/main/ontology/extensions/go-lego.owl"

export MINERVA_CLI_MEMORY=128G

# Import TTL models into a local Blazegraph journal.
su jenkins -c "$MINERVA_CLI --import-owl-models -f $WORK/models -j $WORK/blazegraph.jnl"

# Convert GO-CAM to GPAD via SPARQL.
su jenkins -c "mkdir -p $WORK/legacy/gpad"
su jenkins -c "$MINERVA_CLI --lego-to-gpad-sparql --ontology $GO_LEGO_OWL --ontojournal $WORK/ontojournal.jnl -i $WORK/blazegraph.jnl --gpad-output $WORK/legacy/gpad"

# Unify into single GPAD (production models only).
su jenkins -c "wget -q -O $WORK/unify-gpads.pl https://raw.githubusercontent.com/geneontology/go-site/${TARGET_GO_SITE_BRANCH}/scripts/unify-gpads.pl"
su jenkins -c "perl $WORK/unify-gpads.pl $WORK/legacy/gpad > $WORK/unified.gpad"
su jenkins -c "gzip $WORK/unified.gpad"

###
### Phase 5: JSON dump (minerva-cli)
###

# Download the reacto-neo journal (produced by issue-35-neo-test
# branch of geneontology/pipeline and published to skyhook).
su jenkins -c "wget -q -O $WORK/blazegraph-go-lego-reacto-neo.jnl.gz http://skyhook.berkeleybop.org/blazegraph-go-lego-reacto-neo.jnl.gz"
su jenkins -c "gunzip $WORK/blazegraph-go-lego-reacto-neo.jnl.gz"

su jenkins -c "mkdir -p $WORK/jsonout"
su jenkins -c "$MINERVA_CLI --dump-owl-json --journal $WORK/blazegraph.jnl --ontojournal $WORK/blazegraph-go-lego-reacto-neo.jnl --folder $WORK/jsonout"

###
### Phase 6: gocam-py conversion (JSON + YAML)
###

# Install gocam-py.
cd /workspace/gocam-py
chown -R jenkins:jenkins .
su jenkins -c 'git config --global --add safe.directory /workspace/gocam-py'
su jenkins -c 'uv sync --all-extras'

# Convert Minerva JSON to gocam-py JSON.
su jenkins -c "mkdir -p $WORK/gocam-json"
su jenkins -c "uv run python pipeline/convert_minerva_models_to_gocam_models.py --input-dir $WORK/jsonout --output-dir $WORK/gocam-json --verbose"

# Convert gocam-py JSON to YAML via Model class.
# The YAML must come from gocam-py's Model serialization, not a
# mechanical JSON→YAML translation.
su jenkins -c "mkdir -p $WORK/gocam-yaml"
su jenkins -c "uv run python -c \"
import json, yaml, pathlib, sys, logging
from gocam.datamodel import Model

logging.basicConfig(level=logging.WARNING)
in_dir = pathlib.Path('$WORK/gocam-json')
out_dir = pathlib.Path('$WORK/gocam-yaml')
ok = 0
fail = 0
for f in sorted(in_dir.glob('*.json')):
    try:
        m = Model.model_validate_json(f.read_text())
        (out_dir / f.with_suffix('.yaml').name).write_text(
            yaml.dump(m.model_dump(exclude_none=True), sort_keys=False, allow_unicode=True))
        ok += 1
    except Exception as e:
        logging.warning('Failed to convert %s: %s', f.name, e)
        fail += 1
print(f'YAML conversion: {ok} ok, {fail} failed', file=sys.stderr)
\""

###
### Phase 7: Upload to skyhook
###

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

SKYHOOK_BASE="skyhook@${SKYHOOK_MACHINE}:/home/skyhook/pipeline-from-goa/main/internal"

scp_retry "-r" "$WORK/gocam-json/*"       "${SKYHOOK_BASE}/all-go-cams-json/"
scp_retry "-r" "$WORK/gocam-yaml/*"       "${SKYHOOK_BASE}/all-go-cams-yaml/"
scp_retry ""   "$WORK/unified.gpad.gz"    "${SKYHOOK_BASE}/all-go-cams-gpad/"
scp_retry "-r" "$WORK/legacy/gpad/*"      "${SKYHOOK_BASE}/all-go-cams-gpad/model/"

# Fix ownership so jenkins user can clean up.
chown -R "$JENKINS_UID:$JENKINS_GID" /workspace || true
