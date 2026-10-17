# Apple platform status

## Current status

| Platform | Status | What is validated today |
| --- | --- | --- |
| iOS / iPadOS | Available in the Xcode project | SwiftUI app target, demo mode, UI tests, and the shared protocol client |
| macOS | Planned; app target not created | `MatrixKit` package supports macOS 14+ and can run protocol unit tests on a Mac |
| tvOS | Planned | No tvOS app target yet |
| watchOS | Planned | No watchOS app target yet |

The current `HDMIMatrix.xcodeproj` is an iOS-only application target. It uses
the iOS 26 SDK and does not yet produce a `.app`, archive, or installer for
macOS. The macOS support in
[`MatrixKit/Package.swift`](../ios-app/MatrixKit/Package.swift) applies to the
protocol library, not to the SwiftUI application.

## Intel and Apple silicon requirement

The Mac client will ship as one Universal 2 application containing both:

- `arm64` for Apple silicon Macs; and
- `x86_64` for Intel Macs.

The planned Mac target should use a macOS 14+ deployment baseline so it can
serve supported Intel and Apple-silicon systems. Liquid Glass should be used
when the runtime provides it, with a standard SwiftUI material fallback on
older supported macOS releases. See Apple's [Liquid Glass documentation](<https://developer.apple.com/documentation/swiftui/view/glasseffect(_:in:)>)
and [macOS compatibility list](https://support.apple.com/en-euro/122867).

## Work required before a Mac build is available

1. Add a macOS SwiftUI application target to `HDMIMatrix.xcodeproj`, or split
   the current iOS shell into shared views plus platform-specific app shells.
2. Replace UIKit-only color construction in
   [`Theme.swift`](../ios-app/HDMIMatrix/Theme.swift) with cross-platform
   SwiftUI/AppKit-safe code.
3. Gate iOS-only modifiers and navigation behavior with platform-specific
   implementations while preserving the shared routing, inputs, device, and
   connection screens.
4. Add a Release build that sets `ONLY_ACTIVE_ARCH=NO` and verifies both
   architectures with `lipo -info`.
5. Add macOS CI that compiles the app target for `arm64` and `x86_64`, then
   add signed/notarized distribution after the unsigned build is stable.

Until these steps are complete, do not describe the Mac client as shipped or
as a universal binary. The existing Mac CI job validates `MatrixKit` only; the
iOS UI build does not validate the Mac application.

## Local validation target

Once the Mac target exists, the acceptance check should look like this:

```bash
xcodebuild \
  -project ios-app/HDMIMatrix.xcodeproj \
  -scheme HDMIMatrixMac \
  -configuration Release \
  -destination 'generic/platform=macOS' \
  -arch arm64 -arch x86_64 \
  build

lipo -info /path/to/HDMIMatrixMac.app/Contents/MacOS/HDMIMatrixMac
```

The output must report both `arm64` and `x86_64`. A successful `swift test`
run for `MatrixKit` alone is not sufficient evidence that the Mac app builds.
