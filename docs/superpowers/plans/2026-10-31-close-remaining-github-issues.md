# Close Remaining GitHub Issues Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:executing-plans` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Resolve open GitHub issues #75–80 in one PR targeting `dev`, preserving the agreed issue order and host policy.

**Architecture:** Update the two mirrored Python matrix clients so accepted network/password changes affect the running client, and return explicit acknowledgements instead of performing a fragile immediate state read. Harden the web server's origin guard using private/loopback IP defaults and exact `TRUSTED_HOSTS` entries. Make dev publication depend on reusable CI, embed channel/revision metadata in images and the PWA cache key, and have the frontend compare dev builds with the latest successful image workflow run.

**Tech Stack:** Python standard library, `unittest`/pytest, vanilla JavaScript with Node's built-in test runner, Docker Buildx, GitHub Actions.

**Spec:** `docs/superpowers/specs/2026-10-31-close-remaining-github-issues-design.md`

## Global Constraints

- Keep the web backend dependency-free.
- Keep `hdmi-matrix-ui/backend/matrix_client.py` and `ha-hdmi-matrix/custom_components/hdmi_matrix/matrix_client.py` byte-identical.
- Do not change device command formats or captured protocol fixtures.
- Allow private and loopback IP literals by default; require exact hostname entries in comma-separated `TRUSTED_HOSTS`.
- Do not write UI-submitted device credentials into mounted configuration files or Docker settings.
- Work on the isolated branch based on `dev` and deliver all six issues in one PR targeting `dev`.
- Preserve the issue order: #75–77, then #78, then #79–80.
- Keep the repository's Conventional Commit format and squash-merge policy.

## Review Focus

1. A matching attacker-controlled hostname must fail while a private/loopback IP or exact configured hostname succeeds; pin these cases in Task 3.
2. Malformed, `null`, unsupported-scheme, mismatched-port, and IPv6 origins must fail safely; pin parser cases in Task 3.
3. A device command that is accepted before its connection changes must return success without an immediate state read, and a rejected command must leave runtime settings unchanged; pin both in Tasks 1–2.
4. A dev build with no revision, no successful publication run, or a GitHub API error must report the check as unavailable; pin these cases in Task 6.
5. A newer commit that has not completed image publication must not be reported as a published update; pin comparison against successful workflow runs in Task 6.

## File Map

- `hdmi-matrix-ui/backend/matrix_client.py` and `ha-hdmi-matrix/custom_components/hdmi_matrix/matrix_client.py`: synchronized runtime network/credential updates.
- `hdmi-matrix-ui/backend/config.py`, `config.example.json`, and `server.py`: trusted-host configuration, origin validation, acknowledgements, and build metadata.
- `hdmi-matrix-ui/backend/tests/`: HTTP, configuration, and client regression coverage.
- `ha-hdmi-matrix/tests/test_matrix_client.py`: matching runtime-setting regression coverage for the mirrored client.
- `hdmi-matrix-ui/frontend/index.html`, `app.js`, and `styles.css`: actionable setting notices and channel-aware update UI.
- `hdmi-matrix-ui/frontend/sw.js` and `Dockerfile`: revision-specific PWA shell cache in built images.
- `hdmi-matrix-ui/frontend/update-check.js` and `frontend/tests/update-check.test.js`: pure update decisions and Node built-in tests.
- `.github/workflows/ci.yml`, `dev-image.yml`, and `release.yml`: reusable checks, frontend/API smoke, and channel/revision build arguments.
- `docs/PROTOCOL.md` and `docs/DOCKER.md`: web API response contract, trusted-host configuration, and Docker restart/build guidance.

## Preflight

- Confirm the worktree is on `codex/fix-open-github-issues`, based on `dev` at `4ad25331385029c945d0450c656557adcd984bc3`, and contains no unrelated changes.
- Create separate virtual environments under `/private/tmp` and install each project's development requirements:

```bash
python3 -m venv /private/tmp/hdmi-web-venv
/private/tmp/hdmi-web-venv/bin/python -m pip install -r hdmi-matrix-ui/backend/requirements-dev.txt
python3 -m venv /private/tmp/hdmi-ha-venv
/private/tmp/hdmi-ha-venv/bin/python -m pip install -r ha-hdmi-matrix/requirements-dev.txt
```

