#!/bin/bash
#
# Produce derived metadata files stage.
#
# Generates the metadata derivatives that the old pipeline's "Produce
# metadata" stage created but the new pipeline does not (it otherwise
# only rsyncs the source YAML from go-site). The files are written
# INTO the go-site-for-metadata/metadata checkout so the Jenkinsfile
# stage's existing rsync ships them to skyhook alongside the source
# YAML -- this script intentionally does NOT upload anything itself.
#
# Generated (release-independent transforms of go-site source YAML):
#   metadata/db-xrefs.json               (yaml2json -p db-xrefs.yaml)
#   metadata/db-xrefs.legacy             (db-xrefs-yaml2legacy.js)
#   metadata/GO.xrf_abbs                 (copy of db-xrefs.legacy)
#   metadata/eco-usage-constraints.json  (yaml2json -p)
#   metadata/groups.ttl                  (go-site yaml2turtle.sh + ROBOT)
#   metadata/users.ttl                   (go-site yaml2turtle.sh + ROBOT)
#
# The TTL forms come from go-site's own scripts/yaml2turtle.sh (the
# canonical tool), which assembles a JSON-LD doc (context + graph) and
# runs `robot convert`. We therefore install a pinned ROBOT + a
# ROBOT-compatible JRE. The intermediate .tmp.jsonld files the old
# inline approach left behind are NOT shipped (yaml2turtle.sh uses a
# throwaway temp); the .ttl products are equivalent.
#
# Tooling matches go-site's own declared deps: yamljs (provides the
# yaml2json binary), minimist + underscore (required by
# db-xrefs-yaml2legacy.js). They are installed globally so we do not
# pull the whole go-site dependency tree.
#
# Runs inside ubuntu:noble with /workspace mounted from the Jenkins
# workspace (with go-site checked out at go-site-for-metadata/).
#
# Required env vars:
#   JENKINS_UID, JENKINS_GID
#
# Required mounts:
#   /workspace -- Jenkins workspace (go-site checked out at
#                 go-site-for-metadata/)

set -euo pipefail

# Pinned ROBOT release used for the JSON-LD -> Turtle conversion.
ROBOT_VERSION='v1.9.10'

# WARNING: MEGAHACK -- the Jenkins host's docker network DNS is broken.
echo 'nameserver 8.8.8.8' > /etc/resolv.conf
echo 'search lbl.gov' >> /etc/resolv.conf

GO_SITE_DIR='/workspace/go-site-for-metadata'
META="${GO_SITE_DIR}/metadata"

# Helper for retried apt-get install. Same pattern as the other
# scripts -- archive.ubuntu.com is intermittently unreachable from
# this Jenkins host.
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

# Helper for retried npm global install (registry.npmjs.org can be
# intermittently slow/unreachable, same family of flakiness).
npm_install_retry() {
    local _i
    for _i in 1 2 3; do
        if npm install -g "$@"; then
            return 0
        fi
        echo "npm install attempt ${_i} failed; sleeping 15s before retry"
        sleep 15
    done
    return 1
}

# Helper for retried download.
wget_retry() {
    local url="$1"
    local dst="$2"
    local _i
    for _i in 1 2 3; do
        if wget --quiet --tries=3 -O "$dst" "$url"; then
            return 0
        fi
        echo "download attempt ${_i} for ${url} failed; sleeping 15s before retry"
        sleep 15
    done
    return 1
}

DEBIAN_FRONTEND=noninteractive apt-get update
# nodejs/npm for the yaml2json/legacy generation; openjdk-17 + wget for
# ROBOT (Turtle conversion).
apt_install_retry nodejs npm openjdk-17-jre-headless wget ca-certificates

# yamljs -> yaml2json binary; minimist + underscore -> required by
# db-xrefs-yaml2legacy.js. Versions float; these are pure-JS and
# stable.
npm_install_retry yamljs minimist underscore

NODE_GLOBAL_ROOT="$(npm root -g)"
YAML2JSON="$(npm prefix -g)/bin/yaml2json"

# Install pinned ROBOT (jar + launcher wrapper) onto PATH so go-site's
# yaml2turtle.sh can call `robot` directly.
wget_retry "https://github.com/ontodev/robot/releases/download/${ROBOT_VERSION}/robot.jar" /usr/local/bin/robot.jar
wget_retry "https://raw.githubusercontent.com/ontodev/robot/${ROBOT_VERSION}/bin/robot" /usr/local/bin/robot
chmod +x /usr/local/bin/robot

# Create jenkins user matching host UID/GID so the generated files are
# owned correctly for the host-side rsync that ships them.
groupadd -g "$JENKINS_GID" jenkins || true
useradd -u "$JENKINS_UID" -g "$JENKINS_GID" -m -s /bin/bash jenkins
chown -R jenkins:jenkins "$GO_SITE_DIR"

# Generate as the jenkins user. NODE_PATH points require() at the
# globally-installed modules. Redirections happen inside the jenkins
# shell so the outputs are written as jenkins.
su jenkins -c "NODE_PATH='${NODE_GLOBAL_ROOT}' '${YAML2JSON}' -p '${META}/db-xrefs.yaml' > '${META}/db-xrefs.json'"
su jenkins -c "cd '${GO_SITE_DIR}' && NODE_PATH='${NODE_GLOBAL_ROOT}' node scripts/db-xrefs-yaml2legacy.js -i metadata/db-xrefs.yaml > metadata/db-xrefs.legacy"
su jenkins -c "cp '${META}/db-xrefs.legacy' '${META}/GO.xrf_abbs'"
su jenkins -c "NODE_PATH='${NODE_GLOBAL_ROOT}' '${YAML2JSON}' -p '${META}/eco-usage-constraints.yaml' > '${META}/eco-usage-constraints.json'"

# TTL forms via go-site's canonical yaml2turtle.sh (yaml2json + robot,
# both on PATH from the global npm bin and /usr/local/bin).
su jenkins -c "cd '${GO_SITE_DIR}' && bash scripts/yaml2turtle.sh metadata/users-groups-context.yaml metadata/groups.yaml metadata/groups.ttl"
su jenkins -c "cd '${GO_SITE_DIR}' && bash scripts/yaml2turtle.sh metadata/users-groups-context.yaml metadata/users.yaml metadata/users.ttl"

echo '=== Generated metadata derivatives ==='
ls -AlF \
    "${META}/db-xrefs.json" \
    "${META}/db-xrefs.legacy" \
    "${META}/GO.xrf_abbs" \
    "${META}/eco-usage-constraints.json" \
    "${META}/groups.ttl" \
    "${META}/users.ttl"

# Defensive final ownership fix so the jenkins host user can clean up.
chown -R "$JENKINS_UID:$JENKINS_GID" /workspace || true
