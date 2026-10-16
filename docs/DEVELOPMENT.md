# Development guide

## Repo layout

```
hdmi-matrix-ui/      Local web app (Python stdlib backend + PWA frontend)
ha-hdmi-matrix/       Home Assistant custom integration
docs/                 This file, PROTOCOL.md, ROADMAP.md
.github/              CI workflows, issue/PR templates, Dependabot config
pyproject.toml        Shared ruff config (repo-wide)
```

Each subproject is independently runnable and independently tested — see
their own READMEs ([hdmi-matrix-ui](../hdmi-matrix-ui/README.md),
[ha-hdmi-matrix](../ha-hdmi-matrix/README.md)) for how to run them.

## Setup

```bash
git clone <this repo>
cd matrix

# Per subproject you're working on:
cd hdmi-matrix-ui && pip install -r requirements-dev.txt
cd ../ha-hdmi-matrix && pip install -r requirements-dev.txt
```

No runtime dependencies anywhere (`hdmi-matrix-ui/backend` is pure stdlib
on purpose); `requirements-dev.txt` is test/lint tooling only.

## Running tests

```bash
# From either subproject directory:
pytest tests/ -v
pytest tests/ --cov=. --cov-report=term-missing   # with coverage

# Lint (whole repo, from the root):
ruff check .
ruff check --fix .   # auto-fix what's fixable
```

Tests never touch the real matrix or a real Home Assistant instance:

- `hdmi-matrix-ui/backend/tests/test_matrix_client.py` — protocol parsing
  and command validation, against real captured device responses, with
  `MatrixClient._request` mocked out
- `hdmi-matrix-ui/backend/tests/test_server.py` — runs the actual stdlib
  HTTP server in a background thread against `mock_client.MockMatrixClient`
  and drives it over real HTTP
- `ha-hdmi-matrix/tests/test_matrix_client.py` — same protocol-layer
  coverage for that copy of the client

If you're testing against the **real hardware**, read the "known hardware
quirk" note in [docs/PROTOCOL.md](PROTOCOL.md) first — it can lock up
under rapid requests, and a power cycle is the recovery.

## Making a change

1. Branch off `main`: `git checkout -b <type>/<short-description>` (e.g.
   `fix/edid-select-reverts-on-error`, `feat/multi-matrix-support`).
2. If you touch `matrix_client.py`, **update both copies**
   (`hdmi-matrix-ui/backend/` and
   `ha-hdmi-matrix/custom_components/hdmi_matrix/`) — CI's
   `protocol-consistency` job fails the build otherwise. See
   [ROADMAP.md](ROADMAP.md) for the plan to stop needing two copies.
3. Add/update tests for the change. A bug fix should come with a test
   that fails without the fix.
4. `ruff check .` and `pytest tests/ -v` in whatever subproject(s) you
   touched.
5. If this closes or adds a planned item, update
   [ROADMAP.md](ROADMAP.md) in the same PR.
6. Open a PR against `main` — the template will prompt for what changed,
   why, and how it was tested.

## Commit messages

[Conventional Commits](https://www.conventionalcommits.org/):

```
<type>(<scope>): <short summary>

<body, if the summary needs more context>
```

- `type`: `feat`, `fix`, `docs`, `test`, `refactor`, `chore`, `ci`
- `scope` (optional): `web-app`, `ha-integration`, `protocol`, `ci`, `docs`

Examples:

```
fix(web-app): revert EDID select on failed request

feat(ha-integration): add reboot button entity

docs(protocol): document the audio_set dec= field name mismatch
```

Keep the summary line imperative and under ~72 characters; put the "why"
in the body if it's not obvious from the summary alone.

## Filing bugs / feature requests

Use the issue templates (Issues → New Issue) — they ask for the one or
two things that make a matrix-protocol bug report actually actionable
(which component, matrix firmware version, logs). "Questions /
discussion" has its own link in the template picker for anything that
isn't yet a concrete bug or request.