- Confirm the HA interpreter is Python 3.14.2 or newer. Run both existing Python suites once before Task 1; record and resolve or isolate any baseline failures before implementation.
- Baseline on 2026-10-31: web backend passed 63 tests and 25 subtests on Python 3.15.0; Home Assistant passed 45 tests and 25 subtests on Python 3.14.8.
- Repository-wide Ruff and `node --check hdmi-matrix-ui/frontend/app.js` passed on the baseline. `actionlint` and Docker are unavailable locally. The local MatrixKit `swift test` baseline is blocked because the sandbox denies writes to Swift's default module cache under `/var/folders/.../C/clang/ModuleCache`, including when `TMPDIR` and the SwiftPM scratch path are redirected to `/private/tmp`. Reattempt if an allowed compiler cache override is found; otherwise require GitHub CI to validate workflows, build/smoke-test the image, and pass the `ios-unit` job before merge.

---

### Task 1: Apply accepted network and password changes to the running matrix clients

**Files:**
- Modify: `hdmi-matrix-ui/backend/matrix_client.py`
- Modify: `ha-hdmi-matrix/custom_components/hdmi_matrix/matrix_client.py`
- Test: `hdmi-matrix-ui/backend/tests/test_matrix_client.py`
- Test: `ha-hdmi-matrix/tests/test_matrix_client.py`

**Interfaces:**
- Consumes: Existing `MatrixClient.set_network(ip, mask, gw)` and `MatrixClient.set_password(user, password, group="0")` commands.
- Produces: After the wire request succeeds, `set_network` updates `self.base` to `http://<validated-ip>`; `set_password` updates `self.username` and `self.password` and clears `self._logged_in` so the next operation logs in with the new credentials. Exceptions leave the prior client state unchanged.

- [x] **Step 1: Write failing tests for successful client updates and failed commands**

In each client's test suite, cover the new base/credentials after a successful mocked `_request`; cover that an `_request` exception leaves the old values and login flag untouched. Keep the web and HA test cases equivalent.

- [x] **Step 2: Run the focused tests and confirm they fail**

Run from `hdmi-matrix-ui/backend`: `/private/tmp/hdmi-web-venv/bin/python -m pytest tests/test_matrix_client.py -k 'network_updates or password_updates' -v`
Expected: new assertions fail because the current methods do not update runtime settings.

Run from `ha-hdmi-matrix`: `/private/tmp/hdmi-ha-venv/bin/python -m pytest tests/test_matrix_client.py -k 'network_updates or password_updates' -v`
Expected: the equivalent assertions fail.

- [x] **Step 3: Implement post-acknowledgement runtime updates in both mirrored clients**

Update the network base only after the existing `ip.set` request returns successfully. Update credentials and clear the login flag only after the existing `system_set` registration request succeeds. Preserve validation and wire command strings.

- [x] **Step 4: Run focused client tests and protocol-copy consistency check**

Run `/private/tmp/hdmi-web-venv/bin/python -m pytest tests/test_matrix_client.py tests/test_protocol_fixtures.py -v` from `hdmi-matrix-ui/backend` and `/private/tmp/hdmi-ha-venv/bin/python -m pytest tests/test_matrix_client.py tests/test_protocol_fixtures.py -v` from `ha-hdmi-matrix`. From the repository root run `diff -u hdmi-matrix-ui/backend/matrix_client.py ha-hdmi-matrix/custom_components/hdmi_matrix/matrix_client.py`.
Expected: both suites pass and `diff` prints no differences.

- [x] **Step 5: Commit the client behavior**

```bash
git add hdmi-matrix-ui/backend/matrix_client.py ha-hdmi-matrix/custom_components/hdmi_matrix/matrix_client.py hdmi-matrix-ui/backend/tests/test_matrix_client.py ha-hdmi-matrix/tests/test_matrix_client.py
git commit -m "fix(matrix-client): apply accepted device setting changes"
```

### Task 2: Acknowledge device setting changes and guide Docker operators

