# Design: close the remaining GitHub issues

**Status:** Approved by user for execution
**Date:** 2026-10-31
**Base:** `dev` at `4ad25331385029c945d0450c656557adcd984bc3` (merge of PR #85)

## Goal

Resolve every issue open in `scotchnhand/hdmi-matrix-control` after PR #85 merged. A fresh GitHub query on 2026-10-31 returned issues #75–80. Deliver the fixes together in one PR targeting `dev`.

The user chose this order:

1. Server behavior and origin security (#75–77).
2. CI-gated `dev` image publishing (#78).
3. Build metadata, PWA cache invalidation, and dev-channel update checks (#79–80).

The user also chose this host policy for #77: private and loopback IP literals are trusted by default; hostnames must be listed in `TRUSTED_HOSTS`.

## Issue inventory

| Issue | Open issue | Acceptance covered by this design |
|---|---|---|
| #75 | [Docker web app keeps using the old matrix IP after network settings change](https://github.com/scotchnhand/hdmi-matrix-control/issues/75) | The running client follows the accepted IP change; the UI tells operators how to update container configuration for restart. |
| #76 | [Changing the matrix password leaves the Docker app configured with old credentials](https://github.com/scotchnhand/hdmi-matrix-control/issues/76) | The running client uses accepted credentials; the UI tells operators how to update container configuration for restart without persisting the password. |
| #77 | [Same-origin Host/Origin comparison does not reject DNS-rebinding requests](https://github.com/scotchnhand/hdmi-matrix-control/issues/77) | Matching attacker-controlled hostnames are rejected unless exactly configured in `TRUSTED_HOSTS`; private/loopback IP literals remain usable by default. |
| #78 | [Run CI checks for dev before publishing the mutable Docker image](https://github.com/scotchnhand/hdmi-matrix-control/issues/78) | Dev commits receive the normal CI suite, publication depends on CI, and smoke checks cover frontend and backend responses. |
| #79 | [Mutable dev image can serve a stale PWA shell after a frontend-only update](https://github.com/scotchnhand/hdmi-matrix-control/issues/79) | Every built dev image uses its commit revision in the service-worker shell cache identity. |
| #80 | [Update check says the dev build is current without checking the dev image](https://github.com/scotchnhand/hdmi-matrix-control/issues/80) | Stable builds check stable releases; dev builds compare against the latest successfully published dev image revision. |

## Approaches

### State changes for #75–76

- **Acknowledge and warn only:** Stop the immediate state poll after a successful network/password command and tell the operator to update container settings. This is the smallest change, but leaves the running client pointed at stale connection settings until restart.
- **Update the runtime client and warn about restart:** After the matrix acknowledges the command, retarget the running client to the new IP or credentials, skip the immediate state poll, and show a persistent notice to update Docker settings before the next container recreation. This keeps the current session usable without silently rewriting mounted configuration or persisting secrets. **Recommended.**

### CI gate for #78

- **Trigger image publishing from a completed CI workflow:** This can avoid duplicated checks, but requires filtering workflow-run events and carefully checking the source event, branch, SHA, and permissions before publishing.
- **Call the normal CI workflow from `dev-image.yml`:** A `workflow_call` job runs the existing suite and the image job depends on it. PRs to `dev` also run CI directly. This makes the dependency and published SHA explicit and avoids a privileged `workflow_run` trigger. **Recommended.**

### Published dev revision for #79–80

- **Compare the running revision with the current `dev` branch head:** This is simple, but may advertise an image update before the corresponding build passes or publishes.
- **Compare with the latest successful `dev-image.yml` run:** This reports the revision of a successful image publication, matching the mutable tag more closely. It relies on the public GitHub Actions API, so a network/API failure must remain an unavailable result. **Recommended.**

These are implementation recommendations, not additional user-selected requirements. The user's explicit decisions remain the #77 host policy and the single-PR issue order above.

## Proposed behavior

### #75–76: network and password changes

- After a successful network change, update the running web client's target to the new IP. After a successful password change, update the running client credentials so later logins use the new values. Keep the two mirrored `matrix_client.py` files in sync.
- Do not immediately poll state after either command. The matrix may drop its connection or login session while applying the change, and that follow-up request must not turn a successful command into an ordinary failure response.
- Return a successful command acknowledgement and show a persistent, actionable notice in the web UI. The network notice tells Docker operators to update `MATRIX_HOST` or `matrix_host` in a mounted `config.json`, then recreate the container. The password notice tells them to update `MATRIX_USERNAME`/`MATRIX_PASSWORD` or `matrix_username`/`matrix_password` in a mounted config file, then recreate it. Do not write replacement credentials to a mounted config file or persist secrets from the UI.
- Document the restart requirement in the Docker guide. The running client can use the new settings until restart; container configuration remains the operator's source of truth.

### #77: reject untrusted hostnames

- Continue requiring JSON and matching same-origin `Origin` and `Host` values for browser control requests; continue allowing requests with no `Origin` for CLI and service clients.
- Parse and validate the origin and host instead of comparing raw `netloc` strings. Accept literal private or loopback IP hosts by default. Accept a hostname only when it exactly matches an entry in comma-separated `TRUSTED_HOSTS`.
- Keep port matching as part of the same-origin comparison. Reject malformed origins, `null` origins, and untrusted hostnames with 403.
- Document `TRUSTED_HOSTS` for `.local` names and reverse-proxy domains. Matching forwarded `Host` remains necessary when the app is behind a proxy.

### #78: gate publication on CI

- Make `ci.yml` callable with `workflow_call`, and run its existing checks for PRs targeting `dev` as well as `main`.
- Have the `dev-image.yml` push workflow call the reusable CI workflow first. Make image publication depend on that job succeeding. Keep the existing multi-architecture `:dev` publication.
- Extend the Docker smoke check to request the app shell and JavaScript/service-worker assets as well as the backend API, and check that the build metadata endpoint is served.

### #79–80: identify and check dev builds

- Add Docker build metadata for channel and revision, expose it from `/api/version`, and pass the dev commit SHA from the gated image workflow. Stable releases continue to use the stable release version and channel.
- Include the build revision in the service-worker shell cache key. Build images with their revision substituted into the service worker so every published dev image activates a distinct cache.
- Keep stable update checks against the latest stable GitHub release. For dev builds, check the latest successful `dev-image.yml` workflow run and compare its `head_sha` to the running image revision. This identifies a successfully published image rather than merely a commit that has not finished CI yet.
- Show an update notice with a link to the relevant release or dev workflow when an update exists. If GitHub cannot be reached, report the check as unavailable rather than current.

## Constraints and non-goals

- Keep the web backend dependency-free and keep the web and Home Assistant protocol client copies synchronized.
- Do not change device command formats or captured protocol fixtures.
- Update the `/api/*` behavior table in `docs/PROTOCOL.md` if network/password commands return acknowledgements instead of a fresh state payload.
- Do not auto-edit Docker Compose, environment files, or mounted credentials.
- Do not expand this change into unrelated roadmap work or currently closed issues.
- Preserve the user's untracked files in the original checkout; implementation remains in the isolated worktree.

## Verification expectations

- Add focused backend tests for trusted host parsing, allowed private/loopback IPs, trusted and untrusted hostnames, origin mismatch, missing origin, and network/password command acknowledgements without immediate state polling.
- Add focused client tests proving successful network/password commands update runtime connection settings, while failed commands do not.
- Add checks for build metadata, revision-specific service-worker cache identity, and channel-specific update behavior where the existing test setup supports them.
- Verify both protocol client copies remain identical. The dev-image CI run must demonstrate the frontend/backend smoke test, and image publication must occur only after the reusable CI workflow succeeds.
- Run the repository's relevant Python and Swift checks, frontend asset checks, and required CI. Do not claim hardware validation.

## Review focus

1. Is the selected behavior for #75–76 clear and safe for Docker users, including the restart notice and runtime reconnection?
2. Is exact-match `TRUSTED_HOSTS` plus private/loopback IP defaults the intended host policy?
3. Does using the latest successful dev-image workflow run satisfy #80's definition of a published build?
4. Is there any open issue beyond #75–80 that should be included in this PR?
