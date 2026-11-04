import Foundation

/// Layout under `root`:
///   observations/<observer-id>/<device-id>.json         latest snapshot, one writer per observer folder
///   history/<observer-id>/<device-id>/<yyyy-MM-dd>.jsonl one HistoryPoint per line
public struct FleetStore: Sendable {
    public let root: URL

    public init(root: URL) {
        self.root = root
    }

    public static var iCloudRoot: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appending(path: "Library/Mobile Documents/com~apple~CloudDocs/BattSignal", directoryHint: .isDirectory)
    }

    private var observationsDir: URL { root.appending(path: "observations", directoryHint: .isDirectory) }
    private var historyDir: URL { root.appending(path: "history", directoryHint: .isDirectory) }

    private func historyDir(observer: String, device: String) -> URL {
        historyDir
            .appending(path: Self.safe(observer), directoryHint: .isDirectory)
            .appending(path: Self.safe(device), directoryHint: .isDirectory)
    }

    public func write(_ snapshot: Snapshot) throws {
        let dir = observationsDir.appending(path: Self.safe(snapshot.observer.id), directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let data = try JSONCoding.encoder.encode(snapshot)
        try data.write(to: dir.appending(path: Self.safe(snapshot.device.id) + ".json"), options: .atomic)
    }

    public func readAll() -> [Snapshot] {
        Self.children(of: observationsDir).flatMap { observerDir in
            Self.readableFiles(in: observerDir, withExtension: "json").compactMap { file in
                guard let data = try? Data(contentsOf: file) else { return nil }
                return try? JSONCoding.decoder.decode(Snapshot.self, from: data)
            }
        }
    }

    public static func latestPerDevice(_ snapshots: [Snapshot]) -> [Snapshot] {
        Dictionary(grouping: snapshots, by: \.device.id)
            .values
            .compactMap { $0.max { $0.observedAt < $1.observedAt } }
    }

    public func appendHistory(_ snapshot: Snapshot) throws {
        let dir = historyDir(observer: snapshot.observer.id, device: snapshot.device.id)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appending(path: Self.dayString(snapshot.observedAt) + ".jsonl")

        var line = try JSONCoding.lineEncoder.encode(HistoryPoint(snapshot))
        line.append(0x0A)
        if let handle = try? FileHandle(forWritingTo: file) {
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: line)
        } else {
            try line.write(to: file, options: .atomic)
        }
    }

    public func readHistory(deviceID: String) -> [HistoryPoint] {
        let decoder = JSONCoding.decoder
        return Self.children(of: historyDir)
            .map { $0.appending(path: Self.safe(deviceID), directoryHint: .isDirectory) }
            .flatMap { Self.readableFiles(in: $0, withExtension: "jsonl") }
            .flatMap { file -> [HistoryPoint] in
                guard let data = try? Data(contentsOf: file) else { return [] }
                return data.split(separator: 0x0A).compactMap { try? decoder.decode(HistoryPoint.self, from: Data($0)) }
            }
            .sorted { $0.t < $1.t }
    }

    static func safe(_ component: String) -> String {
        String(component.map { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" ? $0 : "_" })
    }

    private static func dayString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    private static func children(of dir: URL) -> [URL] {
        (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil, options: [])) ?? []
    }

    /// Returns downloaded files and asks iCloud to fetch evicted ones (shown as `.name.icloud` placeholders).
    private static func readableFiles(in dir: URL, withExtension ext: String) -> [URL] {
        children(of: dir).compactMap { file in
            let name = file.lastPathComponent
            if name.hasPrefix("."), name.hasSuffix(".icloud") {
                let realName = String(name.dropFirst().dropLast(".icloud".count))
                try? FileManager.default.startDownloadingUbiquitousItem(at: dir.appending(path: realName))
                return nil
            }
            return file.pathExtension == ext ? file : nil
        }
    }
}
