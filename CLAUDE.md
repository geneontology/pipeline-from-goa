# Pipeline-from-GOA

## Issue and commit hygiene

Every commit and PR must reference a GitHub issue. Every issue must
be assigned to a project. The chain is:

    commit → issue → project

- Commits: end the first line with `; for geneontology/pipeline-from-goa#NN`
- PRs: reference the issue in the body
- Issues: must be added to the active project (see "Which project"
  below)

If no issue exists for the work being done, create one first. Do
not commit without an issue reference.

### Picking the right issue

Issues are read by non-technical project managers and biologists,
so issue titles and bodies should tell the project story at a level
they can follow. Technical detail (file paths, retry counts, glob
patterns, etc.) belongs in the **commit message** or PR body, not
the issue.

When picking the issue to tag in a commit footer:

- Pick by **story fit**, not topic-keyword match or "precedent from
  a prior commit." The right issue is the one whose narrative the
  commit advances.
- If no issue is an exact match, walk **up the hierarchy of
  generality**. A small reliability fix can sit under a broader
  "ensure the pipeline produces files at expected locations" issue.
- If unsure, **ask** rather than defaulting to the closest stretch.
  Mis-tagging is recoverable via comments but generates churn.

### Which project

The active project for `pipeline-from-goa` work is currently
**GOEx Data Exchange**, but the project will change over time as
the work moves through phases (planning → active → closeout →
successor project for the next phase). The repo stays the same;
the project label drifts.

If it isn't obvious from context which project is current — for
example, by looking at recently-created issues and where they were
assigned, or from the user's recent direction — **confirm with
the user before assigning**. Don't assume a project name remembered
from an earlier session is still the active one.

## Renaming public-facing paths

Before renaming any path that surfaces under
`current.geneontology.org/` or
`skyhook.geneontology.io/pipeline-from-goa/`, search the
geneontology org for consumers:

    gh search code 'PATH org:geneontology' --limit 100

