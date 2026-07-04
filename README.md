# Solboard

A minimal iPhone app to control a MoonBoard LED climbing wall over Bluetooth LE.
Personal project — it replaces the official MoonBoard app for one purpose: light
up a route on the wall and save presets.

## What it does

- **Board** — an 11×18 grid (columns A–K, rows 1–18). Tap a hold to cycle it
  through start (green) → move (blue) → end (red) → off. "Light it" sends the
  route to the wall, "Clear" resets, "Save preset" stores it.
- **Presets** — a plain list; tap to load a route onto the grid, swipe to delete.
- **Connect** — scan for the LED control box and connect; the app auto-reconnects
  to the last box on launch.

## Principles

- **No networking.** The only radio used is CoreBluetooth. No accounts, no
  analytics, nothing leaves the phone.
- **No dependencies.** Swift standard library + SwiftUI + CoreBluetooth only.
- Presets are stored as a JSON file in the app's Documents directory.

## Board image (you supply your own)

The Board screen can display a **photo of your wall** as the background, with the
tap cells overlaid transparently and lit holds drawn as colored rings.

This image is a **Moon Climbing asset and is not distributed with this repo.** To
use it, drop your own photo into the `board` image set at:

```
Solboard/Assets.xcassets/board.imageset/board.png
```

The PNG is gitignored and must never be committed. Without it, the app falls back
to a plain grid. If the rings don't sit on the holds, calibrate the four fractions
in `MoonBoardProtocol.imageInsets`.

## Build

- Open `Solboard.xcodeproj`, scheme `Solboard`.
- Compile check: `xcodebuild -scheme Solboard -destination 'generic/platform=iOS' build`
- Deploy to a device from Xcode (⌘R). The iOS Simulator has no Bluetooth, so BLE
  can only be tested on hardware.

## Protocol

Commands are ASCII strings written to a Nordic-UART-style TX characteristic, e.g.
`l#S5,P9,P13,E18#`. The board wiring (0/1-basing, serpentine direction, exact
UUIDs) is isolated in `MoonBoardProtocol.swift` so on-site fixes touch one file.
