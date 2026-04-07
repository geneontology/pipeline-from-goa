#!/bin/bash
#
# Produce derivatives stage: Solr index build, sanity check, upload,
# and stats.
#
# Runs inside the geneontology/golr-autoindex container. The
# container's run-indexer.sh starts Jetty/Solr in the background and
# runs the indexer; Solr stays running so subsequent stats queries
# can hit it.
#
# Required env vars:
#   JENKINS_UID, JENKINS_GID
#   SKYHOOK_MACHINE
#   START_DATE
#   BRANCH_NAME
#   SANITY_SOLR_DOC_COUNT_MIN, SANITY_SOLR_BIOENTITY_DOC_COUNT_MIN
#   GOLR_INPUT_ONTOLOGIES, GOLR_INPUT_GAFS, GOLR_INPUT_PANTHER_TREES
#   GOLR_SOLR_MEMORY, GOLR_LOADER_MEMORY
#
# Required mounts:
#   /workspace -- Jenkins workspace (with go-stats checked out)
#   /secrets/skyhook_key -- skyhook ssh key

set -euo pipefail

# WARNING: MEGAHACK -- the Jenkins host's docker network DNS is broken.
echo 'nameserver 8.8.8.8' > /etc/resolv.conf
echo 'search lbl.gov' >> /etc/resolv.conf

# WARNING: MEGAHACK
# See attempts around: https://github.com/geneontology/pipeline/issues/407#issuecomment-2513461418
# Remove --solr-optimize from the indexer.
sed 's/--solr-optimize//' /tmp/run-indexer.sh > /tmp/run-indexer-no-opt.sh

# Bump jetty memory and timeout.
sed 's/Xmx3g/Xmx16g -Djetty.timeout=300000/' /etc/default/jetty9 > /tmp/jetty9.tmp
mv /tmp/jetty9.tmp /etc/default/jetty9
sed 's/http.timeout=300000/http.timeout=3000000/' /etc/jetty9/start.ini > /tmp/start.ini.tmp
mv /tmp/start.ini.tmp /etc/jetty9/start.ini

# Install pip dependencies as root (before dropping privileges)
# since they go into system site-packages.
pip3 install --force-reinstall requests==2.19.1
pip3 install --force-reinstall networkx==2.2

# Create jenkins user matching host UID/GID.
groupadd -g "$JENKINS_GID" jenkins || true
useradd -u "$JENKINS_UID" -g "$JENKINS_GID" -m -s /bin/bash jenkins

# Set up skyhook key for jenkins user.
cp /secrets/skyhook_key /home/jenkins/.skyhook_key
chown jenkins:jenkins /home/jenkins/.skyhook_key
chmod 0600 /home/jenkins/.skyhook_key

# Build the Solr index. Solr/Jetty is started in the background by
# this script and stays running for subsequent queries.
bash /tmp/run-indexer-no-opt.sh

# After indexer completes, fix ownership for jenkins user.
chown -R jenkins:jenkins /workspace
chmod -R a+r /srv/solr/data

# Sanity check on release branch only.
if [[ "${BRANCH_NAME:-}" == "release" ]]; then
    echo "SANITY_SOLR_DOC_COUNT_MIN: $SANITY_SOLR_DOC_COUNT_MIN"
    docs=$(curl -s 'http://localhost:8080/solr/select?q=*:*&rows=0&wt=json' | grep -oh '"numFound":[[:digit:]]*' | grep -oh '[[:digit:]]*')
    if [[ "$SANITY_SOLR_DOC_COUNT_MIN" -gt "$docs" ]]; then
        echo "Doc count $docs below minimum $SANITY_SOLR_DOC_COUNT_MIN"
        exit 1
    fi
    echo "Doc count OK: $docs"

    echo "SANITY_SOLR_BIOENTITY_DOC_COUNT_MIN: $SANITY_SOLR_BIOENTITY_DOC_COUNT_MIN"
    bio=$(curl -s 'http://localhost:8080/solr/select?q=*:*&rows=0&wt=json&fq=document_category:bioentity' | grep -oh '"numFound":[[:digit:]]*' | grep -oh '[[:digit:]]*')
    if [[ "$SANITY_SOLR_BIOENTITY_DOC_COUNT_MIN" -gt "$bio" ]]; then
        echo "Bioentity count $bio below minimum $SANITY_SOLR_BIOENTITY_DOC_COUNT_MIN"
        exit 1
    fi
    echo "Bioentity count OK: $bio"
fi

# Tar up the Solr index.
su jenkins -c 'tar --use-compress-program=pigz -cvf /tmp/golr-index-contents.tgz -C /srv/solr/data/index .'

# Helper: retry an scp upload up to 3 times.
scp_retry() {
    local src="$1"
    local dst="$2"
    local _i
    for _i in 1 2 3; do
        if su jenkins -c "scp -o StrictHostKeyChecking=no -o IdentitiesOnly=true -o IdentityFile=/home/jenkins/.skyhook_key $src $dst"; then
            return 0
        fi
        sleep 5
    done
    return 1
}

# Helper: retry an arbitrary command (run as jenkins) up to 3 times.
run_retry() {
    local cmd="$1"
    local _i
    for _i in 1 2 3; do
        if su jenkins -c "$cmd"; then
            return 0
        fi
        sleep 5
    done
    return 1
}

# Upload Solr index and timestamp log to skyhook.
scp_retry "/tmp/golr-index-contents.tgz" "skyhook@${SKYHOOK_MACHINE}:/home/skyhook/pipeline-from-goa/main/products/solr/"
scp_retry "/tmp/golr_timestamp.log"      "skyhook@${SKYHOOK_MACHINE}:/home/skyhook/pipeline-from-goa/main/products/solr/"

# Solr should still be running in the background here from indexing
# -- create stats products from running GOlr using go-stats.
chown -R jenkins:jenkins /workspace/go-stats
mkdir -p /tmp/stats
chown jenkins:jenkins /tmp/stats
su jenkins -c 'cp /workspace/go-stats/libraries/go-stats/*.py /tmp'

# Verify Solr is still responding.
echo "Check that results have been stored properly"
su jenkins -c 'curl "http://localhost:8080/solr/select?q=*:*&rows=0"'
echo "End of results"

run_retry "python3 /tmp/go_reports.py -g http://localhost:8080/solr/ -s http://current.geneontology.org/release_stats/go-stats.json -n http://current.geneontology.org/release_stats/go-stats-no-pb.json -c http://snapshot.geneontology.org/ontology/go.obo -p http://current.geneontology.org/ontology/go.obo -r http://current.geneontology.org/release_stats/go-references.tsv -o /tmp/stats/ -d ${START_DATE}"
run_retry "cd /workspace/go-stats && wget -N http://current.geneontology.org/release_stats/aggregated-go-stats-summaries.json"

# Roll the stats forward.
su jenkins -c 'python3 /tmp/aggregate-stats.py -a /workspace/go-stats/aggregated-go-stats-summaries.json -b /tmp/stats/go-stats-summary.json -o /tmp/stats/aggregated-go-stats-summaries.json'

# Upload stats files to skyhook.
for f in /tmp/stats/*; do
    scp_retry "$f" "skyhook@${SKYHOOK_MACHINE}:/home/skyhook/pipeline-from-goa/main/release_stats/"
done

# See if sleeping a little gives the tmpfs a little time to catch up.
sleep 120

# Fix ownership so jenkins user can clean up.
chown -R "$JENKINS_UID:$JENKINS_GID" /workspace || true
