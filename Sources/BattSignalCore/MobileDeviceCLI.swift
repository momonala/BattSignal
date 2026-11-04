import Foundation

public struct IOSDevice: Equatable, Sendable {
    public let udid: String
    public let name: String
    public let kind: DeviceKind
    public let productType: String?
    public let osVersion: String?

    public var info: DeviceInfo {
        DeviceInfo(id: udid, name: name, kind: kind, model: productType, osVersion: osVersion.map { "\(kind == .ipad ? "iPadOS" : "iOS") \($0)" })
    }

    public static func parseList(_ data: Data) throws -> [IOSDevice] {
        guard let entries = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            throw MobileDeviceError.unexpectedOutput
        }
        var seen = Set<String>()
        return entries.compactMap { entry in
            guard let udid = (entry["UniqueDeviceID"] ?? entry["Identifier"]) as? String,
                  seen.insert(udid).inserted
            else { return nil }
            let kind: DeviceKind = switch (entry["DeviceClass"] as? String)?.lowercased() {
            case "iphone": .iphone
            case "ipad": .ipad
            default: .other
            }
            return IOSDevice(
                udid: udid,
                name: entry["DeviceName"] as? String ?? udid,
                kind: kind,
                productType: entry["ProductType"] as? String,
                osVersion: entry["ProductVersion"] as? String
            )
        }
    }
}

public enum MobileDeviceError: Error, LocalizedError {
    case unexpectedOutput
    case timedOut
    case failed(status: Int32, message: String)

    public var errorDescription: String? {
        switch self {
        case .unexpectedOutput: "pymobiledevice3 returned output BattSignal can't read"
        case .timedOut: "pymobiledevice3 timed out"
        case let .failed(status, message): "pymobiledevice3 exited with \(status): \(message)"
        }
    }
}

public struct MobileDeviceCLI: Sendable {
    public let executable: URL

    public init(executable: URL) {
        self.executable = executable
    }

    public static func locate() -> MobileDeviceCLI? {
        locateExecutable("pymobiledevice3").map(MobileDeviceCLI.init(executable:))
    }

    public func listDevices() async throws -> [IOSDevice] {
        try IOSDevice.parseList(await run(["usbmux", "list"], timeout: 30))
    }

    public func battery(udid: String) async throws -> BatteryReading {
        let data = try await run(["diagnostics", "battery", "single", "--udid", udid], timeout: 60)
        guard let registry = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw MobileDeviceError.unexpectedOutput
        }
        return BatteryReading(registry: registry)
    }

    private func run(_ arguments: [String], timeout: TimeInterval) async throws -> Data {
        let result = try await CommandRunner.run(executable, arguments, timeout: timeout)
        if result.timedOut { throw MobileDeviceError.timedOut }
        guard result.status == 0 else { throw MobileDeviceError.failed(status: result.status, message: result.errorOutput) }
        return result.output
    }
}