If repos like `geneontology.github.io`, `go-fastapi`, or `go-stats`
hardcode the URL, the rename is **not** a unilateral change. It
needs cross-repo coordination: open an issue (assign the relevant
person, mark "In Progress" on the active project — see "Which
project" above) and pin the rename behind a deprecation/cutover
plan rather than landing it.

For examples of pinned renames waiting on cutover, see #11
(`release_stats/` rename) and #12 (`go-cams/index-json/` move).

If the audit returns no external consumers, the rename is safe to
land directly — see #13 (`reports/groups/`) and #14
(`reports/go-rules/`) for examples.

## Jenkins CI

This project uses a Jenkins CI instance for builds. To debug build
failures, you need a Jenkins API token configured in `~/.netrc`:

```
machine <jenkins-host> login <username> password <api-token>
```

If the token is missing or expired, ask the user to create a new one
via Jenkins: username (top right) -> Security -> API Token -> Add new
Token.

### Downloading console logs

Jenkins console logs (`consoleText`) can be extremely large (hundreds
of MB to multiple GB). Never try to read them directly via curl into
a tool buffer. Instead:

1. Download once to a local temp file:
   `curl -n -s -o /tmp/jenkins-build-NNN.log "<jenkins-url>/job/pipeline-from-goa/job/main/NNN/consoleText"`
2. Then analyze locally with tail, grep, etc.
3. Clean up the file when done.

### In-container scripts

In-container shell work lives in `scripts/*.sh`, NOT inline in the
Jenkinsfile. Each docker stage in the Jenkinsfile:

1. Curls its script fresh from
   `raw.githubusercontent.com/geneontology/pipeline-from-goa/${BRANCH_NAME}/scripts/foo.sh`
2. Runs `docker run --rm -v $WORKSPACE:/workspace ... image bash /workspace/scripts/foo.sh`

Do not reintroduce inline `bash -c '...'` in the Jenkinsfile. The
4-layer interpretation chain (Groovy → Jenkins sh → host shell →
docker → container shell) is a recurring source of subtle bugs.

### Editing scripts

Always run `shellcheck scripts/*.sh` before committing. It's
installed locally. Fix all warnings -- no exceptions.

### The `su jenkins -c` pattern

In-container scripts run inside ephemeral docker containers that
start as root. The base images do not have a `jenkins` user; each
script creates one with UID/GID matching the host's Jenkins agent
user (passed in via `$JENKINS_UID`/`$JENKINS_GID` env vars), so that
files written to the bind-mounted `/workspace` have correct
ownership when viewed from the host.

The pattern is intentional and required:

1. **Start as root** -- needed for `apt-get install`, `pip install`,
   modifying `/etc/`, `chown`, starting services like Jetty.
2. **Create the jenkins user** with matching host UID/GID:
   ```
   groupadd -g "$JENKINS_GID" jenkins || true
   useradd -u "$JENKINS_UID" -g "$JENKINS_GID" -m -s /bin/bash jenkins
   chown -R jenkins:jenkins /workspace
   ```
3. **Set up the skyhook key** under `/home/jenkins/`, owned by jenkins,
   mode 0600 (ssh requires this).
4. **Drop privileges** for any work that produces files or uses ssh:
   ```
   su jenkins -c 'python3 some_script.py'
   ```
5. **Final ownership fix** at end of script (defensive, in case
   anything slipped through as root):
   ```
   chown -R "$JENKINS_UID:$JENKINS_GID" /workspace || true
   ```

Do not skip the user creation and run everything as root. Even
though `--rm` cleans up the container, the bind-mounted `/workspace`
persists on the host and root-owned files there will break
subsequent builds.

`su jenkins -c '...'` is the chosen pattern despite being verbose.
It is clear, well-known, and present in every base image. We do not
swap it for `runuser`/`gosu`/`setpriv` -- consistency matters more
than the small ergonomic wins.

### Iteration cost and recovery model

A full pipeline run takes several hours. There are two distinct
iteration paths depending on what changed:

#### Script change → fast (Restart from Stage)

For bugs in `scripts/*.sh`:

1. Edit the script in `scripts/`
2. `shellcheck scripts/*.sh`
3. `git commit && git push`
4. In Jenkins UI: click the failed build → "Restart from Stage" →
   pick the failing stage

This works because the scripts are fetched at runtime from
`raw.githubusercontent.com` via `curl` in the stage. Restart from
Stage replays the **original build's pinned Jenkinsfile and SCM
revision**, but the curl fetches the latest script from the branch,
so the fix takes effect.

**This is the whole reason we externalized scripts.** Keep the bash
in `scripts/`, not inline in the Jenkinsfile, so the fast path
remains usable.

#### Jenkinsfile change → slow (Scan Repository Now + new build)

For bugs in the Jenkinsfile itself (stage structure, env vars, git
URLs, credential IDs, etc.):

Restart from Stage **cannot** pick up Jenkinsfile changes. It pins
the original build's Jenkinsfile and SCM revision; new commits are
ignored.

The correct workflow:

1. Edit the Jenkinsfile carefully (Jenkinsfile changes are
   expensive -- see below)
2. `git commit && git push`
3. In Jenkins UI, navigate to the multibranch project and click
   **"Scan Repository Now"** to make Jenkins discover the new
   commit
4. A new build will be triggered that uses the latest Jenkinsfile
5. This is a fresh build -- it runs from the first stage, including
   the long indexer

**Be extra careful when editing the Jenkinsfile.** A typo costs
hours of pipeline time. Before pushing a Jenkinsfile change:
- Read the diff carefully
- Verify any new repo URLs / paths actually exist (`gh api ...`)
- Verify any new credentials IDs are correct
- Consider whether the change can be moved into a script instead
  (scripts are cheap to iterate, the Jenkinsfile is expensive)

### Multi-line bash gotchas

- `&&`/`||` must be at the END of a line, never the start
- Use `set -e; cmd1; cmd2` for fail-fast on one line
- Bash `set -x` trace strips quotes from multi-line args -- that's a
  display artifact, not a bug
