#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT_DIR"

BASE_BRANCH="${BASE_BRANCH:-main}"
REMOTE="${REMOTE:-origin}"
BRANCH_NAME="${BRANCH_NAME:-repro/dependabot-hidden-check}"
STAMP="$(date +%Y%m%d-%H%M%S)"
DEPENDABOT_FILE=".github/dependabot.yml"

require_gh() {
  if ! command -v gh >/dev/null 2>&1; then
    echo "gh is required for this command." >&2
    exit 1
  fi
}

usage() {
  cat <<'EOF'
Usage:
  bash repro_dependabot_hidden_check.sh prepare
  bash repro_dependabot_hidden_check.sh open-pr
  bash repro_dependabot_hidden_check.sh wait-pr-checks
  bash repro_dependabot_hidden_check.sh show-main-checks PR_NUMBER

Purpose:
  Reproduce a real Dependabot-originated hidden failing check on the merged
  main SHA while the visible PR checks remain green before merge.

Protocol:
  1. Touch .github/dependabot.yml on a PR branch.
  2. Merge the PR after visible required-ci checks pass.
  3. Wait for GitHub to run Dependabot on the merged main commit.
  4. Inspect the merged main SHA for a failed "Dependabot" check run.
EOF
}

prepare() {
  git fetch "$REMOTE"
  git checkout -B "$BRANCH_NAME" "$REMOTE/$BASE_BRANCH"

  if grep -q '^# repro-touch:' "$DEPENDABOT_FILE"; then
    sed -i "s/^# repro-touch:.*/# repro-touch: $STAMP/" "$DEPENDABOT_FILE"
  else
    tmp_file="$(mktemp)"
    {
      printf '# repro-touch: %s\n' "$STAMP"
      cat "$DEPENDABOT_FILE"
    } > "$tmp_file"
    mv "$tmp_file" "$DEPENDABOT_FILE"
  fi

  git add "$DEPENDABOT_FILE"
  git commit -m "repro: retrigger dependabot hidden check"
  git push -u "$REMOTE" "$BRANCH_NAME"

  cat <<EOF

Prepared Dependabot repro branch.

Branch: $BRANCH_NAME
SHA:    $(git rev-parse HEAD)
File:   $DEPENDABOT_FILE

Next steps:
1. Open the PR with:
   bash repro_dependabot_hidden_check.sh open-pr
2. Wait until visible PR checks are green with:
   bash repro_dependabot_hidden_check.sh wait-pr-checks
3. Merge the PR normally in GitHub.
4. Inspect the merged main commit with:
   bash repro_dependabot_hidden_check.sh show-main-checks PR_NUMBER

Expected before merge:
  - Required CI / required-ci (pull_request) green
  - Required CI / required-ci (push) green
  - no visible failed Dependabot check on the PR

Expected after merge on main:
  - Required CI / required-ci (push) green
  - a detached failed Dependabot check run on the same merge SHA
EOF
}

open_pr() {
  require_gh
  git checkout "$BRANCH_NAME"

  if gh pr view "$BRANCH_NAME" >/dev/null 2>&1; then
    gh pr view "$BRANCH_NAME" --web
    return 0
  fi

  gh pr create \
    --base "$BASE_BRANCH" \
    --head "$BRANCH_NAME" \
    --title "repro: retrigger dependabot hidden check" \
    --body "Touch .github/dependabot.yml to reproduce a hidden Dependabot failure on the merged main commit."

  gh pr view "$BRANCH_NAME" --web
}

wait_pr_checks() {
  require_gh
  git checkout "$BRANCH_NAME"

  while true; do
    clear
    echo "Watching visible PR checks for branch $BRANCH_NAME"
    echo "Expected before merge:"
    echo "  - Required CI / required-ci (pull_request)"
    echo "  - Required CI / required-ci (push)"
    echo "Press Ctrl+C to stop polling."
    echo
    gh pr checks "$BRANCH_NAME" || true
    sleep 5
  done
}

show_main_checks() {
  require_gh
  local pr_number="${1:?PR number is required}"
  local merge_sha

  merge_sha="$(gh pr view "$pr_number" --json mergeCommit --jq '.mergeCommit.oid')"
  echo "Merged main SHA: $merge_sha"
  echo
  gh api "repos/{owner}/{repo}/commits/$merge_sha/check-runs" \
    --jq '.check_runs[] | [.name, .conclusion, .details_url] | @tsv'
}

case "${1:-}" in
  prepare)
    prepare
    ;;
  open-pr)
    open_pr
    ;;
  wait-pr-checks)
    wait_pr_checks
    ;;
  show-main-checks)
    show_main_checks "${2:-}"
    ;;
  *)
    usage
    exit 1
    ;;
esac
