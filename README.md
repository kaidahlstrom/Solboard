# Solboard

A minimal iPhone app to control a MoonBoard LED climbing wall over Bluetooth LE.
Personal project - it replaces the official MoonBoard app for one purpose: light
up a route on the wall and save presets.

## What it does

- **Board** - an 11x18 grid (columns A-K, rows 1-18). Tap a hold to cycle it
  through start (green) -> move (blue) -> end (red) -> off. "Light it" sends the
  route to the wall, "Clear" resets, "Save preset" stores it.
- **Presets** - a plain list; tap to load a route onto the grid, swipe to delete.
- **Connect** - scan for the LED control box and connect; the app auto-reconnects
  to the last box on launch.

## Principles

- **No networking.** The only radio used is CoreBluetooth. No accounts, no
  analytics, nothing leaves the phone.
- **No dependencies.** Swift standard library + SwiftUI + CoreBluetooth only.
- Presets are stored as a JSON file in the app's Documents directory.

## Board image (bundled original artwork)

The Board screen renders a hand-drawn board illustration as the background, with
the tap cells overlaid transparently. Each selected hold shows a small filled
"LED dot" just below it (green/blue/red by type), mirroring the physical board
where the LEDs sit under the holds.

This image is **original artwork owned by the app author** and ships with the app
- it lives in the `board` image set and is tracked in git. It is **not** a Moon
Climbing asset. If it is ever missing, the app falls back to a plain grid. If the
dots don't sit on the holds, calibrate the four fractions in
`MoonBoardProtocol.imageInsets`.

## Build

- Open `Solboard.xcodeproj`, scheme `Solboard`.
- Compile check: `xcodebuild -scheme Solboard -destination 'generic/platform=iOS' build`
- Deploy to a device from Xcode (CmdR). The iOS Simulator has no Bluetooth, so BLE
  can only be tested on hardware.

## Protocol

Commands are ASCII strings written to a Nordic-UART-style TX characteristic, e.g.
`l#S5,P9,P13,E18#`. The board wiring (0/1-basing, serpentine direction, exact
UUIDs) is isolated in `MoonBoardProtocol.swift` so on-site fixes touch one file.
