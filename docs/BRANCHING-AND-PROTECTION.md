# Branching and GitHub protection

This is the repository's agent-agnostic collaboration contract. It applies
equally to human contributors, IDE automations, CI jobs, and AI coding agents.
No contributor is expected to use a particular assistant or Git client.

## Branch roles

| Branch | Role | Allowed pull request sources |
| --- | --- | --- |
| `main` | Protected, release-ready production line | `dev`, `release/*`, or urgent `hotfix/*` |
| `dev` | Protected shared-integration line | `feature/*`, `fix/*`, `docs/*`, `test/*`, `refactor/*`, `chore/*`, and other short-lived work branches |

Normal flow:

```text
work branch -> PR -> dev -> PR -> main
                           ^
                 hotfix/* -+
```

Use a `hotfix/*` branch only for an urgent production repair. After it is
merged to `main`, merge or cherry-pick the same fix into `dev` so the branches
do not drift.

## Work branch rules

- Start normal work from the latest `dev`.
- Use a short, descriptive name such as
  `feature/watch-connectivity`, `fix/edid-retry`, or `docs/deployment-guide`.
- Keep one cohesive change per branch and PR.
- Rebase or update the branch through the normal GitHub PR workflow when the
  target branch moves; never force-push a protected branch.
- Prefer squash merging to keep the protected branches easy to audit.

## Required GitHub checks

The following check contexts are stable and should be required on both
protected branches:

- `CI / Required checks`
- `Branch policy / Branch routing`
- `CodeQL / Analyze (Python)`
- `Markdown / Markdown lint`

`CI / Required checks` is an aggregate job. It fails if any of the individual
lint, test, protocol-consistency, Home Assistant manifest, or frontend-smoke
jobs fail. This keeps branch protection stable even when CI gains another
implementation job.

## Protection settings for `main` and `dev`

Configure the same baseline on both branches:

- Require a pull request before merging.
- Require at least one approving review.
- Dismiss stale approvals when new commits are pushed.
- Require all review conversations to be resolved.
- Require the four status checks listed above.
- Require branches to be up to date before merging.
- Require linear history and use squash merge.
- Block force-pushes and branch deletion.
- Do not allow administrators to bypass these rules.
- Enable automatic head-branch deletion after merge.

For `main`, additionally require that the PR comes from `dev`, `release/*`,
or `hotfix/*`; the `Branch policy / Branch routing` check enforces this. For
`dev`, allow normal short-lived work branches but do not allow `main` or `dev`
as PR heads.

## Bootstrap the missing `dev` branch

If the remote repository does not yet have `dev`, an administrator should
create it from the current `main` tip before enabling its protection:

```bash
git fetch origin main
git switch -c dev --track origin/main
git push -u origin dev
```

If local work is in progress, perform this from a clean checkout or use the
GitHub UI's **New branch** action from `main`.

## GitHub UI checklist

For each branch, open **Settings -> Branches -> Add branch protection rule** and
enter the branch name exactly (`main`, then `dev`). Enable the settings above,
select the required checks after the first workflow run has completed, and
save the rule. Confirm that a direct push and a PR with a failing required
check are both rejected.

The repository's connected GitHub integration can create and inspect PRs, but
it does not have administration permission to read or write branch protection
rules. Applying the settings is therefore an owner/admin action.
