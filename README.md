# BattSignal

Menu bar app showing battery health for both of my Macs, my iPhone and my iPads, from either Mac. It replaces coconutBattery Plus. Charge limiting is left to the limit built into macOS 26.4+, which BattSignal reads and shows.

## Quick start

On each Mac:

```bash
uv tool install pymobiledevice3          # reads iPhone/iPad batteries; no root needed
cd ~/code/projects/BattSignal
swift test                               # core logic tests
./scripts/build-app.sh                   # builds build/BattSignal.app, copies it to ~/Applications, launches it (--build-only skips the last two)
```

Then click the bat in the menu bar, open the gear, and tick **Open at login**.

For iPhones and iPads, pair each one once: plug it into a Mac, tap **Trust**, then turn on **Show this iPhone when on Wi-Fi** in Finder. After that, any Mac on the same Wi-Fi can read it.

## How it works

Every Mac runs the same app and does three things on a timer:

- Reads its own battery every 60 s from the IORegistry `AppleSmartBattery` entry (`MacBattery.read`).
- Every 15 min (Settings › iPhone and iPad), runs `pymobiledevice3 usbmux list` to find iPhones and iPads, then `pymobiledevice3 diagnostics battery single --udid …` for each one. iOS returns the same `AppleSmartBattery` keys as macOS, so one parser (`BatteryReading(registry:)`) handles every device.
- Writes what it saw into iCloud Drive and reads what the other Mac wrote. The device list shows the newest reading per device.

```
~/Library/Mobile Documents/com~apple~CloudDocs/BattSignal/
  observations/<mac-uuid>/<device-id>.json            latest reading; rewritten on change or every 10 min
  history/<mac-uuid>/<device-id>/<yyyy-mm-dd>.jsonl   one line per 15 min
  history/<mac-uuid>/<device-id>/coconutbattery-import.jsonl
```

`<mac-uuid>` is the hardware UUID of the Mac that took the reading. `<device-id>` is a Mac's hardware UUID or an iPhone/iPad's UDID. Names shown in the UI are read from the files, so renaming a device keeps its history.

### Where the numbers come from

| Shown as | Source |
|---|---|
| Charge % | `AppleRawCurrentCapacity / AppleRawMaxCapacity`, the same as coconutBattery. Falls back to macOS's `CurrentCapacity` when the raw values are missing. |
| Health | `AppleRawMaxCapacity / DesignCapacity` |
| Temperature | `VirtualTemperature / 100`. Falls back to `Temperature / 100` when `VirtualTemperature` is missing. |
| Lifetime (operating time, voltage range, peak currents) | `BatteryData.LifetimeData` |
| Temp seen | min and max of BattSignal's own readings |
| Battery made | battery serial: 4th character is the year digit, 5th and 6th are the ISO week |
| Charge limit | `/Library/Preferences/com.apple.powerd.charging.plist`, policy `manualChargeLimit` |
| Cycles / month, health / month | least-squares fit over daily averages of the full history (needs 14+ days) |

### coconutBattery history

History imported from coconutBattery during setup lives in `coconutbattery-import.jsonl` next to each device's daily files. It is read like any other history file; nothing writes to it any more.

## Configuration

- **Settings** live in `UserDefaults` under `org.mnalavadi.battsignal` and are edited from the gear in the popover. To add one: add a key in `SettingsKey` (`Sources/BattSignal/SettingsView.swift`), register its default in `registerDefaults()`, and read it with `@AppStorage` in the view or `defaults` in `AppModel`.
- **Charge limit** is set in macOS, not in BattSignal. The **Change…** button in Settings opens System Settings › Battery › Battery Health.
- No secrets or credentials.

## Project structure

- `Sources/BattSignalCore/`: everything testable without a UI. Battery parsing, the iCloud store (`FleetStore`), chart maths (`HistoryAggregator`), the charge-limit reader, and the subprocess runner for `pymobiledevice3`.
- `Sources/BattSignal/`: the SwiftUI `MenuBarExtra` app. `AppModel` runs the timers, `DevicesView` is the main list with expandable rows, `HistoryView` draws the charts, and `Motion.swift` holds the animation timings.
- `Tests/BattSignalCoreTests/`: unit tests for the core.
- `scripts/build-app.sh`: wraps the release binary in an ad-hoc signed `.app` using `Resources/Info.plist` (menu bar only, no Dock icon).
- `data/backups/`: coconutBattery `.ccba` exports and AlDente's stats, kept as an archive. Personal data, so keep it out of git.
- `docs/screenshots/`: the coconutBattery and AlDente screens the UI was modelled on.

## Key decisions

- **iCloud Drive as the sync layer, one writer per folder.** No server to run and no Apple developer account, which CloudKit would need. Each Mac only writes under its own UUID, so iCloud never has to resolve a conflict. The cost is a few minutes of sync lag.
- **External tools run as subprocesses through one wrapper (`CommandRunner`).** `pymobiledevice3` is Python. Calling it keeps a Python runtime out of the app, and if it breaks, only `MobileDeviceCLI` changes.
- **macOS's charge limit, not our own.** macOS 26.4 holds the battery at 80–100 %, keeps doing so while asleep, and Apple maintains it. Driving the SMC ourselves, as AlDente and the `battery` CLI do, needs root and breaks whenever Apple changes the firmware keys. BattSignal only reads the limit; there's no public API to set it.
- **Raw charge % for display, macOS's % for limit logic.** The display matches coconutBattery. "Held at 80 % limit" compares against macOS's own figure, because that's the number macOS stops at. A row reading "79 % · Held at 80 % limit" is therefore correct.
- **The battery's own lifetime temperatures aren't shown.** Their units differ between keys and between devices (tenths of a degree on some, whole degrees on others), so "Temp seen" comes from BattSignal's readings instead.

## Limitations

- iPhones and iPads are only read while on the same Wi-Fi as a running Mac, or plugged into one. A device away from home shows its last reading with "seen X ago".
- The charge-limit file and the archived policy inside it are undocumented. If Apple changes the format, BattSignal shows "Not set" rather than showing a wrong number.
- "Battery made" decoding is only checked against two serials (this MacBook Air and the iPhone 13). Batteries from other suppliers may encode the date differently.
- The app is built for the Mac's own architecture and ad-hoc signed, so build it on each Mac instead of copying the `.app` across.
