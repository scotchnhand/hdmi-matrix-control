# Apple platform apps

The native client work lives under [`ios-app/`](../ios-app/). It is organized
around one Foundation-only `MatrixKit` layer plus SwiftUI app targets for iOS,
macOS, tvOS, and watchOS. The clients connect to the local web container's API
(for example `http://192.168.1.20:8765`) rather than duplicating the matrix's
undocumented protocol.

## Current scope

- `MatrixKit`: Codable state models and an actor-isolated HTTP client for the
  existing `/api/*` endpoints.
- iOS: routing, output power, audio source, connection URL, refresh, and
  persistent appearance selection.
- macOS: the same control surface in a resizable window.
- tvOS: a focus-friendly routing surface for a living-room remote.
- watchOS: a compact status/routing surface plus `WatchConnectivity` command
  and state relay through the iPhone app.

These are deliberately early native targets: they establish the shared API,
theme preference, and cross-device boundary while leaving signing, icons, and
App Store metadata to the Xcode project that will be used for distribution.

## Xcode setup

1. Open [`ios-app/MatrixKit/Package.swift`](../ios-app/MatrixKit/Package.swift)
   in Xcode to build and test the shared client layer.
2. Create an Xcode workspace/project with app targets named `MatrixControl`
   (iOS), `MatrixControlMac` (macOS), `MatrixControlTV` (tvOS), and
   `MatrixControlWatch` (watchOS).
3. Add the Swift sources under `ios-app/Apps/` to their matching targets, and
   add the `MatrixKit/Sources/MatrixKit/` files to each target or attach the
   local package product.
4. Add [`Apps/iOS/Info.plist`](../ios-app/Apps/iOS/Info.plist) to the iOS
   target. It contains the Local Network usage description and the narrow ATS
   exception needed for the matrix's plain-HTTP LAN service.
5. Embed the watch app in the iOS app. Add the iOS `WatchConnectivityBridge`
   to the phone target and `WatchSessionCoordinator` to the watch target.
6. Run the web container on the LAN, launch the iOS app, and enter the full
   base URL including port. The URL is stored in app preferences for the next
   launch.

The source layout is intentionally XcodeGen-independent so it can be adopted
in an existing Apple project without adding a project-generation dependency.
The package test suite can be run from the repository root with:

```sh
swift test --package-path ios-app/MatrixKit
```

## Appearance

All SwiftUI clients expose `System`, `Light`, and `Dark` in the app toolbar or
settings. The choice is stored locally with `AppStorage` and maps to
`preferredColorScheme`, so dark mode is consistent across the iOS, macOS, and
tvOS apps while still respecting the system when `System` is selected. The web
PWA stores the same conceptual preference in `localStorage`.

## Watch connectivity

The watch target uses `WCSession` when available. The iPhone owns the API
connection and responds to watch requests with a Codable state snapshot; route
and power actions are sent back to the iPhone, which executes them through
`MatrixKit`. This means the watch does not need its own matrix credentials and
does not need to discover the Docker host independently.

The watch still needs the normal Apple pairing, app-group/signing setup, and a
real paired device to validate end-to-end. Those are provisioning concerns,
not runtime dependencies of the shared protocol client.
