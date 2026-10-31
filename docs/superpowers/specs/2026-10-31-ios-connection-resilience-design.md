# iOS Connection Resilience Design

**Status:** Implemented in PR #97. Written after the fact; the decisions below were made during troubleshooting, not in a prior brainstorming session.

## Problem

The matrix's embedded HTTP server is slow and sometimes drops connections. In the iOS app this showed up as frequent, confusing "Connection lost" banners, and a first-launch connecting screen that never explained a delay.

## Goals

- A single slow or dropped response does not flip the UI to "Connection lost".
- A wrong host address fails fast and offers a way to fix it.
- Error text says what happened and what to do, instead of raw `URLSession` messages.

## Non-goals

- Reducing poll frequency or the three-request cost of a state read.
- Retrying commands. The device's server is fragile and a repeated command may not be safe.
- Caching state across launches, or detecting a missing Wi-Fi connection up front (see Follow-ups).

## Decisions

- **Failure threshold.** `MatrixStore` reports "Connection lost" only after 3 consecutive failed polls (`failuresBeforeLost`), about 9 seconds at the 3-second poll interval. It keeps the last known state in the meantime.
- **Read retry.** `MatrixClient` retries a GET once on `networkConnectionLost`, `timedOut`, or `cannotConnectToHost`, because the device may close an idle keep-alive connection. This applies only after the first request has succeeded.
- **First-contact timeout.** Until a request succeeds, each request uses a 2-second timeout (`firstContactTimeout`, capped at the normal timeout). The normal timeout is 4 seconds. Per-request `timeoutInterval` overrides the session configuration; this was checked against an unroutable address.
- **Messages.** `MatrixClient.describe` maps common `URLError` codes to plain-language text.
- **Connecting screen.** After the first failed attempt it shows the reason, the attempt count, and a Connection Settings button (`MatrixStore.lastError`, `consecutiveFailures`).

## Constraints

- Avoid rapid or concurrent real-device requests (see `AGENTS.md`). The retry adds at most one extra read per failed read.
- The Python clients retry refused command connections (`aa543a4`); the Swift client deliberately does not retry commands. Revisit if the protocol fixtures start covering retry behavior.

## Testing

`MatrixClientResilienceTests` covers the first-contact timeout, the single read retry, no retry for commands, and the error messages, using an injected transport. The failure threshold lives in the app target's `MatrixStore` and has no unit test yet.

## Follow-ups

- [#95](https://github.com/scotchnhand/hdmi-matrix-control/issues/95): show last known state while reconnecting.
- [#96](https://github.com/scotchnhand/hdmi-matrix-control/issues/96): detect missing Wi-Fi before contacting the matrix.
- Not yet verified against real hardware.
