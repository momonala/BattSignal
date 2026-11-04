# BattSignal: Phase A (replace coconutBattery Plus)

Done = menu bar popover shows this Mac, every iPhone/iPad on Wi-Fi, and the other Mac (via iCloud Drive), with a hoverable history chart and health/temperature alerts. Values match `ioreg` / coconutBattery.

- [x] Stage 0: Wi-Fi spike. iPhone "Momo" read over Wi-Fi, no root
- [x] Package skeleton (SwiftPM, core + app + tests)
- [x] Core: BatteryReading parser, Snapshot, HostIdentity
- [x] Core: MobileDeviceCLI (pymobiledevice3 subprocess)
- [x] Core: FleetStore (observations + daily history JSONL)
- [x] Core: AlertPolicy, HistoryAggregator
- [x] Unit tests pass
- [x] App: popover (This Mac / Devices / History), menu bar icon
- [x] Build script → ~/Applications/BattSignal.app
- [x] Verify against ioreg + live run (Mac and Momo written to iCloud Drive)
- [ ] Owner: visual check of popover, enable "Open at login"
- [x] Import coconutBattery history from its SQLite store (249 Mac readings + 1 Momo)
- [x] Settings tab, bat menu bar icon, health as plain stat
- [ ] Stage 4: install on MacBook Pro M5 (needs owner). Its coconutBattery history, incl. a 2nd Momo reading, imports automatically there
