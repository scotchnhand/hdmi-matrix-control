# Agent-neutral repository contract

This repository is designed to be worked on by people, scripts, and AI agents
without depending on a particular vendor, model, editor, or automation tool.
The files in the repository are the source of truth; chat context and local
agent memory are not.

## Work lanes

- `main` is the protected, release-ready branch.
- `dev` is the protected shared-integration branch.
- Short-lived work branches are created from `dev` and use a neutral prefix
  such as `feature/`, `fix/`, `docs/`, `test/`, `refactor/`, or `chore/`.
- `hotfix/*` may branch from `main` when production needs an urgent repair.
- Work branches merge into `dev` through pull requests. Only `dev` (or an
  approved `hotfix/*` branch) may merge into `main`.

No contributor or agent pushes directly to `main` or `dev`. The GitHub branch
rules described in [docs/BRANCHING-AND-PROTECTION.md](docs/BRANCHING-AND-PROTECTION.md)
are the enforcement layer for this policy.

## Required behavior for every change

1. Read the relevant README, `docs/DEVELOPMENT.md`, and the current issue or
   task before editing.
2. Inspect the working tree first and preserve unrelated user changes.
3. Keep changes focused. Do not rewrite or delete unrelated work.
4. Add or update tests for behavior changes. Never claim hardware validation
   when only mocks or fixtures were used.
5. Run the smallest relevant local checks, then report exactly what passed and
   what was not run.
6. Update user-facing documentation when behavior, setup, deployment, or
   support changes.
7. Never commit credentials, private keys, local configuration, or generated
   build artifacts.
8. Use the pull request template and identify the target branch explicitly.

For Markdown-only changes, run
`npx --yes markdownlint-cli2 --config .markdownlint-cli2.jsonc '**/*.md'`.
The same check runs automatically in GitHub Actions.

## Project-specific invariants

- The web and Home Assistant copies of `matrix_client.py` must remain
  byte-for-byte identical; CI enforces this.
- The application is local-first. Do not add a cloud dependency or transmit
  matrix credentials to a third party without an explicit design decision.
- Docker, Portainer, CasaOS, and ZimaOS deployment changes must update
  `docs/DOCKER.md` and the relevant compose template.
- Apple platform changes must update `docs/APPLE-PLATFORMS.md` when setup or
  supported-platform behavior changes.

## Completion standard

A change is ready for review only when the working tree is clean except for
intentional work, the relevant tests and checks have been run, documentation
is current, and the PR describes limitations or unverified areas clearly.
