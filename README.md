# GitHub Hidden Checks Repro

This sample is meant to reproduce issue `#698`:

- a required CI check is green
- an auxiliary GitHub Actions check run fails
- before the fix, Scalingo marks the deployment as `Aborted: Other job failed`
- after the fix, Scalingo ignores the auxiliary failure if it is not a required status check on `main`

## What This Sample Contains

- a minimal Node app deployable on Scalingo
- one required GitHub Actions job: `required-ci`
- one auxiliary GitHub Actions job on `main`: `automerge`

The important part is that only `required-ci` must be configured as a required status check on `main`.

## Files

- `.github/workflows/required-ci.yml`
- `.github/workflows/automerge.yml`
- `Procfile`
- `package.json`
- `server.js`

## Create The Test Repo

1. Create a fresh GitHub repository.
2. Set the default branch to `main`.
3. Copy the contents of this sample directory into that repository root.
4. Push `main`.
5. Link that GitHub repository to a dedicated test app in Scalingo.
6. Enable auto-deploy on branch `main`.

## Configure Branch Protection

On GitHub, protect `main` and configure:

1. Require a pull request before merging.
2. Require status checks to pass before merging.
3. Select only `required-ci` as a required check.

Do not select `automerge` as a required check.

That mismatch is the core of the reproduction.

## Baseline Test On `main`

This verifies the repo and integration are healthy before triggering the bug.

1. Make a direct commit on `main` without the marker:

```bash
git checkout main
date >> smoke.txt
git add smoke.txt
git commit -m "smoke: green main push"
git push origin main
```

2. Expected result:
   - `required-ci` succeeds
   - `automerge` succeeds
   - Scalingo deploys successfully

## Reproduce The Original Bug With A New Branch

The auxiliary workflow fails only when the merged commit message contains `[trigger-hidden-fail]`.

1. Create a branch:

```bash
git checkout -b repro/hidden-check-failure
```

2. Add a commit with the marker in the commit message:

```bash
date >> repro.txt
git add repro.txt
git commit -m "repro: hidden main-only failure [trigger-hidden-fail]"
git push origin repro/hidden-check-failure
```

3. Open a pull request from `repro/hidden-check-failure` to `main`.
4. Wait for `required-ci` to pass on the pull request.
5. Merge with `Rebase and merge` or `Squash and merge`.

Use a merge strategy that preserves the marker in the final commit message on `main`.

## Expected Result Before This Fix

After the merge lands on `main`:

- `required-ci` is green
- `automerge` fails on the `main` push
- Scalingo receives the failing `check_run`
- Scalingo sets its commit status to `Aborted: Other job failed`

This is the incorrect behavior.

## Expected Result After This Fix

After the merge lands on `main`:

- `required-ci` is green
- `automerge` fails on the `main` push
- GitHub branch protection still considers the commit valid because `automerge` is not required
- Scalingo ignores the failing `automerge` check run
- Scalingo continues the deployment on `main`

This is the expected behavior.

## Useful Checks During Validation

On GitHub:

- open the commit page on `main`
- confirm `required-ci` is green
- confirm `automerge` is red
- confirm branch protection only requires `required-ci`

In `scalingo-github-hook` logs:

- before the fix, you should see the failed `check_run` lead to `Status failure received: marking the deployment as aborted`
- after the fix, the non-required context should be ignored

## Why This Reproduces `#698`

GitHub exposes both checks as check runs, but only one is part of branch protection.

Before the fix, the integration treated any failed GitHub check run as blocking.
After the fix, the integration filters GitHub checks to the required status-check contexts for the protected branch before deciding whether to abort the deployment.
