pipeline {
    agent any
    // In additional to manual runs, trigger somewhere at midnight to
    // give us the max time in a day to get things right.
    triggers {
	// Master never runs--Feb 31st.
	cron('0 0 31 2 *')
	// Nightly @12am, for "snapshot", skip "release" night.
	//cron('0 0 2-31/2 * *')
	// First of the month @12am, for "release" (also "current").
	//cron('0 0 1 * *')
    }
    environment {

	///
	/// Internal run variables.
	///

	// The branch of geneontology/go-site to use.
	TARGET_GO_SITE_BRANCH = 'master'
	// The branch of geneontology/go-stats to use.
	TARGET_GO_STATS_BRANCH = 'master'
	// The branch of go-ontology to use.
	TARGET_GO_ONTOLOGY_BRANCH = 'master'
	// The branch of minerva to use.
	TARGET_MINERVA_BRANCH = 'master'
	// The branch of ROBOT to use in one silly section.
	// Necessary due to java version jump.
	// https://github.com/ontodev/robot/issues/997
	TARGET_ROBOT_BRANCH = 'master'
	// The branch of noctua-models to use.
	TARGET_NOCTUA_MODELS_BRANCH = 'master'
	// The branch of gocam-py to use.
	TARGET_GOCAM_PY_BRANCH = 'main'
	// URL to the Minerva JSON models tarball (input for gocam-py).
	// This tarball is produced by an earlier pipeline step and made
	// available at a URL (e.g. on S3 or skyhook HTTP).
	// WARNING: TBD -- set to actual URL once upstream pipeline is determined.
	MINERVA_JSON_TARBALL_URL = 'https://current.geneontology.org/products/json/noctua-models-json.tgz'
	// The people to call when things go bad. It is a comma-space
	// "separated" string.
	// TARGET_ADMIN_EMAILS = 'sjcarbon@lbl.gov,debert@usc.edu,smoxon@lbl.gov'
	// TARGET_SUCCESS_EMAILS = 'sjcarbon@lbl.gov,debert@usc.edu,suzia@stanford.edu,smoxon@lbl.gov'
	// TARGET_RELEASE_HOLD_EMAILS = 'sjcarbon@lbl.gov,debert@usc.edu,pascale.gaudet@sib.swiss,pgaudet1@gmail.com,smoxon@lbl.gov'
	TARGET_ADMIN_EMAILS = 'sjcarbon@lbl.gov'
	TARGET_SUCCESS_EMAILS = 'sjcarbon@lbl.gov'
	TARGET_RELEASE_HOLD_EMAILS = 'sjcarbon@lbl.gov'
	// The file bucket(/folder) combination to use.
	//TARGET_BUCKET = 'go-data-product-snapshot'
	TARGET_BUCKET = 'go-data-TBD'
	// The URL prefix to use when creating site indices.
	//TARGET_INDEXER_PREFIX = 'http://snapshot.geneontology.org'
	TARGET_INDEXER_PREFIX = 'null'
	// This variable should typically be 'TRUE', which will cause
	// some additional basic checks to be made. There are some
	// very exotic cases where these check may need to be skipped
	// for a run, in that case this variable is set to 'FALSE'.
	WE_ARE_BEING_SAFE_P = 'TRUE'
	// Sanity check for solr index being built--overall min count.
	// See https://github.com/geneontology/pipeline/issues/315 .
	// Only used on release attempts (as it saves QC time and
	// getting the number for all branches would be a trick).
	SANITY_SOLR_DOC_COUNT_MIN = 11000000
	SANITY_SOLR_BIOENTITY_DOC_COUNT_MIN = 1400000
	// Control make to get through our loads faster if
	// possible. Assuming we're cpu bound for some of these...
	// wok has 48 "processors" over 12 "cores", so I have no idea;
	// let's go with conservative and see if we get an
	// improvement.
	MAKECMD = 'make --jobs --max-load 12.0'
	//MAKECMD = 'make'

	///
	/// PANTHER/PAINT metadata.
	///

	PANTHER_VERSION = '19.0'

	///
	/// Application tokens.
	///

	// The Zenodo concept ID to use for releases (and occasionally
	// master testing).
	//ZENODO_ARCHIVE_CONCEPT = '425666'
	ZENODO_ARCHIVE_CONCEPT = 'null'
	// Distribution ID for the AWS CloudFront for this branch,
	// used soley for invalidations. Versioned release does not
	// need this as it is always a new location and the index
	// upload already has an invalidation on it. For current,
	// snapshot, and experimental.
	//AWS_CLOUDFRONT_DISTRIBUTION_ID = 'E3UPPWY0HYLLL2'
	//AWS_CLOUDFRONT_RELEASE_DISTRIBUTION_ID = 'E2HF1DWYYDLTQP'
	AWS_CLOUDFRONT_DISTRIBUTION_ID = 'null'
	AWS_CLOUDFRONT_RELEASE_DISTRIBUTION_ID = 'null'

	///
	/// Ontobio Validation
	///
	// WARNING: This will need to be changed.
	VALIDATION_ONTOLOGY_URL="http://snapshot.geneontology.org/ontology/go.json"

	///
	/// Minerva input.
	///

	// Minerva operating profile.
	// WARNING: This will need to be changed.
	MINERVA_INPUT_ONTOLOGIES = [
	    "http://snapshot.geneontology.org/ontology/extensions/go-lego.owl"
	].join(" ")

	///
	/// GOlr/AmiGO input.
	///

	// GOlr load profile.
	GOLR_SOLR_MEMORY = "256G"
	GOLR_LOADER_MEMORY = "256G"
	GOLR_INPUT_ONTOLOGIES = [
	    "http://snapshot.geneontology.org/ontology/extensions/go-amigo.owl"
	].join(" ")
	// WARNING: hard-coded for the moment.
	GOLR_INPUT_GAFS = [
	    // "https://skyhook.geneontology.io/pipeline-from-goa/main/union_1.gaf.gz",
	    // "https://skyhook.geneontology.io/pipeline-from-goa/main/union_2.gaf.gz",
	    // "https://skyhook.geneontology.io/pipeline-from-goa/main/union_3.gaf.gz",
	    // "https://skyhook.geneontology.io/pipeline-from-goa/main/union_4.gaf.gz",
	    // "https://skyhook.geneontology.io/pipeline-from-goa/main/union_5.gaf.gz",
	    // "https://skyhook.geneontology.io/pipeline-from-goa/main/union_6.gaf.gz",
	    // "https://skyhook.geneontology.io/pipeline-from-goa/main/union_7.gaf.gz",
	    // "https://skyhook.geneontology.io/pipeline-from-goa/main/union_8.gaf.gz",
	    // "https://skyhook.geneontology.io/pipeline-from-goa/main/union_9.gaf.gz",
	    // "https://skyhook.geneontology.io/pipeline-from-goa/main/union_10.gaf.gz"
	    'http://go-public.s3.us-east-1.amazonaws.com/skyhook-geneontology-io/union_1.gaf.gz',
	    'http://go-public.s3.us-east-1.amazonaws.com/skyhook-geneontology-io/union_2.gaf.gz',
	    'http://go-public.s3.us-east-1.amazonaws.com/skyhook-geneontology-io/union_3.gaf.gz',
	    'http://go-public.s3.us-east-1.amazonaws.com/skyhook-geneontology-io/union_4.gaf.gz',
	    'http://go-public.s3.us-east-1.amazonaws.com/skyhook-geneontology-io/union_5.gaf.gz',
	    'http://go-public.s3.us-east-1.amazonaws.com/skyhook-geneontology-io/union_6.gaf.gz',
	    'http://go-public.s3.us-east-1.amazonaws.com/skyhook-geneontology-io/union_7.gaf.gz',
	    'http://go-public.s3.us-east-1.amazonaws.com/skyhook-geneontology-io/union_8.gaf.gz',
	    'http://go-public.s3.us-east-1.amazonaws.com/skyhook-geneontology-io/union_9.gaf.gz',
	    'http://go-public.s3.us-east-1.amazonaws.com/skyhook-geneontology-io/union_10.gaf.gz'
	].join(" ")
	GOLR_INPUT_PANTHER_TREES = [
	    "http://snapshot.geneontology.org/products/panther/arbre.tgz"
	].join(" ")

	///
	/// Groups to run and tests to avoid running during the current
	/// mega-make.
	///

	// The gorule tag is used to identify which rules to suppress
	// reports from during the megastep and during templating the
	// reports after the megastep. The tags are currently
	// respected at two times in the pipeline: the gorules report
	// take the flag as a CLI argument, supressing it; ontobio
	// takes it during the same stage as the JSON
	// generation/parsing step, to supress the .md output. At this
	// time, this variable can be either nothing or empty string
	// for no rule suppression (default behavior everything), or a
	// single value (practically speaking pretty much always
	// "silent")
	GORULE_TAGS_TO_SUPPRESS="silent"

	// Optional. Groups to run.
	//RESOURCE_GROUPS=""
	// Optional. Datasets to skip within the resources that we
	// will run (defined in the line above).
	//DATASET_EXCLUDES=""
	// Optional. This acts as an override, /if/ it's grabbed (as
	// defined above).
	//GOA_UNIPROT_ALL_URL=""

    }
    options{
	timestamps()
	buildDiscarder(logRotator(numToKeepStr: '14'))
    }
    stages {
	// Very first: pause for a few minutes to give a chance to
	// cancel and clean the workspace before use.
	stage('Ready and clean') {
	    steps {

		// Check to make sure we have coherent metadata so we
		// don't clobber good products.
		watchdog();

		// Give us a minute to cancel if we want.
//		sleep time: 1, unit: 'MINUTES'
		cleanWs deleteDirs: true, disableDeferredWipeout: true
	    }
	}

	stage('Initialize') {
	    steps {

		///
		/// Automatic run variables.
		///

		// Pin dates and day to beginning of run.
		script {
		    env.START_DATE = sh (
			script: 'date +%Y-%m-%d',
			returnStdout: true
		    ).trim()

		    env.START_DAY = sh (
			script: 'date +%A',
			returnStdout: true
		    ).trim()

		    // Capture host jenkins UID/GID for Docker
		    // privilege drop.
		    env.JENKINS_UID = sh(
			script: 'id -u',
			returnStdout: true
		    ).trim()
		    env.JENKINS_GID = sh(
			script: 'id -g',
			returnStdout: true
		    ).trim()
		}

		// Reset base.
		initialize();

		sh 'env > env.txt'
		sh 'echo $BRANCH_NAME > branch.txt'
		sh 'echo "$BRANCH_NAME"'
		sh 'echo "$JOB_NAME"'
		sh 'cat env.txt'
		sh 'cat branch.txt'
		sh 'echo $START_DAY > dow.txt'
		sh 'echo "$START_DAY"'
		sh 'echo $START_DATE > date.txt'
		sh 'echo "$START_DATE"'
	    }
	}

	stage('Ontology download') {
	    steps {
		script {
		    try {
			// Get the ontology.
			sh 'wget --wait 5 --recursive --no-parent --no-host-directories --execute robots=off --span-hosts=off --user-agent="GOC Pipeline" --debug --reject="index.html*,*.tmp,README*,*.html,*.htm,robots.txt,Makefile*,*wikipedia*" https://ftp.ebi.ac.uk/pub/contrib/goa/goex/current/ontology/'
		    } catch (exception) {
			echo "There has been a recursion/download failure; accepting that this was likely fine, but check contents."
		    }

		    // Copy to skyhook for record.
		    withCredentials([file(credentialsId: 'skyhook-private-key', variable: 'SKYHOOK_IDENTITY'), string(credentialsId: 'skyhook-machine-private', variable: 'SKYHOOK_MACHINE')]) {
			sh 'scp -r -o StrictHostKeyChecking=no -o IdentitiesOnly=true -o IdentityFile=$SKYHOOK_IDENTITY ./pub/contrib/goa/goex/current/ontology/* skyhook@$SKYHOOK_MACHINE:/home/skyhook/pipeline-from-goa/main/ontology/'
		    }
		}
	    }
	}

	stage('Annotation download and partition') {
	    steps {
		script {
		    // Clone go-site on host (Jenkins git step).
		    dir('./go-site') {
			git branch: TARGET_GO_SITE_BRANCH, url: 'https://github.com/geneontology/go-site.git'
		    }

		    // Run all container work via raw docker run,
		    // bypassing the unmaintained docker-workflow
		    // plugin to avoid container teardown failures
		    // (JENKINS-73567).
		    withCredentials([
			file(credentialsId: 'skyhook-private-key', variable: 'SKYHOOK_IDENTITY'),
			string(credentialsId: 'skyhook-machine-private', variable: 'SKYHOOK_MACHINE'),
			file(credentialsId: 's3cmd_go_push_configuration', variable: 'S3CMD_JSON'),
			string(credentialsId: 'aws_go_access_key', variable: 'AWS_ACCESS_KEY_ID'),
			string(credentialsId: 'aws_go_secret_key', variable: 'AWS_SECRET_ACCESS_KEY')
		    ]) {
			sh """
			    docker run --rm \
			      --init \
			      --mount type=tmpfs,destination=/tmp \
			      -u root:root \
			      -v "\$WORKSPACE":/workspace \
			      -v "\$SKYHOOK_IDENTITY":/secrets/skyhook_key:ro \
			      -v "\$S3CMD_JSON":/secrets/s3cmd.cfg:ro \
			      -e SKYHOOK_MACHINE="\$SKYHOOK_MACHINE" \
			      -e AWS_ACCESS_KEY_ID="\$AWS_ACCESS_KEY_ID" \
			      -e AWS_SECRET_ACCESS_KEY="\$AWS_SECRET_ACCESS_KEY" \
			      -e JENKINS_UID="\$JENKINS_UID" \
			      -e JENKINS_GID="\$JENKINS_GID" \
			      ubuntu:noble bash -c "
				# WARNING: MEGAHACK
				echo 'nameserver 8.8.8.8' > /etc/resolv.conf
				echo 'search lbl.gov' >> /etc/resolv.conf

				DEBIAN_FRONTEND=noninteractive apt-get update
				DEBIAN_FRONTEND=noninteractive apt-get -y install python3 python3-yaml openssh-client s3cmd

				# Create jenkins user matching host UID/GID.
				groupadd -g \\\$JENKINS_GID jenkins || true
				useradd -u \\\$JENKINS_UID -g \\\$JENKINS_GID -m -s /bin/bash jenkins
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
				su jenkins -c 'scp -o StrictHostKeyChecking=no -o IdentitiesOnly=true -o IdentityFile=/home/jenkins/.skyhook_key /tmp/goex/*.gaf.gz skyhook@'\\\$SKYHOOK_MACHINE':/home/skyhook/pipeline-from-goa/main/annotations/'

				# Partition.
				su jenkins -c 'ls -AlF /tmp/goex'
				su jenkins -c 'python3 scripts/partition_and_merge_gaf.py /tmp/goex /tmp/merged union 10'
				su jenkins -c 'ls -AlF /tmp/merged'

				# Copy merged files to skyhook.
				su jenkins -c 'scp -o StrictHostKeyChecking=no -o IdentitiesOnly=true -o IdentityFile=/home/jenkins/.skyhook_key /tmp/merged/union* skyhook@'\\\$SKYHOOK_MACHINE':/home/skyhook/pipeline-from-goa/main/TEMP/'

				# Push merged files to S3.
				chmod a+r /secrets/s3cmd.cfg
				su jenkins -c 's3cmd -c /secrets/s3cmd.cfg --acl-public put /tmp/merged/union* s3://go-public/skyhook-geneontology-io/'

				# Fix ownership so jenkins user can clean up.
				chown -R \\\$JENKINS_UID:\\\$JENKINS_GID /workspace || true
			      "
			"""
		    }
		}
	    }
	}

	// stage('TTL pathways package') {
	//     steps {
	// 	script {

	// 	    // Setup repo.
	// 	    dir('./sparql-for-pathway-go-cams') {
	// 		// Remember that git lays out into CWD.
	// 		git branch: 'main', url: 'https://github.com/geneontology/sparql-for-pathway-go-cams.git'

	// 		// Get production blazegraph.
	// 		sh 'rm -f blazegraph-production.jnl || true'
	// 		sh 'rm -f blazegraph-production.jnl.gz || true'
	// 		sh 'wget -N http://skyhook.berkeleybop.org/snapshot/products/blazegraph/blazegraph-production.jnl.gz'
	// 		sh 'gunzip blazegraph-production.jnl.gz'

	// 		// Get noctua-models checkout.
	// 		sh 'pwd'
	// 		sh 'ls -AlFrt'
	// 		// Change check method to address
	// 		// https://github.com/geneontology/go-site/issues/2336.
	// 		sh "git clone --no-tags --depth=1 -b $TARGET_NOCTUA_MODELS_BRANCH https://github.com/geneontology/noctua-models.git"

	// 		// Debug check.
	// 		sh 'env'
	// 		sh 'pwd'
	// 		sh 'ls -AlFrt'

	// 		sh 'NOCTUA_MODELS_PATH=./noctua-models make target/pathway-like_go-cams.tar.gz'

	// 		// Port files out to skyhook snapshot.
	// 		withCredentials([file(credentialsId: 'skyhook-private-key', variable: 'SKYHOOK_IDENTITY')]) {
	// 		    sh 'scp -o StrictHostKeyChecking=no -o IdentitiesOnly=true -o IdentityFile=$SKYHOOK_IDENTITY target/pathway-like_go-cams.tar.gz skyhook@skyhook.berkeleybop.org:/home/skyhook/snapshot/products/ttl/pathway-like_go-cams.tar.gz'
	// 		}
	// 	    }
	// 	}
	//     }
	// }

	//...
	stage('Produce derivatives (*)') {

	    // // CHECKPOINT: Recover key environmental variables.
	    // environment {
	    // 	START_DOW = sh(script: 'curl https://skyhook.geneontology.io/pipeline-from-goa/main/metadata/dow.txt', , returnStdout: true).trim()
	    // 	START_DATE = sh(script: 'curl https://skyhook.geneontology.io/pipeline-from-goa/main/metadata/date.txt', , returnStdout: true).trim()
	    // }

	    steps {
		script {
		    // Clone go-stats on host (Jenkins git step).
		    dir('./go-stats') {
			git branch: TARGET_GO_STATS_BRANCH, url: 'https://github.com/geneontology/go-stats.git'
		    }

		    // Use raw docker run -d + docker exec to
		    // bypass the unmaintained docker-workflow
		    // plugin and avoid container teardown failures
		    // (JENKINS-73567). This stage needs a
		    // long-running Solr service, so we use a named
		    // container with explicit lifecycle management.
		    def containerName = "golr-${env.BUILD_NUMBER}"

		    try {
			// Start the container detached. All real
			// work happens via docker exec.
			sh """
			    docker run -d \
			      --name ${containerName} \
			      --init \
			      --mount type=tmpfs,destination=/srv/solr/data \
			      -u root:root \
			      -v "\$WORKSPACE":/workspace \
			      -e JENKINS_UID="\$JENKINS_UID" \
			      -e JENKINS_GID="\$JENKINS_GID" \
			      -e START_DATE="\$START_DATE" \
			      -e SANITY_SOLR_DOC_COUNT_MIN="\$SANITY_SOLR_DOC_COUNT_MIN" \
			      -e SANITY_SOLR_BIOENTITY_DOC_COUNT_MIN="\$SANITY_SOLR_BIOENTITY_DOC_COUNT_MIN" \
			      -e GOLR_INPUT_ONTOLOGIES="\$GOLR_INPUT_ONTOLOGIES" \
			      -e GOLR_INPUT_GAFS="\$GOLR_INPUT_GAFS" \
			      -e GOLR_INPUT_PANTHER_TREES="\$GOLR_INPUT_PANTHER_TREES" \
			      -e GOLR_SOLR_MEMORY="\$GOLR_SOLR_MEMORY" \
			      -e GOLR_LOADER_MEMORY="\$GOLR_LOADER_MEMORY" \
			      geneontology/golr-autoindex:28a693d28b37196d3f79acdea8c0406c9930c818_2022-03-17T171930_master \
			      tail -f /dev/null
			"""

			// WARNING: MEGAHACK
			sh "docker exec ${containerName} bash -c \"echo 'nameserver 8.8.8.8' > /etc/resolv.conf && echo 'search lbl.gov' >> /etc/resolv.conf\""

			// WARNING: MEGAHACK
			// See attempts around: https://github.com/geneontology/pipeline/issues/407#issuecomment-2513461418
			// Remove optimize, bump jetty timeout.
			sh """docker exec ${containerName} bash -c "
			    cat /tmp/run-indexer.sh | sed 's/--solr-optimize//' > /tmp/run-indexer-no-opt.sh
			    && cat /etc/default/jetty9 | sed 's/Xmx3g/Xmx16g -Djetty.timeout=300000/' > /tmp/jetty9.tmp
			    && mv /tmp/jetty9.tmp /etc/default/jetty9
			    && cat /etc/jetty9/start.ini | sed 's/http.timeout=300000/http.timeout=3000000/' > /tmp/start.ini.tmp
			    && mv /tmp/start.ini.tmp /etc/jetty9/start.ini
			\""""

			// Install pip dependencies as root (before
			// dropping privileges) since they go into
			// system site-packages.
			sh "docker exec ${containerName} pip3 install --force-reinstall requests==2.19.1"
			sh "docker exec ${containerName} pip3 install --force-reinstall networkx==2.2"

			// Create jenkins user matching host UID/GID.
			sh "docker exec ${containerName} bash -c \"groupadd -g \\\$JENKINS_GID jenkins || true\""
			sh "docker exec ${containerName} bash -c \"useradd -u \\\$JENKINS_UID -g \\\$JENKINS_GID -m -s /bin/bash jenkins\""

			// Build index into tmpfs (stays as root for
			// Solr/Jetty service management).
			sh "docker exec ${containerName} bash /tmp/run-indexer-no-opt.sh"

			// After indexer completes, fix ownership for
			// jenkins user.
			sh "docker exec ${containerName} bash -c \"chown -R jenkins:jenkins /workspace && chmod -R a+r /srv/solr/data\""

			// Immediately check to see if it looks like
			// we have enough docs when trying a release.
			if( env.BRANCH_NAME == 'release' ){

			    // Test overall.
			    echo "SANITY_SOLR_DOC_COUNT_MIN:${env.SANITY_SOLR_DOC_COUNT_MIN}"
			    sh "docker exec -u jenkins ${containerName} curl 'http://localhost:8080/solr/select?q=*:*&rows=0&wt=json'"
			    sh """docker exec ${containerName} bash -c "
				if [ \\\$SANITY_SOLR_DOC_COUNT_MIN -gt \\\$(curl 'http://localhost:8080/solr/select?q=*:*&rows=0&wt=json' | grep -oh '\"numFound\":[[:digit:]]*' | grep -oh '[[:digit:]]*') ]; then exit 1; else echo 'We seem to be clear wrt doc count'; fi
			    \""""

			    // Test bioentity.
			    echo "SANITY_SOLR_BIOENTITY_DOC_COUNT_MIN:${env.SANITY_SOLR_BIOENTITY_DOC_COUNT_MIN}"
			    sh "docker exec -u jenkins ${containerName} curl 'http://localhost:8080/solr/select?q=*:*&rows=0&wt=json&fq=document_category:bioentity'"
			    sh """docker exec ${containerName} bash -c "
				if [ \\\$SANITY_SOLR_BIOENTITY_DOC_COUNT_MIN -gt \\\$(curl 'http://localhost:8080/solr/select?q=*:*&rows=0&wt=json&fq=document_category:bioentity' | grep -oh '\"numFound\":[[:digit:]]*' | grep -oh '[[:digit:]]*') ]; then exit 1; else echo 'We seem to be clear wrt doc count'; fi
			    \""""
			}

			// Copy tmpfs Solr contents onto skyhook.
			sh "docker exec -u jenkins ${containerName} tar --use-compress-program=pigz -cvf /tmp/golr-index-contents.tgz -C /srv/solr/data/index ."
			withCredentials([file(credentialsId: 'skyhook-private-key', variable: 'SKYHOOK_IDENTITY'), string(credentialsId: 'skyhook-machine-private', variable: 'SKYHOOK_MACHINE')]) {
			    sh "docker cp \"\$SKYHOOK_IDENTITY\" ${containerName}:/home/jenkins/.skyhook_key"
			    sh "docker exec ${containerName} bash -c \"chown jenkins:jenkins /home/jenkins/.skyhook_key && chmod 0600 /home/jenkins/.skyhook_key\""
			    // Copy over index.
			    // Copy over log.
			    sh "docker exec -u jenkins ${containerName} scp -o StrictHostKeyChecking=no -o IdentitiesOnly=true -o IdentityFile=/home/jenkins/.skyhook_key /tmp/golr-index-contents.tgz skyhook@\$SKYHOOK_MACHINE:/home/skyhook/pipeline-from-goa/main/products/solr/"
			    sh "docker exec -u jenkins ${containerName} scp -o StrictHostKeyChecking=no -o IdentitiesOnly=true -o IdentityFile=/home/jenkins/.skyhook_key /tmp/golr_timestamp.log skyhook@\$SKYHOOK_MACHINE:/home/skyhook/pipeline-from-goa/main/products/solr/"
			}

			// Solr should still be running in the
			// background here from indexing--create stats
			// products from running GOlr.
			sh "docker exec ${containerName} bash -c \"chown -R jenkins:jenkins /workspace/go-stats\""
			sh "docker exec ${containerName} bash -c \"mkdir -p /tmp/stats && chown jenkins:jenkins /tmp/stats\""
			sh "docker exec -u jenkins ${containerName} cp /workspace/go-stats/libraries/go-stats/*.py /tmp"

			// Check that results have been stored properly.
			echo "Check that results have been stored properly"
			sh "docker exec -u jenkins ${containerName} curl 'http://localhost:8080/solr/select?q=*:*&rows=0'"
			echo "End of results"
			retry(3){
			    sh "docker exec -u jenkins ${containerName} python3 /tmp/go_reports.py -g http://localhost:8080/solr/ -s http://current.geneontology.org/release_stats/go-stats.json -n http://current.geneontology.org/release_stats/go-stats-no-pb.json -c http://snapshot.geneontology.org/ontology/go.obo -p http://current.geneontology.org/ontology/go.obo -r http://current.geneontology.org/release_stats/go-references.tsv -o /tmp/stats/ -d \$START_DATE"
			}
			retry(3) {
			    sh "docker exec -u jenkins ${containerName} bash -c \"cd /workspace/go-stats && wget -N http://current.geneontology.org/release_stats/aggregated-go-stats-summaries.json\""
			}

			// Roll the stats forward.
			sh "docker exec -u jenkins ${containerName} python3 /tmp/aggregate-stats.py -a /workspace/go-stats/aggregated-go-stats-summaries.json -b /tmp/stats/go-stats-summary.json -o /tmp/stats/aggregated-go-stats-summaries.json"

			withCredentials([file(credentialsId: 'skyhook-private-key', variable: 'SKYHOOK_IDENTITY'), string(credentialsId: 'skyhook-machine-private', variable: 'SKYHOOK_MACHINE')]) {
			    sh "docker cp \"\$SKYHOOK_IDENTITY\" ${containerName}:/home/jenkins/.skyhook_key"
			    sh "docker exec ${containerName} bash -c \"chown jenkins:jenkins /home/jenkins/.skyhook_key && chmod 0600 /home/jenkins/.skyhook_key\""
			    retry(3) {
				// Copy over stats files.
				sh "docker exec -u jenkins ${containerName} scp -o StrictHostKeyChecking=no -o IdentitiesOnly=true -o IdentityFile=/home/jenkins/.skyhook_key /tmp/stats/* skyhook@\$SKYHOOK_MACHINE:/home/skyhook/pipeline-from-goa/main/release_stats/"
			    }
			}

			// See if sleeping a little gives the tmpfs
			// a little time to catch up.
			sleep time: 2, unit: 'MINUTES'

			// Fix ownership so jenkins user can clean up.
			sh "docker exec ${containerName} bash -c \"chown -R \\\$JENKINS_UID:\\\$JENKINS_GID /workspace || true\""

		    } finally {
			// Explicit container cleanup -- this is the
			// whole point of the migration away from the
			// docker-workflow plugin. No more "Failed to
			// kill container" build failures.
			sh "docker stop ${containerName} || true"
			sh "docker rm -f ${containerName} || true"
		    }
		}
	    }
	}

	stage('GO-CAM processing') {
	    steps {
		script {
		    // Clone gocam-py on host (Jenkins git step).
		    // Pipeline scripts are NOT included in the pip
		    // package, so we must clone the repo and run
		    // from there.
		    dir('./gocam-py') {
			git branch: TARGET_GOCAM_PY_BRANCH, url: 'https://github.com/geneontology/gocam-py.git'
		    }

		    // Run all container work via raw docker run,
		    // bypassing the unmaintained docker-workflow
		    // plugin to avoid container teardown failures
		    // (JENKINS-73567).
		    withCredentials([
			file(credentialsId: 'skyhook-private-key', variable: 'SKYHOOK_IDENTITY'),
			string(credentialsId: 'skyhook-machine-private', variable: 'SKYHOOK_MACHINE')
		    ]) {
			sh """
			    docker run --rm \
			      --init \
			      --mount type=tmpfs,destination=/tmp \
			      -u root:root \
			      -v "\$WORKSPACE":/workspace \
			      -v "\$SKYHOOK_IDENTITY":/secrets/skyhook_key:ro \
			      -e SKYHOOK_MACHINE="\$SKYHOOK_MACHINE" \
			      -e JENKINS_UID="\$JENKINS_UID" \
			      -e JENKINS_GID="\$JENKINS_GID" \
			      -e MINERVA_JSON_TARBALL_URL="\$MINERVA_JSON_TARBALL_URL" \
			      ubuntu:noble bash -c "
				# WARNING: MEGAHACK
				echo 'nameserver 8.8.8.8' > /etc/resolv.conf
				echo 'search lbl.gov' >> /etc/resolv.conf

				# Install system dependencies.
				DEBIAN_FRONTEND=noninteractive apt-get update
				DEBIAN_FRONTEND=noninteractive apt-get -y install python3 python3-pip python3-venv git openssh-client wget graphviz libgraphviz-dev

				# Install uv (not available in Ubuntu apt repos).
				pip3 install --break-system-packages uv

				# Create jenkins user matching host UID/GID.
				groupadd -g \\\$JENKINS_GID jenkins || true
				useradd -u \\\$JENKINS_UID -g \\\$JENKINS_GID -m -s /bin/bash jenkins
				chown -R jenkins:jenkins /workspace
				chown jenkins:jenkins /tmp

				# Set up skyhook key for jenkins user.
				cp /secrets/skyhook_key /home/jenkins/.skyhook_key
				chown jenkins:jenkins /home/jenkins/.skyhook_key
				chmod 0600 /home/jenkins/.skyhook_key

				# Install gocam-py dependencies.
				cd /workspace/gocam-py
				chown -R jenkins:jenkins .
				# Mark repo safe for git; needed because
				# uv-dynamic-versioning uses git.
				su jenkins -c 'git config --global --add safe.directory /workspace/gocam-py'
				su jenkins -c 'uv sync --all-extras'

				# Set up working directory structure.
				su jenkins -c 'mkdir -p /tmp/gocam-work/input /tmp/gocam-work/01-gocam-models /tmp/gocam-work/02-true-gocams /tmp/gocam-work/02-pseudo-gocams /tmp/gocam-work/03-indexed-true-gocams /tmp/gocam-work/04-index-files /tmp/gocam-work/05-browser-search-docs /tmp/gocam-work/reports'

				# Download and extract Minerva JSON tarball.
				su jenkins -c 'wget -q -O /tmp/gocam-work/minerva-models.tar.gz '\\\$MINERVA_JSON_TARBALL_URL''
				su jenkins -c 'tar -xzf /tmp/gocam-work/minerva-models.tar.gz -C /tmp/gocam-work/input'

				# Download released GO ontology and GOC groups
				# metadata from current.geneontology.org for use
				# in step 3 (indexing).
				su jenkins -c 'wget -q -O /tmp/gocam-work/go.obo https://current.geneontology.org/ontology/go.obo'
				su jenkins -c 'wget -q -O /tmp/gocam-work/groups.yaml https://current.geneontology.org/metadata/groups.yaml'

				# Step 1: Convert Minerva models to GO-CAM models.
				su jenkins -c 'uv run python pipeline/convert_minerva_models_to_gocam_models.py --input-dir /tmp/gocam-work/input --output-dir /tmp/gocam-work/01-gocam-models --report-file /tmp/gocam-work/reports/01-convert.json --verbose'

				# Step 2: Filter true GO-CAM models from pseudo GO-CAMs.
				su jenkins -c 'uv run python pipeline/filter_true_gocam_models.py --input-dir /tmp/gocam-work/01-gocam-models --output-dir /tmp/gocam-work/02-true-gocams --pseudo-gocam-output-dir /tmp/gocam-work/02-pseudo-gocams --report-file /tmp/gocam-work/reports/02-filter.json --verbose'

				# Step 3: Add query index (OAK lookups) to models.
				# Uses released GO ontology via pronto adapter.
				# NCBITaxon is not a GO product, so it still
				# auto-downloads from OBO Foundry (sqlite:obo:ncbitaxon).
				su jenkins -c 'uv run python pipeline/add_query_index_to_models.py --input-dir /tmp/gocam-work/02-true-gocams --output-dir /tmp/gocam-work/03-indexed-true-gocams --report-file /tmp/gocam-work/reports/03-index.json --go-adapter-descriptor pronto:/tmp/gocam-work/go.obo --goc-groups-yaml /tmp/gocam-work/groups.yaml --verbose'

				# Step 4: Generate index files (~6 JSON files).
				su jenkins -c 'uv run python pipeline/generate_index_files.py --input-dir /tmp/gocam-work/03-indexed-true-gocams --output-dir /tmp/gocam-work/04-index-files --report-file /tmp/gocam-work/reports/04-index-files.json --verbose'

				# Step 5: Generate GO-CAM Browser search docs (1 JSON file).
				su jenkins -c 'uv run python pipeline/generate_go_cam_browser_search_docs.py --input-dir /tmp/gocam-work/03-indexed-true-gocams --output /tmp/gocam-work/05-browser-search-docs/go-cam-browser-search-docs.json --report-file /tmp/gocam-work/reports/05-browser-search.json --verbose'

				# Upload release artifacts to skyhook
				# with retry logic for each scp.
				for i in 1 2 3; do
				    su jenkins -c 'scp -r -o StrictHostKeyChecking=no -o IdentitiesOnly=true -o IdentityFile=/home/jenkins/.skyhook_key /tmp/gocam-work/02-true-gocams/* skyhook@'\\\$SKYHOOK_MACHINE':/home/skyhook/pipeline-from-goa/main/go-cams/json/' && break
				    sleep 5
				done
				for i in 1 2 3; do
				    su jenkins -c 'scp -r -o StrictHostKeyChecking=no -o IdentitiesOnly=true -o IdentityFile=/home/jenkins/.skyhook_key /tmp/gocam-work/03-indexed-true-gocams/* skyhook@'\\\$SKYHOOK_MACHINE':/home/skyhook/pipeline-from-goa/main/products/indexed-go-cams/' && break
				    sleep 5
				done
				for i in 1 2 3; do
				    su jenkins -c 'scp -r -o StrictHostKeyChecking=no -o IdentitiesOnly=true -o IdentityFile=/home/jenkins/.skyhook_key /tmp/gocam-work/04-index-files/* skyhook@'\\\$SKYHOOK_MACHINE':/home/skyhook/pipeline-from-goa/main/go-cams/index-json/' && break
				    sleep 5
				done
				for i in 1 2 3; do
				    su jenkins -c 'scp -o StrictHostKeyChecking=no -o IdentitiesOnly=true -o IdentityFile=/home/jenkins/.skyhook_key /tmp/gocam-work/05-browser-search-docs/go-cam-browser-search-docs.json skyhook@'\\\$SKYHOOK_MACHINE':/home/skyhook/pipeline-from-goa/main/products/go-cam-search/' && break
				    sleep 5
				done
				for i in 1 2 3; do
				    su jenkins -c 'scp -r -o StrictHostKeyChecking=no -o IdentitiesOnly=true -o IdentityFile=/home/jenkins/.skyhook_key /tmp/gocam-work/reports/* skyhook@'\\\$SKYHOOK_MACHINE':/home/skyhook/pipeline-from-goa/main/reports/go-cam/' && break
				    sleep 5
				done

				# Fix ownership so jenkins user can clean up.
				chown -R \\\$JENKINS_UID:\\\$JENKINS_GID /workspace || true
			      "
			"""
		    }
		}
	    }
	}

	stage('QC reports download') {
	    steps {
		script {
		    try {
			// Get GOEx QC reports (gorule reports per
			// annotation group).
			sh 'wget --wait 5 --recursive --no-parent --no-host-directories --execute robots=off --span-hosts=off --user-agent="GOC Pipeline" --debug --reject="index.html*,*.tmp,robots.txt" https://ftp.ebi.ac.uk/pub/contrib/goa/goex/current/qc_reports/'
		    } catch (exception) {
			echo "There has been a recursion/download failure for QC reports; accepting that this was likely fine, but check contents."
		    }

		    // Copy to skyhook.
		    withCredentials([file(credentialsId: 'skyhook-private-key', variable: 'SKYHOOK_IDENTITY'), string(credentialsId: 'skyhook-machine-private', variable: 'SKYHOOK_MACHINE')]) {
			sh 'scp -r -o StrictHostKeyChecking=no -o IdentitiesOnly=true -o IdentityFile=$SKYHOOK_IDENTITY ./pub/contrib/goa/goex/current/qc_reports/* skyhook@$SKYHOOK_MACHINE:/home/skyhook/pipeline-from-goa/main/reports/'
		    }
		}
	    }
	}

	stage('Metadata and annotations README') {
	    steps {
		script {
		    // Clone geneontology/metadata and copy to
		    // skyhook. This replaces the old go-site
		    // metadata directory copy.
		    dir('./metadata-repo') {
			git branch: 'main', url: 'https://github.com/geneontology/metadata.git'
		    }

		    // Download annotation README from go-site.
		    sh 'wget -N https://raw.githubusercontent.com/geneontology/go-site/$TARGET_GO_SITE_BRANCH/static/pages/README-annotation-downloads.txt'

		    withCredentials([file(credentialsId: 'skyhook-private-key', variable: 'SKYHOOK_IDENTITY'), string(credentialsId: 'skyhook-machine-private', variable: 'SKYHOOK_MACHINE')]) {
			sh 'rsync -avz --exclude=".git" -e "ssh -o StrictHostKeyChecking=no -o IdentitiesOnly=true -o IdentityFile=$SKYHOOK_IDENTITY" ./metadata-repo/ skyhook@$SKYHOOK_MACHINE:/home/skyhook/pipeline-from-goa/main/metadata/'
			sh 'scp -o StrictHostKeyChecking=no -o IdentitiesOnly=true -o IdentityFile=$SKYHOOK_IDENTITY README-annotation-downloads.txt skyhook@$SKYHOOK_MACHINE:/home/skyhook/pipeline-from-goa/main/annotations/README.txt'
		    }
		}
	    }
	}

	stage('PANTHER trees') {
	    steps {
		script {
		    dir('./go-site') {
			git branch: TARGET_GO_SITE_BRANCH, url: 'https://github.com/geneontology/go-site.git'

			// Download PANTHER tree files and names.
			sh "wget -N http://data.pantherdb.org/PANTHER${PANTHER_VERSION}/globals/tree_files.tar.gz"
			sh "wget -N http://data.pantherdb.org/PANTHER${PANTHER_VERSION}/globals/names.tab"
			sh 'tar -zxvf tree_files.tar.gz'

			// Generate arbre files from PANTHER data.
			sh 'python3 ./scripts/prepare-panther-arbre-directory.py -v --names names.tab --trees tree_files --output arbre'
			sh 'tar --use-compress-program=pigz -cvf arbre.tgz -C arbre .'
		    }

		    // Copy to skyhook.
		    withCredentials([file(credentialsId: 'skyhook-private-key', variable: 'SKYHOOK_IDENTITY'), string(credentialsId: 'skyhook-machine-private', variable: 'SKYHOOK_MACHINE')]) {
			sh 'scp -o StrictHostKeyChecking=no -o IdentitiesOnly=true -o IdentityFile=$SKYHOOK_IDENTITY ./go-site/arbre.tgz skyhook@$SKYHOOK_MACHINE:/home/skyhook/pipeline-from-goa/main/products/panther/'
		    }
		}
	    }
	}

	// //...
	// stage('Sanity II') {
	//     when { anyOf { branch 'release' } }
	//     steps {

	// 	//
	// 	echo 'Push pre-release to http://amigo-staging.geneontology.io for testing.'

	// 	// Ninja in our file credentials from Jenkins.
	// 	withCredentials([file(credentialsId: 'skyhook-private-key', variable: 'SKYHOOK_IDENTITY'), file(credentialsId: 'go-svn-private-key', variable: 'GO_SVN_IDENTITY'), file(credentialsId: 'ansible-bbop-local-slave', variable: 'DEPLOY_LOCAL_IDENTITY'), file(credentialsId: 'go-aws-ec2-ansible-slave', variable: 'DEPLOY_REMOTE_IDENTITY')]) {

	// 	    // Get our operations code and decend into ansible
	// 	    // working directory.
	// 	    dir('./operations') {

	// 		git([branch: 'master',
	// 		     credentialsId: 'bbop-agent-github-user-pass',
	// 		     url: 'https://github.com/geneontology/operations.git'])
	// 		dir('./ansible') {

	// 		    retry(3){
	// 			sh 'ansible-playbook update-golr-w-skyhook-forced.yaml --inventory=hosts.amigo --private-key="$DEPLOY_LOCAL_IDENTITY" -e skyhook_branch=release -e target_host=amigo-golr-staging'
	// 		    }

	// 		    // Pause on user input.
	// 		    echo 'Sanity II: Awaiting user input before proceeding.'
	// 		    emailext to: "${TARGET_RELEASE_HOLD_EMAILS}",
	// 			subject: "GO Pipeline waiting on input for ${env.BRANCH_NAME}",
	// 			body: "The ${env.BRANCH_NAME} pipeline is waiting on user input. Please see: https://build.geneontology.org/job/geneontology/job/pipeline/job/${env.BRANCH_NAME}"
	// 		    lock(resource: 'release-run', inversePrecedence: true) {
	// 			echo "Sanity II: A release run holds the lock."
	// 			timeout(time:7, unit:'DAYS') {
	// 			    input message:'Approve release products?'
	// 			}
	// 		    }
	// 		    echo 'Sanity II: Positive user input input given.'
	// 		}
	// 	    }
	// 	}
	// 	// Temporary stop here so that we can have an index to
	// 	// examine for data issues before going with "full"
	// 	// snapshot. 2024-07-15.
	// 	echo 'Only master can touch that target.'
	// 	sh '`exit -1`'
	//     }
	// }

	// stage('Archive (*)') {
	//     // CHECKPOINT: Recover key environmental variables.
	//     environment {
	// 	START_DOW = sh(script: 'curl http://skyhook.berkeleybop.org/snapshot/metadata/dow.txt', , returnStdout: true).trim()
	// 	START_DATE = sh(script: 'curl http://skyhook.berkeleybop.org/snapshot/metadata/date.txt', , returnStdout: true).trim()
	//     }

	//     when { anyOf { branch 'release'; branch 'snapshot'; branch 'master' } }
	//     steps {
	// 	// Experimental stanza to support mounting the sshfs
	// 	// using the "hidden" skyhook identity.
	// 	sh 'mkdir -p $WORKSPACE/mnt/ || true'
	// 	withCredentials([file(credentialsId: 'skyhook-private-key', variable: 'SKYHOOK_IDENTITY')]) {
	// 	    sh 'sshfs -oStrictHostKeyChecking=no -o IdentitiesOnly=true -o IdentityFile=$SKYHOOK_IDENTITY -o idmap=user skyhook@skyhook.berkeleybop.org:/home/skyhook $WORKSPACE/mnt/'

	// 	    // Try to catch and prevent goa_uniprot_all-src
	// 	    // from getting into zenodo archive, etc. Re:
	// 	    // #207.
	// 	    sh 'pwd'
	// 	    sh 'ls -AlF $WORKSPACE/mnt/snapshot/products/upstream_and_raw_data/ || true'
	// 	    sh 'rm -f $WORKSPACE/mnt/snapshot/products/upstream_and_raw_data/goa_uniprot_all-src.gaf.gz || true'
	// 	    sh 'ls -AlF $WORKSPACE/mnt/snapshot/products/upstream_and_raw_data/ || true'

	// 	    // Redo goa_uniprot_all names for publication. From:
	// 	    // https://github.com/geneontology/go-site/issues/1984
	// 	    sh 'mv $WORKSPACE/mnt/snapshot/annotations/goa_uniprot_all.gaf.gz $WORKSPACE/mnt/snapshot/annotations/filtered_goa_uniprot_all.gaf.gz || true'
	// 	    sh 'mv $WORKSPACE/mnt/snapshot/annotations/goa_uniprot_all_noiea.gaf.gz $WORKSPACE/mnt/snapshot/annotations/filtered_goa_uniprot_all_noiea.gaf.gz || true'
	// 	    sh 'mv $WORKSPACE/mnt/snapshot/annotations/goa_uniprot_all_noiea.gpad.gz $WORKSPACE/mnt/snapshot/annotations/filtered_goa_uniprot_all_noiea.gpad.gz || true'
	// 	    sh 'mv $WORKSPACE/mnt/snapshot/annotations/goa_uniprot_all_noiea.gpi.gz $WORKSPACE/mnt/snapshot/annotations/filtered_goa_uniprot_all_noiea.gpi.gz || true'

	// 	    // Get annotation download directory prepped. From:
	// 	    // https://github.com/geneontology/go-site/issues/1971
	// 	    sh 'rm -f README-annotation-downloads.txt || true'
	// 	    sh 'wget -N https://raw.githubusercontent.com/geneontology/go-site/$TARGET_GO_SITE_BRANCH/static/pages/README-annotation-downloads.txt'
	// 	    sh 'mv README-annotation-downloads.txt $WORKSPACE/mnt/snapshot/annotations/README.txt || true'

	// 	    // Try and remove /lib and /bin from getting into
	// 	    // the archives by removing them now that we're
	// 	    // done using them for product builds. Re: #268.
	// 	    sh 'ls -AlF $WORKSPACE/mnt/snapshot/'
	// 	    sh 'rm -r -f $WORKSPACE/mnt/snapshot/bin || true'
	// 	    sh 'rm -r -f $WORKSPACE/mnt/snapshot/lib || true'
	// 	    sh 'ls -AlF $WORKSPACE/mnt/snapshot/'
	// 	}
	// 	// Copy the product to the right location. As well,
	// 	// archive.
	// 	withCredentials([file(credentialsId: 'aws_go_push_json', variable: 'S3_PUSH_JSON'), file(credentialsId: 's3cmd_go_push_configuration', variable: 'S3CMD_JSON'), string(credentialsId: 'zenodo_go_production_token', variable: 'ZENODO_PRODUCTION_TOKEN'), string(credentialsId: 'zenodo_go_sandbox_token', variable: 'ZENODO_SANDBOX_TOKEN')]) {
	// 	    // Ready...
	// 	    dir('./go-site') {
	// 		git branch: TARGET_GO_SITE_BRANCH, url: 'https://github.com/geneontology/go-site.git'

	// 		// WARNING: Caveats and reasons as same
	// 		// pattern above. We need this as some clients
	// 		// are not standard and it turns out there are
	// 		// some subtle incompatibilities with urllib3
	// 		// and boto in some versions, so we will use a
	// 		// virtual env to paper that over.  See:
	// 		// https://github.com/geneontology/pipeline/issues/8#issuecomment-356762604
	// 		sh 'python3 -m venv mypyenv'
	// 		withEnv(["PATH+EXTRA=${WORKSPACE}/go-site/bin:${WORKSPACE}/go-site/mypyenv/bin", 'PYTHONHOME=', "VIRTUAL_ENV=${WORKSPACE}/go-site/mypyenv", 'PY_ENV=mypyenv', 'PY_BIN=mypyenv/bin']){

	// 		    // Extra package for the indexer.
	// 		    sh 'python3 ./mypyenv/bin/pip3 install --force-reinstall pystache==0.5.4'

	// 		    // Correct for (possibly) bad boto3,
	// 		    // as mentioned above.
	// 		    sh 'python3 ./mypyenv/bin/pip3 install boto3==1.18.52'
	// 		    sh 'python3 ./mypyenv/bin/pip3 install botocore==1.21.52'

	// 		    // Needed to work around new incompatibility:
	// 		    // https://github.com/geneontology/pipeline/issues/286
	// 		    sh 'python3 ./mypyenv/bin/pip3 install --force-reinstall certifi==2021.10.8'

	// 		    // Extra package for the uploader.
	// 		    sh 'python3 ./mypyenv/bin/pip3 install filechunkio'

	// 		    // Grab BDBag.
	// 		    sh 'python3 ./mypyenv/bin/pip3 install bdbag'

	// 		    // Need for large uploads in requests.
	// 		    sh 'python3 ./mypyenv/bin/pip3 install requests-toolbelt'

	// 		    // Need as replacement for awful requests lib.
	// 		    sh 'python3 ./mypyenv/bin/pip3 install pycurl'

	// 		    // Apparently something wrong with default
	// 		    // version; error like
	// 		    // https://stackoverflow.com/questions/45821085/awshttpsconnection-object-has-no-attribute-ssl-context
	// 		    sh 'python3 ./mypyenv/bin/pip3 install awscli'

	// 		    // A temporary workaround for
	// 		    // https://github.com/geneontology/pipeline/issues/247,
	// 		    // forcing requests used by bdbags to a
	// 		    // verion that is usable by python 3.5
	// 		    // (our current raw machine default
	// 		    // version of python3).
	// 		    sh 'python3 ./mypyenv/bin/pip3 install --force-reinstall requests==2.25.1'

	// 		    // Well, we need to do a couple of things here in
	// 		    // a structured way, so we'll go ahead and drop
	// 		    // into the scripting mode.
	// 		    script {

	// 			// Build either a release or testing
	// 			// version of a generic BDBag/DOI
	// 			// workflow, keeping special bucket
	// 			// mappings in mind.
	// 			if( env.BRANCH_NAME == 'release' ){
	// 			    sh 'python3 ./scripts/create-bdbag-remote-file-manifest.py -v --walk $WORKSPACE/mnt/snapshot/ --remote http://release.geneontology.org/$START_DATE --output manifest.json'
	// 			}else if( env.BRANCH_NAME == 'snapshot' || env.BRANCH_NAME == 'master' || env.BRANCH_NAME == 'snapshot-post-fail' ){
	// 			    sh 'python3 ./scripts/create-bdbag-remote-file-manifest.py -v --walk $WORKSPACE/mnt/snapshot/ --remote $TARGET_INDEXER_PREFIX --output manifest.json'
	// 			}

	// 			// To make a full BDBag, we first need
	// 			// a copy of the data as BDBags change
	// 			// directory layout (e.g. data/).
	// 			sh 'mkdir -p $WORKSPACE/copyover/ || true'
	// 			sh 'cp -r $WORKSPACE/mnt/snapshot/* $WORKSPACE/copyover/'
	// 			// Make the BDBag in the copyover/
	// 			// (unarchived, as we want to leave it
	// 			// to pigz).
	// 			sh 'python3 ./mypyenv/bin/bdbag $WORKSPACE/copyover'
	// 			// Tarball the whole directory for
	// 			// "deep" archive (handmade BDBag).
	// 			sh 'tar --use-compress-program=pigz -cvf go-release-archive.tgz -C $WORKSPACE/copyover .'

	// 			// We have the archives, now let's try
	// 			// and get them into position--this is
	// 			// fail-y, so we are going to try and
	// 			// buffer failure here for the time
	// 			// being until we work it all out. We
	// 			// are going to do the "hard"/large
	// 			// one first, then skip the
	// 			// "easy"/small one if we fail, so
	// 			// that we can retry this whole stage
	// 			// again on failure.
	// 			try {
	// 			    // Archive full archive.
	// 			    if( env.BRANCH_NAME == 'release' ){
	// 				sh 'python3 ./scripts/zenodo-version-update.py --verbose --key $ZENODO_PRODUCTION_TOKEN --concept $ZENODO_ARCHIVE_CONCEPT --file go-release-archive.tgz --output ./release-archive-doi.json --revision $START_DATE'
	// 			    }else if( env.BRANCH_NAME == 'snapshot' || env.BRANCH_NAME == 'snapshot-post-fail' ){
	// 				// WARNING: to save Zenodo 1TB
	// 				// a month, for snapshot,
	// 				// we'll lie about the DOI
	// 				// that we get (not a big lie
	// 				// as they don't resolve on
	// 				// sandbox anyways).
	// 				//sh 'python3 ./scripts/zenodo-version-update.py --verbose --sandbox --key $ZENODO_SANDBOX_TOKEN --concept $ZENODO_ARCHIVE_CONCEPT --file go-release-archive.tgz --output ./release-archive-doi.json --revision $START_DATE'
	// 				sh 'echo \'{\' > ./release-archive-doi.json'
	// 				sh 'echo \'    "doi": "10.5072/zenodo.000000"\' >> ./release-archive-doi.json'
	// 				sh 'echo \'}\' >> ./release-archive-doi.json'

	// 			    }else if( env.BRANCH_NAME == 'master' ){
	// 				sh 'python3 ./scripts/zenodo-version-update.py --verbose --sandbox --key $ZENODO_SANDBOX_TOKEN --concept $ZENODO_ARCHIVE_CONCEPT --file go-release-archive.tgz --output ./release-archive-doi.json --revision $START_DATE'
	// 			    }

	// 			    // Get the DOI to skyhook for
	// 			    // publishing, but don't bother
	// 			    // with the full thing--too much
	// 			    // space and already in Zenodo.
	// 			    sh 'cp release-archive-doi.json $WORKSPACE/mnt/snapshot/metadata/release-archive-doi.json'

	// 			} catch (exception) {
	// 			    // Something went bad with the
	// 			    // Zenodo archive upload.
	// 			    echo "There has been a failure in the archive upload to Zenodo."
	// 			    emailext to: "${TARGET_ADMIN_EMAILS}",
	// 				subject: "GO Pipeline Zenodo archive upload fail for ${env.BRANCH_NAME}",
	// 				body: "There has been a failure in the archive upload to Zenodo, in ${env.BRANCH_NAME}. Please see: https://build.geneontology.org/job/geneontology/job/pipeline/job/${env.BRANCH_NAME}"
	// 			    // Hard die if this is a release.
	// 			    if( env.BRANCH_NAME == 'release' ){
	// 				error 'Zenodo archive upload error on release--no recovery.'
	// 			    }
	// 			}
	// 		    }
	// 		}
	// 	    }
	// 	}
	//     }
	//     // WARNING: Extra safety as I expect this to sometimes fail.
	//     post {
	// 	always {
	// 	    // Bail on the remote filesystem.
	// 	    sh 'fusermount -u $WORKSPACE/mnt/ || true'
	// 	    // Purge the copyover point.
	// 	    sh 'rm -r -f $WORKSPACE/copyover || true'
	// 	}
	//     }
	// }
	// stage('Publish') {
	//     when { anyOf { branch 'release'; branch 'snapshot'; branch 'snapshot-post-fail'; branch 'master' } }
	//     // CHECKPOINT: Recover key environmental variables.
	//     environment {
	// 	START_DOW = sh(script: 'curl http://skyhook.berkeleybop.org/snapshot/metadata/dow.txt', , returnStdout: true).trim()
	// 	START_DATE = sh(script: 'curl http://skyhook.berkeleybop.org/snapshot/metadata/date.txt', , returnStdout: true).trim()
	//     }
	//     steps {
	// 	// Experimental stanza to support mounting the sshfs
	// 	// using the "hidden" skyhook identity.
	// 	sh 'mkdir -p $WORKSPACE/mnt/ || true'
	// 	withCredentials([file(credentialsId: 'skyhook-private-key', variable: 'SKYHOOK_IDENTITY')]) {
	// 	    sh 'sshfs -oStrictHostKeyChecking=no -o IdentitiesOnly=true -o IdentityFile=$SKYHOOK_IDENTITY -o idmap=user skyhook@skyhook.berkeleybop.org:/home/skyhook $WORKSPACE/mnt/'
	// 	}
	// 	// Copy the product to the right location. As well,
	// 	// archive.
	// 	withCredentials([file(credentialsId: 'aws_go_push_json', variable: 'S3_PUSH_JSON'), file(credentialsId: 's3cmd_go_push_configuration', variable: 'S3CMD_JSON'), string(credentialsId: 'aws_go_access_key', variable: 'AWS_ACCESS_KEY_ID'), string(credentialsId: 'aws_go_secret_key', variable: 'AWS_SECRET_ACCESS_KEY')]) {
	// 	    // Ready...
	// 	    dir('./go-site') {
	// 		git branch: TARGET_GO_SITE_BRANCH, url: 'https://github.com/geneontology/go-site.git'

	// 		// TODO: Special handling still needed w/o OSF.io?
	// 		// WARNING: Caveats and reasons as same
	// 		// pattern above. We need this as some clients
	// 		// are not standard and it turns out there are
	// 		// some subtle incompatibilities with urllib3
	// 		// and boto in some versions, so we will use a
	// 		// virtual env to paper that over.  See:
	// 		// https://github.com/geneontology/pipeline/issues/8#issuecomment-356762604
	// 		sh 'python3 -m venv mypyenv'
	// 		withEnv(["PATH+EXTRA=${WORKSPACE}/go-site/bin:${WORKSPACE}/go-site/mypyenv/bin", 'PYTHONHOME=', "VIRTUAL_ENV=${WORKSPACE}/go-site/mypyenv", 'PY_ENV=mypyenv', 'PY_BIN=mypyenv/bin']){

	// 		    // Extra package for the indexer.
	// 		    sh 'python3 ./mypyenv/bin/pip3 install --force-reinstall pystache==0.5.4'

	// 		    // Extra package for the uploader.
	// 		    sh 'python3 ./mypyenv/bin/pip3 install filechunkio'

	// 		    // Let's be explicit here as well, as there were recent issues.
	// 		    //
	// 		    sh 'python3 ./mypyenv/bin/pip3 install rsa'
	// 		    sh 'python3 ./mypyenv/bin/pip3 install awscli'

	// 		    // Version locking for boto3 / botocore
	// 		    // upgrade that is incompatible with
	// 		    // python3.5. See issues #250 and #271.
	// 		    sh 'python3 ./mypyenv/bin/pip3 install boto3==1.18.52'
	// 		    sh 'python3 ./mypyenv/bin/pip3 install botocore==1.21.52'
	// 		    sh 'python3 ./mypyenv/bin/pip3 install s3transfer==0.5.0'

	// 		    // Well, we need to do a couple of things here in
	// 		    // a structured way, so we'll go ahead and drop
	// 		    // into the scripting mode.
	// 		    script {

	// 			// Create working index off of
	// 			// skyhook. For "release", this will
	// 			// be "current". For "snapshot", this
	// 			// will be "snapshot".
	// 			sh 'python3 ./scripts/directory_indexer.py -v --inject ./scripts/directory-index-template.html --directory $WORKSPACE/mnt/snapshot --prefix $TARGET_INDEXER_PREFIX -x'

	// 			// Push into S3 buckets. Simple
	// 			// overall case: copy tree directly
	// 			// over. For "release", this will be
	// 			// "current". For "snapshot", this
	// 			// will be "snapshot".
	// 			sh 'python3 ./scripts/s3-uploader.py -v --credentials $S3_PUSH_JSON --directory $WORKSPACE/mnt/snapshot/ --bucket $TARGET_BUCKET --number $BUILD_ID --pipeline snapshot'

	// 			// Also, some runs have special maps
	// 			// to buckets...
	// 			if( env.BRANCH_NAME == 'release' ){

	// 			    // "release" -> dated path for
	// 			    // indexing (clobbering
	// 			    // "current"'s index.
	// 			    sh 'python3 ./scripts/directory_indexer.py -v --inject ./scripts/directory-index-template.html --directory $WORKSPACE/mnt/snapshot --prefix http://release.geneontology.org/$START_DATE -x -u'
	// 			    // "release" -> dated path for S3.
	// 			    sh 'python3 ./scripts/s3-uploader.py -v --credentials $S3_PUSH_JSON --directory $WORKSPACE/mnt/snapshot/ --bucket go-data-product-release/$START_DATE --number $BUILD_ID --pipeline snapshot'

	// 			    // Build the capper index.html...
	// 			    sh 'python3 ./scripts/bucket-indexer.py --credentials $S3_PUSH_JSON --bucket go-data-product-release --inject ./scripts/directory-index-template.html --prefix http://release.geneontology.org > top-level-index.html'
	// 			    // ...and push it up to S3.
	// 			    sh 's3cmd -c $S3CMD_JSON --acl-public --mime-type=text/html --cf-invalidate put top-level-index.html s3://go-data-product-release/index.html'

	// 			}else if( env.BRANCH_NAME == 'snapshot' || env.BRANCH_NAME == 'snapshot-post-fail' ){

	// 			    // Currently, the "daily"
	// 			    // debugging buckets are intended
	// 			    // to be RO directly in S3 for
	// 			    // debugging.
	// 			    sh 'python3 ./scripts/s3-uploader.py -v --credentials $S3_PUSH_JSON --directory $WORKSPACE/mnt/snapshot/ --bucket go-data-product-daily/$START_DOW --number $BUILD_ID --pipeline snapshot'

	// 			}else if( env.BRANCH_NAME == 'master' ){
	// 			    // Pass.
	// 			}

	// 			// Invalidate the CDN now that the new
	// 			// files are up.
	// 			sh 'echo "[preview]" > ./awscli_config.txt && echo "cloudfront=true" >> ./awscli_config.txt'
	// 			sh 'AWS_CONFIG_FILE=./awscli_config.txt python3 ./mypyenv/bin/aws cloudfront create-invalidation --distribution-id $AWS_CLOUDFRONT_DISTRIBUTION_ID --paths "/*"'
	// 			// The release branch also needs to
	// 			// deal with the second location.
	// 			if( env.BRANCH_NAME == 'release' ){
	// 			    sh 'AWS_CONFIG_FILE=./awscli_config.txt python3 ./mypyenv/bin/aws cloudfront create-invalidation --distribution-id $AWS_CLOUDFRONT_RELEASE_DISTRIBUTION_ID --paths "/*"'
	// 			}
	// 		    }
	// 		}
	// 	    }
	// 	}
	//     }
	//     // WARNING: Extra safety as I expect this to sometimes fail.
	//     post {
	// 	always {
	// 	    // Bail on the remote filesystem.
	// 	    sh 'fusermount -u $WORKSPACE/mnt/ || true'
	// 	}
	//     }
	// }
	// // Big things to do on major branches.
	// stage('Deploy') {
	//     // For exploration of #204, we'll hold back attempts to push out to AmiGO for master and snapshot
	//     // so we don't keep clobbering #204 trials out.
	//     //when { anyOf { branch 'release'; branch 'snapshot'; branch 'master' } }
	//     when { anyOf { branch 'release' } }
	//     steps {
	// 	parallel(
	// 	    "AmiGO": {

	// 		// Ninja in our file credentials from Jenkins.
	// 		withCredentials([file(credentialsId: 'skyhook-private-key', variable: 'SKYHOOK_IDENTITY'), file(credentialsId: 'go-svn-private-key', variable: 'GO_SVN_IDENTITY'), file(credentialsId: 'ansible-bbop-local-slave', variable: 'DEPLOY_LOCAL_IDENTITY'), file(credentialsId: 'go-aws-ec2-ansible-slave', variable: 'DEPLOY_REMOTE_IDENTITY')]) {

	// 		    // Get our operations code and decend into ansible
	// 		    // working directory.
	// 		    dir('./operations') {

	// 			git([branch: 'master',
	// 			     credentialsId: 'bbop-agent-github-user-pass',
	// 			     url: 'https://github.com/geneontology/operations.git'])
	// 			dir('./ansible') {
	// 			    ///
	// 			    /// Push out to an AmiGO.
	// 			    ///
	// 			    script {
	// 				if( env.BRANCH_NAME == 'release' ){

	// 				    echo 'No current public push on release to Blazegraph.'
	// 				    // retry(3){
	// 				    //	sh 'ansible-playbook update-endpoint.yaml --inventory=hosts.local-rdf-endpoint --private-key="$DEPLOY_LOCAL_IDENTITY" -e target_user=bbop --extra-vars="pipeline=current build=production endpoint=production"'
	// 				    // }

	// 				    echo 'No current public push on release to GOlr.'
	// 				    // retry(3){
	// 				    //	sh 'ansible-playbook ./update-golr.yaml --inventory=hosts.amigo --private-key="$DEPLOY_LOCAL_IDENTITY" -e target_host=amigo-golr-aux -e target_user=bbop'
	// 				    // }
	// 				    // retry(3){
	// 				    //	sh 'ansible-playbook ./update-golr.yaml --inventory=hosts.amigo --private-key="$DEPLOY_LOCAL_IDENTITY" -e target_host=amigo-golr-production -e target_user=bbop'
	// 				    // }

	// 				}else if( env.BRANCH_NAME == 'snapshot' || env.BRANCH_NAME == 'snapshot-post-fail' ){

	// 				    echo 'Push snapshot out internal Blazegraph'
	// 				    retry(3){
	// 					sh 'ansible-playbook update-endpoint.yaml --inventory=hosts.local-rdf-endpoint --private-key="$DEPLOY_LOCAL_IDENTITY" -e target_user=bbop --extra-vars="pipeline=current build=internal endpoint=internal"'
	// 				    }

	// 				    echo 'Push snapshot out to experimental AmiGO'
	// 				    retry(3){
	// 					sh 'ansible-playbook ./update-golr-w-snap.yaml --inventory=hosts.amigo --private-key="$DEPLOY_REMOTE_IDENTITY" -e target_host=amigo-golr-exp -e target_user=ubuntu'
	// 				    }

	// 				}else if( env.BRANCH_NAME == 'master' ){

	// 				    echo 'Push master out to experimental AmiGO'
	// 				    retry(3){
	// 					sh 'ansible-playbook ./update-golr-w-exp.yaml --inventory=hosts.amigo --private-key="$DEPLOY_REMOTE_IDENTITY" -e target_host=amigo-golr-exp -e target_user=ubuntu'
	// 				    }

	// 				}
	// 			    }
	// 			}
	// 		    }
	// 		}
	// 	    }
	// 	)
	//     }
	//     // WARNING: Extra safety as I expect this to sometimes fail.
	//     post {
	// 	always {
	// 	    // Bail on the remote filesystem.
	// 	    sh 'fusermount -u $WORKSPACE/mnt/ || true'
	// 	}
	//     }
	// }
	// stage('TODO: Final status') {
	//     steps {
	//	echo 'TODO: final'
	//     }
	// }
    }
    post {
	// Let's let our people know if things go well.
	success {
	    script {
		if( env.BRANCH_NAME == 'release' || env.BRANCH_NAME == 'snapshot-post-fail' || env.BRANCH_NAME == 'derivatives-from-goa' || env.BRANCH_NAME == 'main' ){
		    echo "There has been a successful run of the ${env.BRANCH_NAME} pipeline."
		    emailext to: "${TARGET_SUCCESS_EMAILS}",
			subject: "GO Pipeline success for ${env.BRANCH_NAME}",
			body: "There has been successful run of the ${env.BRANCH_NAME} pipeline. Please see: https://build.geneontology.io/job/pipeline-from-goa/job/${env.BRANCH_NAME}"
		}
	    }
	}
	// Let's let our internal people know if things change.
	changed {
	    echo "There has been a change in the ${env.BRANCH_NAME} pipeline."
	    emailext to: "${TARGET_ADMIN_EMAILS}",
		subject: "GO Pipeline change for ${env.BRANCH_NAME}",
		body: "There has been a pipeline status change in ${env.BRANCH_NAME}. Please see: https://build.geneontology.io/job/geneontology/job/pipeline-from-goa/job/${env.BRANCH_NAME}"
	}
	// Let's let our internal people know if things go badly.
	failure {
	    echo "There has been a failure in the ${env.BRANCH_NAME} pipeline."
	    emailext to: "${TARGET_ADMIN_EMAILS}",
		subject: "GO Pipeline FAIL for ${env.BRANCH_NAME}",
		body: "There has been a pipeline failure in ${env.BRANCH_NAME}. Please see: https://build.geneontology.io/job/pipeline-from-goa/job/${env.BRANCH_NAME}"
	}
    }
}