**Files:**
- Modify: `hdmi-matrix-ui/backend/server.py`
- Test: `hdmi-matrix-ui/backend/tests/test_server.py`
- Modify: `hdmi-matrix-ui/frontend/index.html`
- Modify: `hdmi-matrix-ui/frontend/app.js`
- Modify: `hdmi-matrix-ui/frontend/styles.css`
- Modify: `docs/PROTOCOL.md`
- Modify: `docs/DOCKER.md`

**Interfaces:**
- Consumes: Task 1's successful runtime changes.
- Produces: `/api/network` returns `{"ok": true, "settings_changed": "network"}` and `/api/system/password` returns `{"ok": true, "settings_changed": "password"}` after command success. Neither route performs an immediate `state_cache.get()`. The frontend renders an inline notice instructing users to update the corresponding Docker environment variables or mounted `config.json`, then recreate the container. No password value appears in the response or notice.

- [x] **Step 1: Write failing HTTP-server tests for both acknowledgements**

Add tests named `test_network_change_acknowledges_without_followup_state_poll` and `test_password_change_acknowledges_without_followup_state_poll`. Patch the matrix action and `state_cache.get`, submit valid JSON through the real test HTTP server, and assert status 200, the response shape above, and that the cache read was not called. Assert that a failed matrix action remains an error.

- [x] **Step 2: Run the focused tests and confirm they fail**

Run from `hdmi-matrix-ui/backend`: `/private/tmp/hdmi-web-venv/bin/python -m pytest tests/test_server.py -k 'network_change_acknowledges or password_change_acknowledges' -v`.
Expected: the existing handler attempts the follow-up state read and returns an error.

- [x] **Step 3: Implement route-specific acknowledgements after successful commands**

Keep the existing state refresh for ordinary actions. Invalidate the cache after successful mutations, but return the specified acknowledgement for network/password changes without reading state. Do not return submitted credentials.

- [x] **Step 4: Add inline notices and user-facing documentation**

Add status regions for network and password results. On each response, show the relevant instruction: set `MATRIX_HOST` (or `matrix_host` in a mounted `config.json`) to the new IP, or update `MATRIX_USERNAME`/`MATRIX_PASSWORD` (or `matrix_username`/`matrix_password` in a mounted config), then recreate the container. Keep each notice visible until the page is reloaded. Update the `/api/*` response table in `docs/PROTOCOL.md` and configuration/change guidance in `docs/DOCKER.md`.

- [x] **Step 5: Run the web backend suite and inspect the rendered HTML hooks**

Run from `hdmi-matrix-ui/backend`: `/private/tmp/hdmi-web-venv/bin/python -m pytest tests/ -v`. Confirm `index.html` contains both notice regions and `app.js` uses `textContent` to display fixed guidance without reflecting the password.

- [x] **Step 6: Commit the acknowledgement and operator guidance**

```bash
git add hdmi-matrix-ui/backend/server.py hdmi-matrix-ui/backend/tests/test_server.py hdmi-matrix-ui/frontend/index.html hdmi-matrix-ui/frontend/app.js hdmi-matrix-ui/frontend/styles.css docs/PROTOCOL.md docs/DOCKER.md
git commit -m "fix(web-app): acknowledge device setting changes"
```

### Task 3: Reject untrusted hostnames on state-changing requests

**Files:**
- Modify: `hdmi-matrix-ui/backend/config.py`
- Modify: `hdmi-matrix-ui/backend/config.example.json`
- Modify: `hdmi-matrix-ui/backend/server.py`
- Test: `hdmi-matrix-ui/backend/tests/test_server.py`
- Create: `hdmi-matrix-ui/backend/tests/test_config.py`
- Modify: `docs/DOCKER.md`

**Interfaces:**
- Consumes: `config["trusted_hosts"]`, represented as an exact normalized hostname list from config JSON or comma-separated `TRUSTED_HOSTS`.
- Produces: `_origin_allowed(handler)` accepts a missing Origin for non-browser clients; otherwise it validates HTTP(S) origin syntax, compares normalized origin host and port with `Host`, and allows the host only if it is a private/loopback IP literal or an exact configured hostname.

- [x] **Step 1: Add failing config and origin-policy tests**

Add tests for comma-separated `TRUSTED_HOSTS`, empty entries, exact host matching, private IPv4, loopback IPv4/IPv6, untrusted hostname even when Origin equals Host, public IP rejection, `null`/malformed origins, port mismatch, and missing Origin. Include a trusted hostname success case.

