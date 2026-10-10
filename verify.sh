#!/usr/bin/env bash
# githug verify: send a PR's commits to githug and fail if any commit that claims an AI agent
# doesn't check out. Human commits always pass. Needs gh + jq (preinstalled on GitHub runners).
set -euo pipefail
: "${REPO:?}" "${PR:?no pull request number (run on pull_request, or set the pull-request input)}"
GITHUG_URL="${GITHUG_URL:-https://githug.ai}"
tmp="$(mktemp -d)"

gh api "repos/$REPO/pulls/$PR/commits?per_page=100" \
  --jq '[.[] | {sha, message: .commit.message, date: .commit.author.date, author_email: .commit.author.email, author_name: .commit.author.name}]' > "$tmp/commits.json"

jq -n --arg repo "$REPO" --slurpfile c "$tmp/commits.json" '{repo: $repo, commits: $c[0]}' > "$tmp/request.json"
# Retries 429/5xx with backoff. If githug stays unreachable, pass with a warning (an outage
# must not block anyone's PRs) unless fail-on-error is set.
if ! curl -fsS --retry 4 --retry-delay 5 --retry-all-errors --max-time 30 "$GITHUG_URL/v1/verify" \
    -H 'Content-Type: application/json' -H 'User-Agent: githug-verify-action/1' --data-binary @"$tmp/request.json" > "$tmp/result.json"; then
  if [ "${FAIL_ON_ERROR:-false}" = true ]; then
    echo "::error::githug verify couldn't reach $GITHUG_URL."
    exit 1
  fi
  echo "::warning::githug verify couldn't reach $GITHUG_URL; skipping the check this time."
  echo "githug verify: skipped (githug unreachable)." >> "${GITHUB_STEP_SUMMARY:-/dev/stdout}"
  exit 0
fi

agent=$(jq -r .agent_commits "$tmp/result.json")
failing=$(jq -r .failing "$tmp/result.json")
{
  echo "### githug verify"
  if [ "$agent" = 0 ]; then echo "No commits in this PR claim an AI agent."; fi
  if [ "$agent" != 0 ]; then
    echo "| | commit | agent | accountable |"
    echo "|---|---|---|---|"
    jq -r --arg u "$GITHUG_URL" --arg r "$REPO" '.commits[] | select(.claims_agent) |
      "| \(if .verdict == "verified" then "✅" elif .verdict == "consistent" then "◐" else "❌" end) | [\(.sha[0:7])](\($u)/v/\($r)/\(.sha)) | \(.agent) | \(.accountable // "?") |"' "$tmp/result.json"
    jq -r '.commits[] | select(.claims_agent and .verdict != "verified") | "\n**\(.sha[0:7])** — " + ([.checks[] | select(.ok | not) | .label] | join("; "))' "$tmp/result.json"
    echo
    echo "✅ attested by the agent's key at push · ◐ consistent with githug's records, not attested · ❌ contradicts the records"
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
echo "githug verify: $agent agent commit(s), none contradict githug's records ($(jq -r '.attested // 0' "$tmp/result.json") attested)."
