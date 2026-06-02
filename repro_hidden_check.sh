#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT_DIR"

BASE_BRANCH="${BASE_BRANCH:-main}"
REMOTE="${REMOTE:-origin}"
MARKER="${MARKER:-[trigger-hidden-fail]}"
BRANCH_NAME="${BRANCH_NAME:-repro/pr-hidden-check}"
STAMP="$(date +%Y%m%d-%H%M%S)"
FILE_NAME="repro-hidden-check-${STAMP}.txt"

usage() {
  cat <<'EOF'
Usage:
  bash repro_hidden_check.sh prepare
  bash repro_hidden_check.sh retrigger-pr
  bash repro_hidden_check.sh open-pr
  bash repro_hidden_check.sh wait-pr-checks
  bash repro_hidden_check.sh show-state

Environment overrides:
  REMOTE=origin
  BASE_BRANCH=main
  BRANCH_NAME=repro/pr-hidden-check
  MARKER='[trigger-hidden-fail]'

Purpose:
  Reproduce the case where Scalingo prints "Aborted: Other job failed"
  while the PR is still open.

Important:
  This protocol relies on a second workflow creating a failed synthetic
  check run named "automerge" on the PR head SHA after Required CI succeeds.
EOF
}

repo_url() {
  git remote get-url "$REMOTE" | sed -E 's#git@github.com:#https://github.com/#; s#\.git$##'
}

require_gh() {
  if ! command -v gh >/dev/null 2>&1; then
    echo "gh is required for this command." >&2
    exit 1
  fi
}

show_state() {
  echo "Repository: $(repo_url)"
  echo "Current branch: $(git rev-parse --abbrev-ref HEAD)"
  echo "HEAD SHA: $(git rev-parse HEAD)"
  echo "Remote main SHA: $(git rev-parse "$REMOTE/$BASE_BRANCH")"
  echo
  git log --oneline --decorate -5
}

prepare() {
  git fetch "$REMOTE"
  git checkout -B "$BRANCH_NAME" "$REMOTE/$BASE_BRANCH"

  printf 'hidden-check repro %s\n' "$STAMP" > "$FILE_NAME"
  git add "$FILE_NAME"
  git commit -m "repro: hidden PR check ${MARKER}"
  git push -u "$REMOTE" "$BRANCH_NAME"

  local sha
  sha="$(git rev-parse HEAD)"

  cat <<EOF

Prepared PR repro branch.

Branch: $BRANCH_NAME
SHA:    $sha
File:   $FILE_NAME

Next steps:
1. Open this PR with:
   bash repro_hidden_check.sh open-pr
2. After the PR is open, force a pull_request synchronize event with:
   bash repro_hidden_check.sh retrigger-pr
3. Wait until the PR head SHA shows green visible checks with:
   bash repro_hidden_check.sh wait-pr-checks
   Expected:
   - Required CI / required-ci (pull_request)
   - Required CI / required-ci (push)
   - Auto Merge / automerge can appear as a failed synthetic check run

Target outcome:
- the PR stays open
- Required CI stays green
- a separate failed "automerge" check run is attached to the PR SHA
- Scalingo can print "Aborted: Other job failed"
EOF
}

open_pr() {
  require_gh
  git checkout "$BRANCH_NAME"

  if gh pr view "$BRANCH_NAME" >/dev/null 2>&1; then
    echo "PR already exists for branch $BRANCH_NAME"
    gh pr view "$BRANCH_NAME" --web
    return 0
  fi

  gh pr create \
    --base "$BASE_BRANCH" \
    --head "$BRANCH_NAME" \
    --title "repro: hidden PR check" \
    --body "Reproduce a hidden auxiliary check_run failure on the PR SHA."

  gh pr view "$BRANCH_NAME" --web
}

retrigger_pr() {
  git checkout "$BRANCH_NAME"

  local retrigger_file="retrigger-pr-checks.txt"
  printf 'retrigger %s\n' "$(date +%Y%m%d-%H%M%S)" >> "$retrigger_file"
  git add "$retrigger_file"
  git commit -m "chore: retrigger PR checks ${MARKER}"
  git push "$REMOTE" "$BRANCH_NAME"

  cat <<EOF

Pushed an extra commit to the open PR branch.

Why:
This forces a pull_request "synchronize" event, which is the most reliable
way to get the visible PR check surface populated.

Now wait for the PR head SHA to show:
  - Required CI / required-ci (pull_request)
  - Required CI / required-ci (push)
  - Auto Merge / automerge can appear as a failed synthetic check run

Then run:
  bash repro_hidden_check.sh wait-pr-checks
EOF
}

wait_pr_checks() {
  require_gh
  git checkout "$BRANCH_NAME"

  echo "Watching checks for branch $BRANCH_NAME"
  echo "Expected visible checks:"
  echo "  - Required CI / required-ci (pull_request)"
  echo "  - Required CI / required-ci (push)"
  echo "  - Auto Merge / automerge can appear as a failed synthetic check run"
  echo "Press Ctrl+C to stop polling."
  echo

  while true; do
    clear
    echo "Watching checks for branch $BRANCH_NAME"
    echo "Expected visible checks:"
    echo "  - Required CI / required-ci (pull_request)"
    echo "  - Required CI / required-ci (push)"
    echo "  - Auto Merge / automerge can appear as a failed synthetic check run"
    echo "Press Ctrl+C to stop polling."
    echo
    gh pr checks "$BRANCH_NAME" || true
    sleep 5
  done
}

cmd="${1:-}"
case "$cmd" in
  prepare)
    prepare
    ;;
  retrigger-pr)
    retrigger_pr
    ;;
  open-pr)
    open_pr
    ;;
  wait-pr-checks)
    wait_pr_checks
    ;;
  show-state)
    show_state
    ;;
  *)
    usage
    exit 1
    ;;
esac
