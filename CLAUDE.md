# Pipeline-from-GOA

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

### Iteration cost

A full pipeline run takes several hours. To iterate on a script bug
without re-running the whole pipeline:

1. Edit the script in `scripts/`
2. `shellcheck scripts/*.sh`
3. `git commit && git push`
4. In Jenkins UI: click the failed build → "Restart from Stage" →
   pick the failing stage
5. The replayed Jenkinsfile fetches the latest script from the
   branch via curl, picking up your fix

This works because the scripts are fetched at runtime from GitHub
raw URLs, not from the SCM checkout that Restart-from-Stage replays.

### Multi-line bash gotchas

- `&&`/`||` must be at the END of a line, never the start
- Use `set -e; cmd1; cmd2` for fail-fast on one line
- Bash `set -x` trace strips quotes from multi-line args -- that's a
  display artifact, not a bug