- [x] **Step 2: Run the focused tests and confirm they fail**

Run from `hdmi-matrix-ui/backend`: `/private/tmp/hdmi-web-venv/bin/python -m pytest tests/test_config.py tests/test_server.py -k 'trusted_hosts or origin or host' -v`.
Expected: config parsing and trust-policy assertions fail against the raw Host/Origin equality check.

- [x] **Step 3: Parse `TRUSTED_HOSTS` and validate origins with standard-library address parsing**

Add `trusted_hosts` to defaults and the example JSON. Parse the environment value into trimmed, lowercase, nonempty hostnames. Use `ipaddress.ip_address` and `urllib.parse` without adding dependencies. Trust loopback, RFC1918 IPv4 (`10/8`, `172.16/12`, `192.168/16`), and IPv6 unique-local (`fc00::/7`) literals by default. Normalize hostnames and effective ports before comparing Origin with Host; reject userinfo, paths, queries, fragments, malformed ports, and unsupported schemes. Do not add wildcard hostname matching.

- [x] **Step 4: Run focused and complete web backend tests**

Run the focused command above, then `/private/tmp/hdmi-web-venv/bin/python -m pytest tests/ -v` from `hdmi-matrix-ui/backend`.
Expected: the DNS-rebinding regression is rejected and existing local-IP same-origin, JSON content type, API-token, and no-Origin behavior remain covered and passing.

- [x] **Step 5: Document hostname configuration and proxy behavior**

Document that private/loopback IP access needs no allowlist, while `.local` and reverse-proxy hostnames must be listed in `TRUSTED_HOSTS` as comma-separated exact names, without schemes or ports. Retain the instruction to pass the original Host header through a reverse proxy.

- [x] **Step 6: Commit the host policy**

```bash
git add hdmi-matrix-ui/backend/config.py hdmi-matrix-ui/backend/config.example.json hdmi-matrix-ui/backend/server.py hdmi-matrix-ui/backend/tests/test_config.py hdmi-matrix-ui/backend/tests/test_server.py docs/DOCKER.md
git commit -m "fix(web-app): reject untrusted request hostnames"
```

### Task 4: Gate dev image publication on the complete CI workflow

**Files:**
- Modify: `.github/workflows/ci.yml`
- Modify: `.github/workflows/dev-image.yml`

**Interfaces:**
- Consumes: reusable workflow `ci.yml` with `workflow_call` and read-only repository permissions.
- Produces: `dev-image.yml` runs the CI workflow on each `dev` push and publishes the multi-architecture image only when the CI job succeeds. Pull requests targeting `dev` receive normal CI checks.

- [x] **Step 1: Extend the Docker smoke check to cover the web-facing surface**

Update the existing `docker-build` smoke step to retry until the container is healthy, then verify successful responses from `/`, `/app.js`, `/styles.css`, `/manifest.json`, `/icons/icon.svg`, `/sw.js`, and `/api/version`. Parse the version JSON and assert it contains `version`.

- [x] **Step 2: Make the current CI workflow reusable and cover dev pull requests**

