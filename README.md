# Hidden Dependabot Check Repro

This repo now targets the closer-to-production case behind issue `#698`:

- visible PR checks are green
- the merged `main` commit later receives a failed `Dependabot` check
- the failed check is detached from PR context and easy to miss in normal PR review
- old Scalingo behavior may treat that failed auxiliary check as blocking

## What This Repo Contains

- a minimal Node app deployable on Scalingo
- one required visible CI job: `required-ci`
- a minimal Bundler manifest used only to give Dependabot a real ecosystem to scan
- a real `.github/dependabot.yml` repro configuration with intentionally broken registry auth

The repo no longer relies on synthetic `automerge` check runs.

## Why This Is Closer To The Real Bug

The `Scalingo/api` occurrence on commit `6898bcc8dbad085572988f00958ea12066a39b61` had:

- visible main CI checks green
- a separate failed check run named `Dependabot`
- a GitHub-internal workflow run with path `dynamic/dependabot/dependabot-updates`
- `pull_requests: []` on that hidden failure

This repo is set up to trigger a real Dependabot-originated failure on the merged `main` SHA instead of a synthetic GitHub Actions check.

## Files

- `.github/workflows/required-ci.yml`
- `.github/dependabot.yml`
- `Gemfile`
- `Procfile`
- `package.json`
- `server.js`
- `repro_dependabot_hidden_check.sh`

## GitHub Setup

1. Use `main` as the default branch.
2. Link the repository to a dedicated Scalingo app.
3. Enable auto-deploy for `main`.
4. Enable review apps if you also want to observe PR deployments.

## Branch Protection

Protect `main` and configure:

1. Require a pull request before merging.
2. Require status checks to pass before merging.
3. Select only `required-ci` as a required check.

Do not make any `Dependabot` check required.

## Dependabot Setup

This repro intentionally expects the top-level registry secret referenced in `.github/dependabot.yml` to be missing or unusable:

- `BROKEN_RUBYGEMS_TOKEN`

Do not create a valid Dependabot secret for that name.

The config is meant to validate successfully, then fail later when GitHub runs the hidden Dependabot update workflow on the merged `main` commit.

## Repro Protocol

From the repo root:

```bash
bash repro_dependabot_hidden_check.sh prepare
bash repro_dependabot_hidden_check.sh open-pr
bash repro_dependabot_hidden_check.sh wait-pr-checks
```

Then merge the PR normally in GitHub.

The helper script touches only `.github/dependabot.yml`, which is deliberate: the target behavior is that a merge changing the Dependabot config triggers the later hidden Dependabot run on the merge SHA.

## Expected Before Merge

On the open PR:

- `Required CI / required-ci (pull_request)` is green
- `Required CI / required-ci (push)` is green
- no failed `Dependabot` check is visible in the normal PR checks list

## Expected After Merge

On the merged `main` commit:

- `Required CI / required-ci (push)` stays green
- GitHub later adds a failed check named `Dependabot`
- that `Dependabot` check is not part of branch protection

Inspect it with:

```bash
bash repro_dependabot_hidden_check.sh show-main-checks PR_NUMBER
```

## Scalingo Expectation

Before the fix:

- Scalingo may treat the failed `Dependabot` check as blocking
- deployment or review app status can become `Aborted: Other job failed`

After the fix:

- Scalingo should ignore that failed `Dependabot` check if it is not required on `main`

## Notes

- Dependabot processing is asynchronous. The hidden failed check can appear after the merge succeeds.
- If GitHub does not produce a hidden Dependabot run on the first try, run the protocol again. Updating `.github/dependabot.yml` is the intended trigger surface.
- The Node app and CI remain intentionally simple. The Bundler files exist only to give Dependabot a real update target.
