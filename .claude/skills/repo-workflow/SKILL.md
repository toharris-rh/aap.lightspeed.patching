---
name: repo-workflow
description: >-
  Git and GitHub procedures for aap.lightspeed.patching — how to commit, push,
  open a PR, and merge changes when `main` is a protected branch. Covers the
  commit-on-main recovery flow, commit/PR message conventions, CHANGELOG
  discipline, and the one-concern-per-PR rule.
  TRIGGER when the user asks to commit, push, open/create a PR, merge, "ship it",
  land a change, branch, or when a push to main is rejected (GH006 / protected
  branch / "Changes must be made through a pull request").
  SKIP for questions about what the code does, AAP CaC behavior, ServiceNow
  logic, or environment/credential setup — use the relevant other skill.
---

# Repo Workflow — aap.lightspeed.patching

How to land changes in this repo. The golden rule: **`main` is a protected
branch — you cannot push to it directly.** Every change goes through a pull
request, even a one-line fix.

## The standard flow (do this from the start)

Work on a feature branch, never commit straight to `main`:

```bash
git checkout -b <type>/<short-kebab-desc>     # e.g. fix/eda-rulebook-filename-ref
# ...make edits, update CHANGELOG.md...
git add <specific files>                      # never `git add -A` blindly — audit for secrets
git commit -m "..."                           # see message conventions below
git push -u origin <branch>
gh pr create --repo toharris-rh/aap.lightspeed.patching --base main --head <branch> \
  --title "..." --body "..."
```

Branch name prefixes seen in this repo: `fix/`, `feature/`. Match that.

## Recovery: you already committed on `main`

If you committed to local `main` and the push was rejected with:

```
remote: error: GH006: Protected branch update failed for refs/heads/main.
remote: - Changes must be made through a pull request.
```

The commit is fine — it's just on the wrong branch. Move it to a new branch and
reset local `main` back to the remote:

```bash
git branch <type>/<desc>          # create branch pointing at your new commit
git reset --hard origin/main      # rewind local main to match remote (commit is safe on the branch)
git checkout <type>/<desc>        # switch to the branch that has your commit
git push -u origin <type>/<desc>  # push the branch
gh pr create ...                  # open the PR
```

This is non-destructive: `git branch` captures the commit before the reset, so
nothing is lost.

## Commit message conventions

- Imperative subject line, ~50 chars, no trailing period.
- Body explains the **why**, wrapped ~72 chars.
- End every commit with the co-author trailer:

  ```
  Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
  ```

## PR conventions

- `--base main`, head is your feature branch.
- Body: a `## Summary` of what and why, plus the concrete change list.
- End the PR body with:

  ```
  🤖 Generated with [Claude Code](https://claude.com/claude-code)
  ```
- Repo slug for `gh`: `toharris-rh/aap.lightspeed.patching`.

## Merging

Merges complete on GitHub. Past PRs use **merge commits** (`Merge pull request
#N from toharris-rh/<branch>`), so keep that style. **Always delete the branch
on merge** with `--delete-branch` — it removes the remote branch and prunes the
local one in the same step, so merged branches don't pile up:

```bash
gh pr merge <N> --repo toharris-rh/aap.lightspeed.patching --merge --delete-branch
```

Then sync local `main`:

```bash
git checkout main && git pull --ff-only origin main
```

**Verify CI is actually green before merging — `Lint` is NOT a required
status check.** A failing `Lint` run does not block merge, so a red lint can
ride along silently (this is how `ansible-lint` stayed broken on `main` across
several PRs — see issue #58). Auto-merge succeeding is *not* evidence the
checks passed. Always confirm explicitly:

```bash
gh pr checks <N> --repo toharris-rh/aap.lightspeed.patching
```

All jobs should read `pass` before you merge. A common offline-lint failure is
`syntax-check[unknown-module]` for a certified module — fix it by adding the
module to `mock_modules` in `.ansible-lint`, not by skipping (syntax-check is
unskippable).

Only merge when the user asks, or when a fix is verified. After a merge that
touches CaC, the EDA project in AAP syncs rulebooks from `main` — so merge
before relying on a rulebook change being live (the activation *definitions* in
`aap_config/files/` are read locally and don't need a merge to test).

## Branch cleanup

Delete every branch as soon as its PR merges (use `--delete-branch` above). To
sweep up stale merged branches that slipped through:

```bash
git fetch --prune origin                              # drop local refs to deleted remotes
git branch --merged origin/main | grep -v ' main$'    # local branches safe to delete
git branch -r --merged origin/main | grep -v 'origin/main$'  # remote branches safe to delete
# delete remote:  git push origin --delete <branch>
# delete local:   git branch -d <branch>
```

Never delete a branch whose PR is still open (e.g. the one you're working on).
After a clean repo, only `main` plus any in-flight feature branches should
remain.

## Non-negotiables (also in CLAUDE.md)

- **Open a GitHub Issue before fixing** (document-before-fixing) and **label
  every new issue** — `gh label list --repo toharris-rh/aap.lightspeed.patching`,
  apply all that fit.
- **One concern per PR** — group by shared root cause. Would you revert these
  together? If not, split them.
- **Update `CHANGELOG.md`** in the same commit — an entry under Added / Changed /
  Fixed / Removed with a `(YYYY-MM-DD)` date heading.
- **Audit every diff for customer data** before committing — no customer names,
  RHDP URLs, cluster/instance IDs, passwords, or tokens. `docs/dev-environment.sh`
  is gitignored and must never be staged.
- **Commit/push only when asked.** Don't push on your own initiative.
