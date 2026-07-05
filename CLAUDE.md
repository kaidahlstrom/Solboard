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
- LED control box: Moon Climbing V4/V5. Advertises as **"MoonBoard A"** (confirmed on-site via nRF Connect).
- BLE: standard Nordic UART Service, confirmed on-site. Service `6E400001-B5A3-F393-E0A9-E50E24DCCA9E`; route commands are written to the RX characteristic `6E400002-B5A3-F393-E0A9-E50E24DCCA9E`.

### Protocol (community reverse-engineered)

Commands are ASCII strings written to the UART RX characteristic (`6E400002`):

```
l#<hold>,<hold>,...#
```

- Starts with `l#`, ends with `#`, holds comma-separated.
- Each hold = type char + position number:
  - `S` = start hold (green)
  - `P` = progress/move hold (blue)
  - `E` = end hold (red)
- Example (real 0-based positions): `l#S0,P50,E197#` = start on A1 (pos 0), move on C15 (pos 50), end on K18 (pos 197).
- Position range **0–197**, serpentine column-major (see Q2/Q3 below). Out-of-range positions are silently ignored by the box.

**Open questions — all RESOLVED on-site (nRF Connect + test pattern):**
1. ✅ **Service + characteristic UUIDs.** Standard Nordic UART Service. Service `6E400001-…`; write target is the RX characteristic `6E400002-…`. Board advertises as "MoonBoard A".
2. ✅ **0- vs 1-based.** **0-based**, range 0–197. (`positionsAreOneBased` alternative removed.)
3. ✅ **Mapping direction.** **Serpentine column-major** (A=0..K=10, rows r=1..18): `position = c*18 + (r-1)` for even column index `c`, `c*18 + (18-r)` for odd `c`. Even columns run bottom-up, odd columns run top-down. Verified 0→A1, 17→A18, 50→C15, **58→D14, 67→D5**, 197→K18. (Initial recon read it as straight column-major because A1/C15/K18 all fall in even columns, where both layouts agree.)
4. ✅ **Framing / MTU / write mode.** No extra framing beyond `l#…#`, but the box is an old Nordic chip with a **23-byte ATT MTU** — writes over 20 bytes are silently dropped. The app chunks the command into ≤20-byte pieces and writes them **sequentially with write-with-response**, waiting for each ack before the next; the framing lets the box reassemble.

Isolate all of this in one file (`MoonBoardProtocol.swift`) with the mapping as a pure function `(column, row, holdType) -> command fragment`, so gym-day fixes touch one place.

## App spec

Three screens max:

1. **Board** (main): 11×18 tappable grid. Tap a cell to cycle: none → start (green) → move (blue) → end (red) → none. Buttons: "Light it" (send to board), "Clear", "Save preset". Show connection status (disconnected / scanning / connected + peripheral name).
2. **Presets**: plain list, tap to load onto the grid, swipe to delete. Rename optional.
3. **Connect**: list of discovered peripherals, tap to connect. Auto-reconnect to last known peripheral on launch.

- Presets stored as a JSON file in the app's Documents directory. Schema: `{ name, createdAt, holds: [{ col, row, type }] }`. No SwiftData/CoreData unless asked.
- Visuals: stock SwiftUI. No custom design, no animations beyond defaults. Grid cells show column letter + row number in small text.
- **Board image (bundled original artwork).** The Board screen renders a hand-drawn board illustration as the background with transparent tap cells overlaid; each selected hold shows a small filled "LED dot" just below it (green/blue/red by type), mimicking the physical board where the LEDs sit under the holds. The image lives in the `board` image set (`Solboard/Assets.xcassets/board.imageset/`) and is **original artwork owned by the app author — it is tracked in git and ships with the app** (it is not a Moon Climbing asset). If the image is ever missing, the app falls back to a plain 11×18 grid. Alignment is calibrated via `MoonBoardProtocol.imageInsets` (top/bottom/left/right fractions) — the one place to tune dot/cell positions.
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
