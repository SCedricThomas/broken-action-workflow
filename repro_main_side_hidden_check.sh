#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT_DIR"

BASE_BRANCH="${BASE_BRANCH:-main}"
REMOTE="${REMOTE:-origin}"
MARKER="${MARKER:-[trigger-hidden-fail]}"
BRANCH_NAME="${BRANCH_NAME:-repro/main-side-hidden-check}"
STAMP="$(date +%Y%m%d-%H%M%S)"
FILE_NAME="repro-main-side-${STAMP}.txt"

require_gh() {
  if ! command -v gh >/dev/null 2>&1; then
    echo "gh is required for this command." >&2
    exit 1
  fi
}

repo_url() {
  git remote get-url "$REMOTE" | sed -E 's#git@github.com:#https://github.com/#; s#\.git$##'
}

usage() {
  cat <<'EOF'
Usage:
  bash repro_main_side_hidden_check.sh prepare
  bash repro_main_side_hidden_check.sh open-pr
  bash repro_main_side_hidden_check.sh wait-pr-checks

Purpose:
  Reproduce the production-like case where:
  - visible PR checks are green
  - a later main-side auxiliary check run fails on the merged commit
  - Scalingo can print "Aborted: Other job failed"

Important:
  This does NOT keep the PR open once the main-side failure exists.
  It is meant to mimic the real pix-editor style occurrence more closely
  than the PR-head synthetic check workflow.
EOF
}

prepare() {
  git fetch "$REMOTE"
  git checkout -B "$BRANCH_NAME" "$REMOTE/$BASE_BRANCH"

  printf 'main-side hidden-check repro %s\n' "$STAMP" > "$FILE_NAME"
  git add "$FILE_NAME"
  git commit -m "repro: main-side hidden check ${MARKER}"
  git push -u "$REMOTE" "$BRANCH_NAME"

  cat <<EOF

Prepared main-side repro branch.

Branch: $BRANCH_NAME
SHA:    $(git rev-parse HEAD)
File:   $FILE_NAME

Next steps:
1. Open the PR with:
   bash repro_main_side_hidden_check.sh open-pr
2. Wait until the PR visible checks are green with:
   bash repro_main_side_hidden_check.sh wait-pr-checks
3. Merge the PR normally in GitHub.

Expected after merge on the new main commit:
  - Required CI / required-ci (push) green
  - Auto Merge / automerge red

This is the closest model of the real bug where the failing auxiliary
check is created from a main-side path rather than directly on the open PR.
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
    --title "repro: main-side hidden check" \
    --body "Reproduce a main-side auxiliary failed check run after merge."

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
  *)
    usage
    exit 1
    ;;
esac