// Check that we do not affect public targets on non-mainline runs.
void watchdog() {
    if( BRANCH_NAME != 'master' && TARGET_BUCKET == 'go-data-product-experimental'){
	echo 'Only master can touch that target.'
	sh '`exit -1`'
    }else if( BRANCH_NAME != 'snapshot-post-fail' && TARGET_BUCKET == 'go-data-product-snapshot'){
	echo 'Only master can touch that target.'
	sh '`exit -1`'
    }else if( BRANCH_NAME != 'release' && TARGET_BUCKET == 'go-data-product-release'){
	echo 'Only master can touch that target.'
	sh '`exit -1`'
    }
}

// Reset and initialize skyhook base.
void initialize() {

    // Possibly protect against issues like #350 by making sure
    // $JOB_NAME is there and vaguely sane.
    if(JOB_NAME instanceof String && JOB_NAME.size() >= 3 ) {

	// Get a mount point ready
	sh 'mkdir -p $WORKSPACE/mnt || true'
	// Ninja in our file credentials from Jenkins.
	withCredentials([file(credentialsId: 'skyhook-private-key', variable: 'SKYHOOK_IDENTITY'), string(credentialsId: 'skyhook-machine-private', variable: 'SKYHOOK_MACHINE')]) {
	    // Try and ssh fuse skyhook onto our local system.
	    sh 'sshfs -o StrictHostKeyChecking=no -o IdentitiesOnly=true -o IdentityFile=$SKYHOOK_IDENTITY -o idmap=user skyhook@$SKYHOOK_MACHINE:/home/skyhook $WORKSPACE/mnt/'
	}
	// Remove anything we might have left around from
	// times past.
	sh 'rm -r -f $WORKSPACE/mnt/$JOB_NAME || true'
	// Rebuild directory structure.
	sh 'mkdir -p $WORKSPACE/mnt/$JOB_NAME/products || true'
	sh 'mkdir -p $WORKSPACE/mnt/$JOB_NAME/products/ttl || true'
	sh 'mkdir -p $WORKSPACE/mnt/$JOB_NAME/products/json || true'
	sh 'mkdir -p $WORKSPACE/mnt/$JOB_NAME/products/blazegraph || true'
	sh 'mkdir -p $WORKSPACE/mnt/$JOB_NAME/products/upstream_and_raw_data || true'
	sh 'mkdir -p $WORKSPACE/mnt/$JOB_NAME/products/pages || true'
	sh 'mkdir -p $WORKSPACE/mnt/$JOB_NAME/products/solr || true'
	sh 'mkdir -p $WORKSPACE/mnt/$JOB_NAME/products/panther || true'
	sh 'mkdir -p $WORKSPACE/mnt/$JOB_NAME/products/gaferencer || true'
	sh 'mkdir -p $WORKSPACE/mnt/$JOB_NAME/products/indexed-go-cams || true'
	sh 'mkdir -p $WORKSPACE/mnt/$JOB_NAME/products/go-cam-search || true'
	sh 'mkdir -p $WORKSPACE/mnt/$JOB_NAME/go-cams/json || true'
	sh 'mkdir -p $WORKSPACE/mnt/$JOB_NAME/go-cams/index-json || true'
	sh 'mkdir -p $WORKSPACE/mnt/$JOB_NAME/reports/go-cam || true'
	sh 'mkdir -p $WORKSPACE/mnt/$JOB_NAME/metadata || true'
	sh 'mkdir -p $WORKSPACE/mnt/$JOB_NAME/annotations || true'
	sh 'mkdir -p $WORKSPACE/mnt/$JOB_NAME/ontology || true'
	sh 'mkdir -p $WORKSPACE/mnt/$JOB_NAME/reports || true'
	sh 'mkdir -p $WORKSPACE/mnt/$JOB_NAME/release_stats || true'
	sh 'mkdir -p $WORKSPACE/mnt/$JOB_NAME/TEMP || true'
	// Tag the top to let the world know I was at least
	// here.
	sh 'echo "Runtime summary." > $WORKSPACE/mnt/$JOB_NAME/summary.txt'
	sh 'echo "" >> $WORKSPACE/mnt/$JOB_NAME/summary.txt'
	sh 'date >> $WORKSPACE/mnt/$JOB_NAME/summary.txt'
	sh 'echo "" >> $WORKSPACE/mnt/$JOB_NAME/summary.txt'
	sh 'echo "Release notes: https://github.com/geneontology/go-site/tree/master/releases" >> $WORKSPACE/mnt/$JOB_NAME/summary.txt'
	sh 'echo "Branch: $JOB_NAME" >> $WORKSPACE/mnt/$JOB_NAME/summary.txt'
	sh 'echo "Start day: $START_DAY" >> $WORKSPACE/mnt/$JOB_NAME/summary.txt'
	sh 'echo "Start date: $START_DATE" >> $WORKSPACE/mnt/$JOB_NAME/summary.txt'
	sh 'echo "$START_DAY" > $WORKSPACE/mnt/$JOB_NAME/metadata/dow.txt'
	sh 'echo "$START_DATE" > $WORKSPACE/mnt/$JOB_NAME/metadata/date.txt'
	sh 'echo "{\"date\": \"$START_DATE\"}" > $WORKSPACE/mnt/$JOB_NAME/metadata/release-date.json'

	sh 'echo "Official release date: metadata/release-date.json" >> $WORKSPACE/mnt/$JOB_NAME/summary.txt'
	sh 'echo "Official Zenodo archive DOI: metadata/release-archive-doi.json" >> $WORKSPACE/mnt/$JOB_NAME/summary.txt'
	sh 'echo "TODO: Note software versions." >> $WORKSPACE/mnt/$JOB_NAME/summary.txt'
	// TODO: This should be wrapped in exception
	// handling. In fact, this whole thing should be.
	sh 'fusermount -u $WORKSPACE/mnt/ || true'
    }else{
	sh 'echo "HOW DID THIS EVEN HAPPEN?"'
    }
}
