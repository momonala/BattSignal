import Foundation

public enum ScanProblem: Equatable, Sendable {
    case toolMissing
    case unreadable([String])
    case listFailed(String)

    public var message: String {
        switch self {
        case .toolMissing:
            "pymobiledevice3 isn't installed, so iPhones and iPads can't be read."
        case .unreadable(let names):
            "Couldn't read \(names.joined(separator: ", ")). It may be asleep or off this Wi-Fi."
        case .listFailed(let description):
            "Scan failed: \(description)"
        }
    }
}

public enum ScanEvent: Equatable, Sendable {
    case started
    case toolMissing
    case listed(deviceCount: Int, failures: [String], at: Date)
    case listFailed(String)
}

public enum ScanState: Equatable, Sendable {
    case idle
    case scanning(lastSucceededAt: Date?)
    case finished(ScanProblem?, lastSucceededAt: Date?)

    public var isScanning: Bool {
        if case .scanning = self { true } else { false }
    }

    public var problem: ScanProblem? {
        if case .finished(let problem, _) = self { problem } else { nil }
    }

    public var lastSucceededAt: Date? {
        switch self {
        case .idle: nil
        case .scanning(let at), .finished(_, let at): at
        }
    }

    public func applying(_ event: ScanEvent) -> ScanState {
        switch event {
        case .started:
            return .scanning(lastSucceededAt: lastSucceededAt)
        case .toolMissing:
            return .finished(.toolMissing, lastSucceededAt: lastSucceededAt)
        case .listed(let deviceCount, let failures, let at):
            let succeeded = deviceCount > 0 && failures.isEmpty
            return .finished(
                failures.isEmpty ? nil : .unreadable(failures),
                lastSucceededAt: succeeded ? at : lastSucceededAt
            )
        case .listFailed(let description):
            return .finished(.listFailed(description), lastSucceededAt: lastSucceededAt)
        }
    }
}
