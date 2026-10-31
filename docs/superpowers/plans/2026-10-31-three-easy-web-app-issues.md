# Three Easy Web App Issues Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Resolve GitHub issues #80, #81, and #82 with small, focused changes to the web app's update status, ZimaOS instructions, and disruptive-action responses.

**Architecture:** Keep the update checker stable-release-only and say so clearly in its UI. Document how to select the existing `:dev` image in the imported ZimaOS app's Docker Image field and in the manual setup's Tag field. Let reboot and factory-reset POSTs return after the device accepts the command, without immediately polling a device that may be offline.

**Tech Stack:** Vanilla JavaScript, Python 3.11 standard library, `unittest` tests run with pytest, Markdown, Docker Compose documentation.

**Spec:** [Issue #80](https://github.com/scotchnhand/hdmi-matrix-control/issues/80), [Issue #81](https://github.com/scotchnhand/hdmi-matrix-control/issues/81), and [Issue #82](https://github.com/scotchnhand/hdmi-matrix-control/issues/82).

## Global Constraints

- `hdmi-matrix-ui/backend/` contains the standard-library Python server and its tests; `frontend/` contains the web app and assets.
- Name Python tests `test_*.py` and test functions `test_*`.
- Do not change device protocol commands; these issues concern the web app response, update messaging, and deployment guidance.
- Use a Conventional Commit title for the PR and wait for CI to pass before merging.
- Target `dev`, as requested for this work.

## Review Focus

- Reboot accepted while the matrix goes offline: return HTTP 200 with `{"ok": true}` and do not call `state_cache.get()` (Task 3 regression test).
- Factory reset accepted while the matrix goes offline: return HTTP 200 with `{"ok": true}` and do not call `state_cache.get()` (Task 3 regression test).
- Ordinary actions still refresh cached state after success (Task 3 existing `test_route_command_updates_state`).
- No newer stable release while a newer mutable dev image may exist: the status must say the check does not track dev images (Task 2 manual UI-copy verification).
- ZimaOS import flow selecting `:dev`: instructions must name the Docker Image field and its full `:dev` value; manual setup must identify the **Tag** field (Task 1 documentation verification).

---

### Task 1: Document the ZimaOS dev image tag (Issue #81)

**Files:**
- Modify: `docs/DOCKER.md` in the ZimaOS import, manual setup, and update instructions.

**Interfaces:**
- Consumes: the imported Compose app's Docker Image value and the manual setup's ZimaOS custom-app **Tag** field.
- Produces: explicit steps to change the imported app's Docker Image to `ghcr.io/scotchnhand/hdmi-matrix-control:dev`, and to set **Tag** to `dev` in manual setup and updates.

- [x] **Step 1: Update the import instructions** to tell users to change the imported **Docker Image** value to `ghcr.io/scotchnhand/hdmi-matrix-control:dev` before installing; retain `:latest` as the default.
- [x] **Step 2: Update the manual setup and update examples** so the **Tag** field lists `latest`, `dev`, or an exact release tag.
- [x] **Step 3: Verify the guide** by checking that the imported image field and manual Tag field both provide the documented dev option.
- [x] **Step 4: Run `git diff --check`** and confirm no whitespace errors.
- [x] **Step 5: Commit** with `docs(zimaos): document dev image tag selection`.

### Task 2: Clarify the stable-release update status (Issue #80)

**Files:**
- Modify: `hdmi-matrix-ui/frontend/app.js` in `checkForUpdates()`.

**Interfaces:**
- Consumes: the existing latest-stable-release comparison.
- Produces: status copy that does not claim the mutable dev image is current.

- [x] **Step 1: Change the no-newer-release status** to `No newer stable release found. This check does not track dev images.`
- [x] **Step 2: Run `node --check hdmi-matrix-ui/frontend/app.js`** and confirm JavaScript parses.
- [x] **Step 3: Review the no-update branch** to confirm the dev-image limitation is visible whenever the stable-release comparison finds no newer version.
- [x] **Step 4: Run `git diff --check`** and confirm no whitespace errors.
- [x] **Step 5: Commit** with `fix(web-app): clarify stable release update status`.

### Task 3: Return promptly after reboot and factory reset (Issue #82)

**Files:**
- Modify: `hdmi-matrix-ui/backend/server.py` in `Handler.do_POST()`.
- Test: `hdmi-matrix-ui/backend/tests/test_server.py`.

**Interfaces:**
- Consumes: the existing POST route table, `StateCache.invalidate()`, and `Handler._handle()`.
- Produces: successful reboot and factory-reset responses as `{"ok": true}` without a follow-up `state_cache.get()`; other successful actions continue returning refreshed state.

- [x] **Step 1: Add `test_reboot_returns_success_without_followup_state_poll`**. Patch `server_module.client.reboot` and make `server_module.state_cache.get` raise `server_module.MatrixError("offline")`; assert status is 200, response is `{"ok": true}`, reboot is called once, and the state read is never called.
- [x] **Step 2: Add `test_factory_reset_returns_success_without_followup_state_poll`** patching `server_module.client.factory_reset` and using the same failing state-read side effect.
- [x] **Step 3: Run the two new tests** from `hdmi-matrix-ui/backend/` with `pytest tests/test_server.py -k 'reboot_returns_success_without_followup_state_poll or factory_reset_returns_success_without_followup_state_poll' -v`; confirm they fail because the current handler polls after the command.
- [x] **Step 4: Update the POST handler** to invalidate state after every successful command, return `{"ok": true}` for `/api/system/reboot` and `/api/system/factory-reset`, and call `state_cache.get()` for other routes.
- [x] **Step 5: Run the full backend suite** from `hdmi-matrix-ui/backend/` with `pytest tests/ -v`; confirm all tests pass, including `test_route_command_updates_state`.
- [x] **Step 6: Commit** with `fix(web-app): return promptly after reboot and reset`.

### Integration and delivery

- [x] Run `ruff check .` from the repository root and `git diff --check`.
- [ ] Push the feature branch and open a draft PR to `dev` titled `fix(web-app): resolve three web app issues`, linking #80, #81, and #82.
- [ ] Include the captured UI screenshot showing the stable-release-only update status in the PR description.
- [ ] Publish the draft PR. Since `.github/workflows/ci.yml` only auto-triggers for `main`, use GitHub Actions **Run workflow** for `CI` on ref `codex/fix-three-easy-issues` (the existing workflow supports `workflow_dispatch`); wait for the run to finish successfully.
- [ ] After CI passes, squash-merge the PR into `dev`.
