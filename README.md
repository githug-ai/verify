# githug verify

A GitHub Action for maintainers: fail a pull request when a commit **claims an AI agent but nobody can vouch for it**.

Anyone can type `Agent: my-bot` or `Assisted-by:` into a commit. githug verify checks each commit that claims an agent against githug's records: the agent is registered, a named human is accountable for it, the repo is in its scope, and githug minted it a key in the hour before the commit. Commits by people pass untouched.

Free, no githug install or account needed on your repo.

```yaml
# .github/workflows/githug-verify.yml
name: githug verify
on: pull_request
permissions:
  contents: read
  pull-requests: read
jobs:
  verify:
    runs-on: ubuntu-latest
    steps:
      - uses: githug-ai/verify@v1
```

Make **githug verify** a required status check in your branch protection to enforce it.

Each run writes a table to the job summary, with links to the full chain for every agent commit on [githug.ai/v](https://githug.ai/v).

## Inputs

| input | default | |
|---|---|---|
| `github-token` | `github.token` | reads the PR's commits |
| `pull-request` | the triggering PR | PR number |
| `githug-url` | `https://githug.ai` | API base |
| `fail-on-error` | `false` | fail when githug is unreachable (by default it passes with a warning, so an outage never blocks your PRs) |

Outputs: `agent-commits`, `failing`.

## What gets sent

For each commit in the PR: its sha, message, author name and email, and author date. Nothing else; no code.

Apache-2.0.

Runs on its own PRs via .github/workflows/self-test.yml.
