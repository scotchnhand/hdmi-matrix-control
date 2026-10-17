# HDMI Matrix Apple clients

A native SwiftUI client for the 4x2 HDMI matrix. Unlike the web app, it
needs **no backend**: a native app isn't subject to CORS, so it talks the
matrix's own protocol ([docs/PROTOCOL.md](../docs/PROTOCOL.md)) straight
over your LAN.

## Platform status

- **iOS / iPadOS:** the current SwiftUI application target, using iOS 26 and
  Liquid Glass.
- **macOS:** not yet an application target. The shared `MatrixKit` package
  supports macOS 14+ and is testable on a Mac, but the current Xcode project
  does not build a Mac `.app`.
- **Intel and Apple silicon:** the planned Mac app will be a Universal 2
  binary containing `x86_64` and `arm64`. This is not implemented yet.

See [Apple platform status](../docs/APPLE-PLATFORMS.md) for the build plan,
architecture checks, and current validation boundaries.

## Layout

```
MatrixKit/                Cross-platform Swift package: protocol client, models, mock
  Sources/MatrixKit/
    MatrixClient.swift     Swift port of matrix_client.py (serialized requests)
    MockMatrixClient.swift Swift port of mock_client.py (demo mode, previews)
    JSONP.swift            Parses the firmware's trailing-comma JSONP
    MatrixState.swift      Normalized state + validation rules
  Tests/MatrixKitTests/    Tests against the same captured device responses
                           as the Python suites
HDMIMatrix/               Current iOS app (SwiftUI, iOS 26+, Liquid Glass)
HDMIMatrix.xcodeproj
Info.plist                ATS exception for plain HTTP on the local network
scripts/generate_icons.swift
                          Renders the app icon (standard / dark / tinted)
                          and the in-app artwork
```

## Design

Built for iOS 26's Liquid Glass. A floating glass tab bar holds three tabs:
**Routing** (output cards and audio), **Inputs** (names and EDID), and
**Device** (connection, network, password, reboot / reset). A glass
accessory above the tab bar shows connection status. Content sits in glass
cards over a backdrop taken from the app icon. Output 1 is always blue and
output 2 always green, matching the routes in the icon.

The icon shows what the app does: four inputs, two screens, and two
crossing routes. To change it, edit `scripts/generate_icons.swift` and run
it from the repo root:

```bash
swift ios-app/scripts/generate_icons.swift
```

## Running it

Open `HDMIMatrix.xcodeproj` in Xcode 26+ and run on a simulator or device.
The app starts in **demo mode** (a simulated matrix); open the **Device** tab →
the connection row, switch demo mode off, and enter your matrix's host (`matrix.local`
or its IP) and login. The password is stored in the Keychain.

On a real device iOS will ask for **Local Network** permission the first
time — allow it, or the app can't reach the matrix.

## User guide

**[docs/ios-guide/](../docs/ios-guide/README.md)** walks through every
screen with screenshots, from installing and connecting through routing,
EDID, and troubleshooting.

## Tests

The protocol layer is a plain Swift package, so it tests on macOS with no
simulator. This validates the shared client only, not a macOS application:

```bash
cd ios-app/MatrixKit && swift test
```

The app has XCUITests (`HDMIMatrixUITests/`) that drive every feature
against the demo matrix. The app launches with `-ui-testing`, which forces
demo mode with throwaway settings. Run them with ⌘U in Xcode, or:

```bash
cd ios-app && xcodebuild test -project HDMIMatrix.xcodeproj -scheme HDMIMatrix \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

`testWalkthrough` also captures the user guide's screenshots. After a UI
change, refresh them with `ios-app/scripts/capture_screenshots.sh`. CI
runs both suites on every PR and uploads the walkthrough screenshots as
an `ios-ui-screenshots` artifact.

## Feature parity with the web app

Routing, output power, port renaming, EDID presets, ARC / audio
extraction, device info, network settings, password change, reboot, and
factory reset. State polls every 3 seconds, and every action re-reads the
device state afterwards, like the web API does.
