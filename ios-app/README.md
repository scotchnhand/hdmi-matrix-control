# HDMI Matrix for iOS

A native SwiftUI client for the 4x2 HDMI matrix. Unlike the web app, it
needs **no backend**: a native app isn't subject to CORS, so it talks the
matrix's own protocol ([docs/PROTOCOL.md](../docs/PROTOCOL.md)) straight
over your LAN.

## Layout

```
MatrixKit/                Swift package: protocol client, models, mock
  Sources/MatrixKit/
    MatrixClient.swift     Swift port of matrix_client.py (serialized requests)
    MockMatrixClient.swift Swift port of mock_client.py (demo mode, previews)
    JSONP.swift            Parses the firmware's trailing-comma JSONP
    MatrixState.swift      Normalized state + validation rules
  Tests/MatrixKitTests/    Tests against the same captured device responses
                           as the Python suites
HDMIMatrix/               The app (SwiftUI, iOS 17+)
HDMIMatrix.xcodeproj
Info.plist                ATS exception for plain HTTP on the local network
```

## Running it

Open `HDMIMatrix.xcodeproj` in Xcode 16+ and run on a simulator or device.
The app starts in **demo mode** (a simulated matrix); open Settings (gear
icon), switch demo mode off, and enter your matrix's host (`matrix.local`
or its IP) and login. The password is stored in the Keychain.

On a real device iOS will ask for **Local Network** permission the first
time — allow it, or the app can't reach the matrix.

## Tests

The protocol layer is a plain Swift package, so it tests on macOS with no
simulator:

```bash
cd ios-app/MatrixKit && swift test
```

## Feature parity with the web app

Routing, output power, port renaming, EDID presets, ARC / audio
extraction, device info, network settings, password change, reboot, and
factory reset. State polls every 3 seconds, and every action re-reads the
device state afterwards, like the web API does.