Add `workflow_call`, retain the `main` push trigger, and include `dev` in the pull request target branches. Do not add a direct `dev` push trigger that duplicates the reusable run. GitHub documents `needs` as supported on reusable-workflow caller jobs ([workflow reuse reference](https://docs.github.com/en/actions/reference/workflows-and-actions/reusing-workflow-configurations)).

- [x] **Step 3: Make dev publishing depend on reusable CI**

Add a `ci` job using `./.github/workflows/ci.yml`; set the publishing job's `needs: ci`. Keep package-write permission scoped to the image job. Add a concurrency group for the `dev` ref with cancellation so an older push cannot publish over a newer dev build.

- [x] **Step 4: Validate the workflow structure and smoke commands**

Run `actionlint .github/workflows/ci.yml .github/workflows/dev-image.yml` if installed. Otherwise verify the YAML through GitHub Actions on the draft PR. Review that the image job has no path that can run unless CI succeeds.

- [x] **Step 5: Commit the CI gate**

```bash
git add .github/workflows/ci.yml .github/workflows/dev-image.yml
git commit -m "ci: gate dev image publishing on full checks"
```

### Task 5: Embed build channel and revision in images and PWA cache identity

**Files:**
- Modify: `hdmi-matrix-ui/Dockerfile`
- Modify: `hdmi-matrix-ui/backend/server.py`
- Modify: `hdmi-matrix-ui/frontend/sw.js`
- Modify: `.github/workflows/ci.yml`
- Modify: `.github/workflows/dev-image.yml`
- Modify: `.github/workflows/release.yml`
- Test: `hdmi-matrix-ui/backend/tests/test_server.py`
- Modify: `docs/DOCKER.md`

**Interfaces:**
- Consumes: Docker build arguments `APP_BUILD_CHANNEL` and `APP_BUILD_REVISION`; defaults are `stable` and `local`.
- Produces: `/api/version` returns `version`, `channel`, and `revision`. Release builds pass `stable` and the checked-out commit SHA; dev builds pass `dev` and the push SHA. The built `sw.js` embeds the same revision in its shell cache key.

- [x] **Step 1: Add failing `/api/version` metadata assertions and a cache-key source assertion**

Add `test_version_endpoint_includes_build_channel_and_revision`, patching the server's build metadata to deterministic values. Add a check that the service-worker template includes a revision placeholder in `CACHE_NAME`.

- [x] **Step 2: Run the focused tests and confirm they fail**

Run from `hdmi-matrix-ui/backend`: `/private/tmp/hdmi-web-venv/bin/python -m pytest tests/test_server.py -k version_endpoint -v`.
Expected: the current endpoint returns only `version`.

- [x] **Step 3: Add build arguments, runtime metadata, and revision substitution**

Have the Dockerfile expose the build channel/revision to the backend and replace the service-worker placeholder at image build time. Include the revision in the cache name alongside `APP_VERSION`.

- [x] **Step 4: Pass channel and SHA from both publishing workflows**

Pass `APP_BUILD_CHANNEL=dev` and `${{ github.sha }}` in `dev-image.yml`. Pass `APP_BUILD_CHANNEL=stable` and `${{ github.sha }}` in the release image job. Keep version bumping under release-please. Extend the Docker smoke assertion in `ci.yml` to require nonempty `version`, `channel`, and `revision` fields.

- [x] **Step 5: Run endpoint and static checks, then document build channels**

Run the focused backend test and `/private/tmp/hdmi-web-venv/bin/python -m pytest tests/ -v`. Build locally with non-default channel/revision arguments if Docker is available and verify `/api/version` and `/sw.js` expose those values. Document that a revision-specific cache is built into each published image.

- [x] **Step 6: Commit image build metadata and cache identity**

```bash
git add hdmi-matrix-ui/Dockerfile hdmi-matrix-ui/backend/server.py hdmi-matrix-ui/frontend/sw.js .github/workflows/ci.yml .github/workflows/dev-image.yml .github/workflows/release.yml hdmi-matrix-ui/backend/tests/test_server.py docs/DOCKER.md
git commit -m "fix(web-app): identify image revisions in PWA cache"
```

### Task 6: Check updates against the running image's channel

**Files:**
- Create: `hdmi-matrix-ui/frontend/update-check.js`
- Create: `hdmi-matrix-ui/frontend/tests/update-check.test.js`
- Modify: `hdmi-matrix-ui/frontend/index.html`
- Modify: `hdmi-matrix-ui/frontend/app.js`
- Modify: `.github/workflows/ci.yml`

**Interfaces:**
- Consumes: `/api/version` fields `version`, `channel`, and `revision`.
- Produces: pure update comparison helpers used by the browser and Node tests; stable builds query the latest stable release; dev builds query the latest successful `dev-image.yml` run for branch `dev` and compare its `head_sha` with the running revision.

- [x] **Step 1: Write Node built-in tests for channel-specific update decisions**

Cover a newer stable release, an unchanged/stable running version, a newer successful dev image SHA, matching dev SHA, a newer `dev` branch commit without a successful image run, missing revision/run data, and GitHub API failure handling.

- [x] **Step 2: Run the frontend tests and confirm they fail**

Run from the repository root: `node --test hdmi-matrix-ui/frontend/tests/update-check.test.js`.
Expected: tests fail because the helper module does not exist.

- [x] **Step 3: Implement and use pure update-check helpers**

Add `evaluateStableUpdate(runningVersion, release)` and `evaluateDevUpdate(runningRevision, workflowRuns)` helpers. Each returns `{state, label, url}` where state is `available`, `current`, or `unavailable`. Load them before `app.js`. Route stable builds to `/releases/latest`; route dev builds to `/actions/workflows/dev-image.yml/runs?branch=dev&status=success&per_page=1`. GitHub's public workflow-runs API supports branch/status filters and returns each run's `head_sha` and `html_url` ([REST workflow-runs reference](https://docs.github.com/en/rest/actions/workflow-runs#list-workflow-runs-for-a-repository)). Link update notices to the release or successful workflow run. Use “check unavailable” for missing build metadata, absent successful runs, malformed responses, and API/network errors. Key dismissed notices by channel and version/revision.

- [x] **Step 4: Run Node update tests and served-asset smoke checks**

Run `node --test hdmi-matrix-ui/frontend/tests/update-check.test.js` and `node --check hdmi-matrix-ui/frontend/app.js`. Confirm `index.html` loads `update-check.js` before `app.js`; extend the Docker smoke in `ci.yml` to verify `/update-check.js` is served. Add `actions/setup-node@v7` with `node-version: "24"` and run the Node tests in CI ([official action](https://github.com/actions/setup-node)).

- [x] **Step 5: Commit channel-aware update checks**

```bash
git add hdmi-matrix-ui/frontend/update-check.js hdmi-matrix-ui/frontend/tests/update-check.test.js hdmi-matrix-ui/frontend/index.html hdmi-matrix-ui/frontend/app.js .github/workflows/ci.yml
git commit -m "fix(web-app): check updates for the active image channel"
```

### Task 7: Verify the integrated branch and prepare the draft PR

**Files:**
- Review: all files changed by Tasks 1–6.

- [x] **Step 1: Run web backend tests and lint**

Run `/private/tmp/hdmi-web-venv/bin/python -m pytest tests/ -v` from `hdmi-matrix-ui/backend`, then run `/private/tmp/hdmi-web-venv/bin/ruff check .` from the repository root.

- [x] **Step 2: Run Home Assistant tests and verify mirrored clients**

Run `/private/tmp/hdmi-ha-venv/bin/python -m pytest tests/ -v` from `ha-hdmi-matrix`, then run the protocol-client `diff` from Task 1.

- [x] **Step 3: Run frontend and MatrixKit checks**

Run the Node tests and syntax check from Task 6, then run `swift test` from `ios-app/MatrixKit` to confirm shared protocol fixtures remain compatible. The local Swift test was attempted with compiler and SwiftPM caches redirected under `/private/tmp`, but `sandbox-exec` failed with `Operation not permitted`. Record this as environment-only and require the CI `ios-unit` job to pass before merge.

- [x] **Step 4: Review complete diff and issue coverage**

Run `git diff --check` and inspect the full diff. Confirm each issue #75–80 has implementation, focused regression coverage, and documentation/workflow coverage as applicable. Confirm no credentials or unrelated checkout changes are included.

- [x] **Step 5: Commit the design and implementation plan**

```bash
git add docs/superpowers/specs/2026-10-31-close-remaining-github-issues-design.md docs/superpowers/plans/2026-10-31-close-remaining-github-issues.md
git commit -m "docs(plan): track remaining GitHub issue fixes"
```

- [ ] **Step 6: Push the feature branch and open a draft PR to `dev`**

Push `codex/fix-open-github-issues`; open a draft PR titled `fix(web-app): resolve remaining open Docker issues`, targeting `dev`, and include `Fixes #75`, `Fixes #76`, `Fixes #77`, `Fixes #78`, `Fixes #79`, and `Fixes #80`. Attach the PR to this Codex task.

- [ ] **Step 7: Publish the PR, wait for all checks, and merge to `dev`**

Mark the draft ready after the plan's checks are complete. Wait for the full CI, dev-image publish, and repository-required checks. Fix failures and wait for reruns to finish. Squash-merge only when all required checks pass. Confirm the merge commit is on `dev`, issues #75–80 are closed, and the dev image workflow succeeded for the merge SHA.
