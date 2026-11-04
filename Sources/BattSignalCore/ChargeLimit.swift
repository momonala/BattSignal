import Foundation

/// Reads the macOS 26.4+ charge limit ("Battery › Charging › Limit"). powerd stores it as an archived
/// `ChargeCtrlPolicy` whose reason is `manualChargeLimit`. The format is undocumented, so any surprise
/// yields nil ("unknown") rather than a guess.
public enum ChargeLimit {
    public static let preferencesURL = URL(fileURLWithPath: "/Library/Preferences/com.apple.powerd.charging.plist")
    public static let settingsURL = URL(string: "x-apple.systempreferences:com.apple.Battery-Settings.extension?batteryhealth")!

    public static func read(from url: URL = preferencesURL) -> Int? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return parse(preferences: data)
    }

    static func parse(preferences data: Data) -> Int? {
        guard let outer = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let policies = outer["policies"] as? Data,
              let archive = try? PropertyListSerialization.propertyList(from: policies, format: nil) as? [String: Any],
              let objects = archive["$objects"] as? [Any],
              objects.contains(where: { ($0 as? String) == "manualChargeLimit" })
        else { return nil }

        return objects
            .compactMap { $0 as? [String: Any] }
            .first { $0["soclimit"] != nil && ($0["terminated"] as? Bool) != true }
            .flatMap { ($0["soclimit"] as? NSNumber)?.intValue }
            .flatMap { (1...100).contains($0) ? $0 : nil }
    }
}
