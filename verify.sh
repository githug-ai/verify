#!/usr/bin/env bash
# githug verify: send a PR's commits to githug and fail if any commit that claims an AI agent
# doesn't check out. Human commits always pass. Needs gh + jq (preinstalled on GitHub runners).
set -euo pipefail
: "${REPO:?}" "${PR:?no pull request number (run on pull_request, or set the pull-request input)}"
GITHUG_URL="${GITHUG_URL:-https://githug.ai}"
tmp="$(mktemp -d)"

gh api "repos/$REPO/pulls/$PR/commits?per_page=100" \
  --jq '[.[] | {sha, message: .commit.message, date: .commit.author.date, author_email: .commit.author.email, author_name: .commit.author.name}]' > "$tmp/commits.json"

jq -n --arg repo "$REPO" --slurpfile c "$tmp/commits.json" '{repo: $repo, commits: $c[0]}' |
  curl -fsS "$GITHUG_URL/v1/verify" -H 'Content-Type: application/json' -H 'User-Agent: githug-verify-action/1' --data-binary @- > "$tmp/result.json"

agent=$(jq -r .agent_commits "$tmp/result.json")
failing=$(jq -r .failing "$tmp/result.json")
{
  echo "### githug verify"
  if [ "$agent" = 0 ]; then echo "No commits in this PR claim an AI agent."; fi
  if [ "$agent" != 0 ]; then
    echo "| | commit | agent | accountable |"
    echo "|---|---|---|---|"
    jq -r --arg u "$GITHUG_URL" --arg r "$REPO" '.commits[] | select(.claims_agent) |
      "| \(if .verdict == "verified" then "✅" else "❌" end) | [\(.sha[0:7])](\($u)/v/\($r)/\(.sha)) | \(.agent) | \(.accountable // "?") |"' "$tmp/result.json"
    jq -r '.commits[] | select(.claims_agent and .verdict != "verified") | "\n**\(.sha[0:7])** — " + ([.checks[] | select(.ok | not) | .label] | join("; "))' "$tmp/result.json"
  fi
  echo
  echo "Checked against githug's agent registry and key log · [githug.ai](https://githug.ai)"
} >> "${GITHUB_STEP_SUMMARY:-/dev/stdout}"

if [ -n "${GITHUB_OUTPUT:-}" ]; then
  echo "agent-commits=$agent" >> "$GITHUB_OUTPUT"
  echo "failing=$failing" >> "$GITHUB_OUTPUT"
fi
if [ "$(jq -r .pass "$tmp/result.json")" != true ]; then
  echo "::error::$failing commit(s) claim an AI agent that githug can't verify. Details in the job summary."
  exit 1
fi
echo "githug verify: $agent agent commit(s), all verified."
