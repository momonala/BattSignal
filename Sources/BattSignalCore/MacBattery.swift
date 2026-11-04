import Foundation
import IOKit
import SystemConfiguration

public enum MacBattery {
    public static func read() -> BatteryReading? {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }
        var properties: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(service, &properties, kCFAllocatorDefault, 0) == KERN_SUCCESS,
              let registry = properties?.takeRetainedValue() as? [String: Any]
        else { return nil }
        var reading = BatteryReading(registry: registry)
        reading.chargeLimit = ChargeLimit.read()
        return reading
    }
}

public struct HostIdentity: Equatable, Sendable {
    public let id: String
    public let name: String
    public let model: String?
    public let serial: String?

    public static func current() -> HostIdentity {
        HostIdentity(
            id: platformProperty(kIOPlatformUUIDKey) ?? "unknown-mac",
            name: (SCDynamicStoreCopyComputerName(nil, nil) as String?) ?? Host.current().localizedName ?? "This Mac",
            model: sysctlString("hw.model"),
            serial: platformProperty(kIOPlatformSerialNumberKey)
        )
    }

    public var observer: Observer { Observer(id: id, name: name) }

    public var device: DeviceInfo {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        let patch = version.patchVersion > 0 ? ".\(version.patchVersion)" : ""
        return DeviceInfo(id: id, name: name, kind: .mac, model: model, osVersion: "macOS \(version.majorVersion).\(version.minorVersion)\(patch)")
    }

    private static func platformProperty(_ key: String) -> String? {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPlatformExpertDevice"))
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }
        return IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0)?
            .takeRetainedValue() as? String
    }

    private static func sysctlString(_ name: String) -> String? {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname(name, &buffer, &size, nil, 0) == 0 else { return nil }
        return String(cString: buffer)
    }
}

public enum ProductNames {
    private static let known: [String: String] = [
        "iPhone14,2": "iPhone 13 Pro",
        "iPhone14,3": "iPhone 13 Pro Max",
        "iPhone14,4": "iPhone 13 mini",
        "iPhone14,5": "iPhone 13",
        "iPad5,1": "iPad mini 4",
        "iPad5,2": "iPad mini 4",
        "iPad16,3": "iPad Pro 11″ (M4)",
        "iPad16,4": "iPad Pro 11″ (M4)",
    ]

    public static func display(_ model: String?) -> String? {
        guard let model else { return nil }
        return known[model] ?? model
    }
}
