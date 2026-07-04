# Solboard

Minimal iPhone app to control a MoonBoard LED climbing wall over Bluetooth LE. Personal project. Replaces the official MoonBoard app for one purpose only: light up a route and save presets.

## Hard constraints — never violate

- **No networking.** No URLSession, no analytics, no crash reporting, no remote config, no third-party SDKs. The only radio this app uses is CoreBluetooth.
- **No accounts, no credentials, no data collection.** Nothing leaves the phone.
- **No secrets in the repo.** Never commit tokens, signing assets, or `.env`-style files. Respect `.gitignore`.
- **Dependencies: none.** Standard library + SwiftUI + CoreBluetooth only. Do not add SPM packages without asking.
- **Keep it simple.** Prefer fewer files and boring code over architecture. No view models where a `@State` will do. This app should stay under ~1000 lines.

## Target hardware

- MoonBoard 2024 setup: full-size board, 11 columns (A–K) × 18 rows (1–18), 198 holds.
- LED control box: Moon Climbing V4/V5 (exact model TBD — verified at the gym via nRF Connect).
- BLE: Nordic UART-style service. Exact service/characteristic UUIDs to be confirmed on-site and recorded below.

### Protocol (community reverse-engineered)

Commands are ASCII strings written to the UART TX characteristic:

```
l#<hold>,<hold>,...#
```

- Starts with `l#`, ends with `#`, holds comma-separated.
- Each hold = type char + position number:
  - `S` = start hold (green)
  - `P` = progress/move hold (blue)
  - `E` = end hold (red)
- Example: `l#S5,P9,P13,E18#`
- Position range 1–198, following the LED strip through the grid.

**Open questions to resolve at the gym (do not guess):**
1. Exact service + characteristic UUIDs.
2. Whether positions are 0-based or 1-based on this box (community sources conflict: e-sr docs say 1–198, Arduino implementations index A1=0).
3. Grid-to-position mapping direction: strips typically run serpentine (A1 up column or along row, alternating). Verify with a known test pattern.
4. Whether the V4/V5 box expects any framing prefix, MTU chunking, or write-with-response vs. write-without-response.

Isolate all of this in one file (`MoonBoardProtocol.swift`) with the mapping as a pure function `(column, row, holdType) -> command fragment`, so gym-day fixes touch one place.

## App spec

Three screens max:

1. **Board** (main): 11×18 tappable grid. Tap a cell to cycle: none → start (green) → move (blue) → end (red) → none. Buttons: "Light it" (send to board), "Clear", "Save preset". Show connection status (disconnected / scanning / connected + peripheral name).
2. **Presets**: plain list, tap to load onto the grid, swipe to delete. Rename optional.
3. **Connect**: list of discovered peripherals, tap to connect. Auto-reconnect to last known peripheral on launch.

- Presets stored as a JSON file in the app's Documents directory. Schema: `{ name, createdAt, holds: [{ col, row, type }] }`. No SwiftData/CoreData unless asked.
- Visuals: stock SwiftUI. No custom design, no animations beyond defaults. Grid cells show column letter + row number in small text.
- **Board image (user-supplied).** The Board screen can render a photo of the wall as the background with transparent tap cells overlaid; selected holds draw colored rings (green/blue/red). Drop a photo into the `board` image set (`Solboard/Assets.xcassets/board.imageset/`). This image is a Moon Climbing asset — it is **gitignored and must never be committed** to this public repo (only the imageset's `Contents.json` is tracked). If no image is present, the app falls back to a plain 11×18 grid. Alignment is calibrated via `MoonBoardProtocol.imageInsets` (top/bottom/left/right fractions) — the one place to tune ring positions.
- `NSBluetoothAlwaysUsageDescription` must be set in target Info.

## Build & run

- Xcode project at repo root: `Solboard.xcodeproj`, scheme `Solboard`.
- Build check: `xcodebuild -scheme Solboard -destination 'generic/platform=iOS' build`
- Device deploys are done by the human via Xcode (⌘R). Don't attempt device installs.
- The iOS Simulator has no Bluetooth — never try to test BLE in the simulator. Compile-check only.

## Git

- Small commits, imperative messages ("Add grid tap cycling"), commit after each working increment.
- Push to `origin main`. Public repo — write code and comments accordingly.

## Verification plan (gym day)

1. nRF Connect: record advertised name, service UUIDs, characteristic UUIDs + properties → update this file.
2. Manually write `l#S1,P50,E198#` from nRF Connect → confirm lights, note which physical holds lit → fix 0/1-basing and serpentine mapping in `MoonBoardProtocol.swift`.
3. App: connect → send same pattern → compare.
4. Then full route round-trip: set on grid → light → save preset → reload → light again.
