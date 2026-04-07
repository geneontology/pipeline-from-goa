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

### Iteration cost

A full pipeline run takes several hours. Avoid blind retries:

- Prefer externalized bash scripts in `scripts/` over inline `bash -c
  '...'` in the Jenkinsfile. Inline shell embedded in Groovy strings
  has 4 layers of interpretation (Groovy → Jenkins sh → host shell →
  docker → container shell) and is a major source of subtle bugs.
- Use Jenkins "Restart from Stage" to skip already-successful stages
  on retry.
- `shellcheck` any externalized scripts before pushing.
- For multi-line `bash -c` content: `&&`/`||` must be at the END of
  a line, never the start. Or use `set -e; cmd1; cmd2` on one line.
