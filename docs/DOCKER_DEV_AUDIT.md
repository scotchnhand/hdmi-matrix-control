# Docker `dev` Image Audit

**Audit target:** `dev` at [`1c407a1b4a13b2ff0457ebd23a41de7320b710b2`](https://github.com/scotchnhand/hdmi-matrix-control/commit/1c407a1b4a13b2ff0457ebd23a41de7320b710b2), tagged `dev` on 2026-10-30.

This audit covers the Dockerized web app: its backend, frontend/PWA behavior, Compose definitions, and dev image workflow. Findings below are linked to project issues so they can be triaged and tracked.

## Summary

| Priority | Issue | Finding |
|---|---|---|
| High | [#75](https://github.com/scotchnhand/hdmi-matrix-control/issues/75) | Network settings changes leave the running client pointed at the old matrix IP. |
| High | [#76](https://github.com/scotchnhand/hdmi-matrix-control/issues/76) | Password changes leave the client using its old credentials. |
| High | [#77](https://github.com/scotchnhand/hdmi-matrix-control/issues/77) | Comparing `Origin` to `Host` does not block a same-host DNS-rebinding request. |
| Medium | [#78](https://github.com/scotchnhand/hdmi-matrix-control/issues/78) | The `dev` image is published without running the normal CI suite. |
| Medium | [#82](https://github.com/scotchnhand/hdmi-matrix-control/issues/82) | Reboot and factory reset are followed by an immediate state read that can fail after the command succeeds. |
| Low | [#79](https://github.com/scotchnhand/hdmi-matrix-control/issues/79) | An installed PWA can show the old shell on its first launch after a frontend-only `dev` update. |
| Low | [#80](https://github.com/scotchnhand/hdmi-matrix-control/issues/80) | The update checker checks stable GitHub releases and cannot report whether the mutable `dev` image changed. |
| Low | [#81](https://github.com/scotchnhand/hdmi-matrix-control/issues/81) | The ZimaOS Compose definition pins `latest`, with no option to install the `dev` image. |

All eight issues are open and attached to the repository's GitHub project.

## Findings

### High: The backend retains the old matrix address after applying network settings — [#75](https://github.com/scotchnhand/hdmi-matrix-control/issues/75)

The server constructs one `MatrixClient` from startup configuration. `set_network()` sends the new IP, mask, and gateway to the matrix but does not change the client's base URL or the server configuration. The shared POST handler then invalidates the state cache and immediately reads state through that same client. Once the matrix moves to its new IP, the read and all later polling continue to target the old address. The network form only shows its success toast after the POST and follow-up read both succeed.

Evidence: [`server.py`](https://github.com/scotchnhand/hdmi-matrix-control/blob/dev/hdmi-matrix-ui/backend/server.py#L37-L46), [`server.py`](https://github.com/scotchnhand/hdmi-matrix-control/blob/dev/hdmi-matrix-ui/backend/server.py#L221-L226), [`matrix_client.py`](https://github.com/scotchnhand/hdmi-matrix-control/blob/dev/hdmi-matrix-ui/backend/matrix_client.py#L108-L115), [`matrix_client.py`](https://github.com/scotchnhand/hdmi-matrix-control/blob/dev/hdmi-matrix-ui/backend/matrix_client.py#L310-L315), [`app.js`](https://github.com/scotchnhand/hdmi-matrix-control/blob/dev/hdmi-matrix-ui/frontend/app.js#L517-L526).

**Current workaround:** Update `MATRIX_HOST` in the container configuration to the new IP and restart the container.

### High: The backend keeps the old matrix credentials after changing the password — [#76](https://github.com/scotchnhand/hdmi-matrix-control/issues/76)

`set_password()` sends the new username and password to the matrix, but the `MatrixClient` keeps its original `username` and `password`. The next login or state read can therefore fail authentication. Docker environment settings also remain at their previous values until changed by the operator.

Evidence: [`matrix_client.py`](https://github.com/scotchnhand/hdmi-matrix-control/blob/dev/hdmi-matrix-ui/backend/matrix_client.py#L108-L115), [`matrix_client.py`](https://github.com/scotchnhand/hdmi-matrix-control/blob/dev/hdmi-matrix-ui/backend/matrix_client.py#L316-L322), [`app.js`](https://github.com/scotchnhand/hdmi-matrix-control/blob/dev/hdmi-matrix-ui/frontend/app.js#L528-L537).

**Current workaround:** Update `MATRIX_USERNAME` and `MATRIX_PASSWORD` in the container configuration and restart the container.

### High: The request-origin check can be satisfied by an attacker-controlled host — [#77](https://github.com/scotchnhand/hdmi-matrix-control/issues/77)

The server accepts a POST when the request's `Origin` authority equals its `Host` header. With DNS rebinding, both values can be the attacker's hostname while that hostname resolves to the Docker app; the check verifies equality but does not establish that the origin is trusted. The default `API_TOKEN` is empty, so the server-side token check is disabled unless the operator configures one. The existing tests cover a different origin and a mismatched port, but not a matching attacker-controlled hostname.

Evidence: [`server.py`](https://github.com/scotchnhand/hdmi-matrix-control/blob/dev/hdmi-matrix-ui/backend/server.py#L99-L116), [`config.py`](https://github.com/scotchnhand/hdmi-matrix-control/blob/dev/hdmi-matrix-ui/backend/config.py#L10-L19), [`docker-compose.yml`](https://github.com/scotchnhand/hdmi-matrix-control/blob/dev/hdmi-matrix-ui/docker-compose.yml#L15-L20), [current origin tests](https://github.com/scotchnhand/hdmi-matrix-control/blob/dev/hdmi-matrix-ui/backend/tests/test_server.py#L130-L155).

This is a code-level validation weakness. A live browser exploit was not exercised; browser local-network protections may affect exploitability in a particular browser and deployment.

### Medium: The mutable `dev` image can publish without CI checks — [#78](https://github.com/scotchnhand/hdmi-matrix-control/issues/78)

The `dev` workflow runs on every push to `dev` and its only job builds and pushes the multi-architecture image to the mutable `:dev` tag. The regular CI workflow is configured for pushes and pull requests targeting `main`, so failures in linting, Python tests, fixture parity, or other CI checks do not block publication from `dev`.

Evidence: [`dev-image.yml`](https://github.com/scotchnhand/hdmi-matrix-control/blob/dev/.github/workflows/dev-image.yml#L1-L31), [`ci.yml`](https://github.com/scotchnhand/hdmi-matrix-control/blob/dev/.github/workflows/ci.yml#L1-L26).

The image publish run for this audit target ([run 39358139510](https://github.com/scotchnhand/hdmi-matrix-control/actions/runs/39358139510)) succeeded, but it only demonstrates that the image build and publish completed; it did not run the normal CI suite.

### Medium: Reboot and factory reset are followed by an immediate state read — [#82](https://github.com/scotchnhand/hdmi-matrix-control/issues/82)

After every successful action, the POST handler invalidates the cache and synchronously reads matrix state before responding. Reboot can make the device unavailable during this read; factory reset can also change the device IP and credentials. If the read fails, the UI's success toast is skipped even though the command may already have been accepted. The effect depends on device firmware timing and was not reproduced against hardware.

Evidence: [`server.py`](https://github.com/scotchnhand/hdmi-matrix-control/blob/dev/hdmi-matrix-ui/backend/server.py#L205-L226), [`app.js`](https://github.com/scotchnhand/hdmi-matrix-control/blob/dev/hdmi-matrix-ui/frontend/app.js#L539-L555).

### Low: An installed PWA can briefly use a stale shell after a frontend-only dev update — [#79](https://github.com/scotchnhand/hdmi-matrix-control/issues/79)

The service-worker cache key is derived from a release version plus a manually bumped shell revision (`APP_VERSION = '1.3.1'`, revision `-2`). Its asset fetch handler returns a cached file immediately and refreshes the cache in the background. A frontend-only change that republishes `:dev` without changing `sw.js` leaves the installed worker on the same cache key, so the first load can render old cached JavaScript or styles before a later reload sees the refreshed asset.

Evidence: [`sw.js`](https://github.com/scotchnhand/hdmi-matrix-control/blob/dev/hdmi-matrix-ui/frontend/sw.js#L1-L13), [`sw.js`](https://github.com/scotchnhand/hdmi-matrix-control/blob/dev/hdmi-matrix-ui/frontend/sw.js#L31-L53).

This is a conditional dev-tag risk: it applies when frontend assets change but the service-worker script and cache revision do not.

### Low: The update checker does not check for a newer dev image — [#80](https://github.com/scotchnhand/hdmi-matrix-control/issues/80)

The UI reads its running application version and compares it with GitHub's `/releases/latest` endpoint. That endpoint reports stable release tags, not commits or changes to the mutable `dev` image. A user on the dev build can therefore see “You’re up to date” even when a newer dev image has been published.

Evidence: [`app.js`](https://github.com/scotchnhand/hdmi-matrix-control/blob/dev/hdmi-matrix-ui/frontend/app.js#L91-L141), [`version.py`](https://github.com/scotchnhand/hdmi-matrix-control/blob/dev/hdmi-matrix-ui/backend/version.py).

### Low: ZimaOS's Compose definition cannot select the dev image — [#81](https://github.com/scotchnhand/hdmi-matrix-control/issues/81)

The general Compose file exposes `HDMI_MATRIX_TAG`, but the ZimaOS/CasaOS definition hardcodes `ghcr.io/scotchnhand/hdmi-matrix-control:latest`. An operator importing that definition cannot select `dev` through a supported variable and may keep running the stable image while believing they installed the dev build.

Evidence: [general Compose](https://github.com/scotchnhand/hdmi-matrix-control/blob/dev/hdmi-matrix-ui/docker-compose.yml#L8-L20), [ZimaOS Compose](https://github.com/scotchnhand/hdmi-matrix-control/blob/dev/hdmi-matrix-ui/docker-compose.zimaos.yml#L7-L22).

## Inspection limits

- The audit inspected the source files and GitHub workflow metadata at the recorded `dev` commit.
- No matrix hardware or user-specific ZimaOS host was available, so device-timing behavior and the reported symptoms were not runtime-reproduced.
- Tests were not run; this report records static findings and does not claim test verification.
