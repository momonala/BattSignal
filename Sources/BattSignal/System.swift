import BattSignalCore
import AppKit
import IOKit.ps
import ServiceManagement

/// Login items need a real app bundle; under `swift run` they are skipped.
private var isBundled: Bool { Bundle.main.bundleIdentifier != nil }

@MainActor
enum LoginItem {
    static var isEnabled: Bool {
        isBundled && SMAppService.mainApp.status == .enabled
    }

    static func set(_ enabled: Bool) throws {
        guard isBundled else { return }
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }
}

enum PowerSymbol: String, CaseIterable {
    case bolt, plug
}

enum BarColoring: String, CaseIterable {
    case blue, chargeState
}

enum IconColoring: String, CaseIterable {
    case symbolOnly, symbolAndNumber, wholeIcon
}

extension ChargeState {
    var tint: NSColor? {
        switch self {
        case .normal: nil
        case .charging: .systemYellow
        case .full: .systemGreen
        case .pluggedIn: .systemBlue
        case .low: .systemRed
        case .onBattery: .systemYellow
        }
    }
}

enum MenuIcon {
    private enum Glyph: Hashable {
        case bolt
        case plug
        case battery(level: Int)
    }

    private struct Key: Hashable {
        let state: ChargeState
        let glyph: Glyph?
        let label: String?
        let coloring: IconColoring
    }

    @MainActor private static var cache: [Key: NSImage] = [:]

    @MainActor
    static func image(
        for battery: BatteryReading?,
        showPercent: Bool,
        powerSymbol: PowerSymbol,
        coloring: IconColoring
    ) -> NSImage {
        let percent = battery?.chargePercent
        let powerGlyph: Glyph = switch powerSymbol {
        case .bolt: .bolt
        case .plug: .plug
        }
        let key = Key(
            state: battery?.chargeState ?? .normal,
            glyph: battery.map { $0.externalPower == true ? powerGlyph : .battery(level: percent ?? 0) },
            label: showPercent ? percent.map(String.init) : nil,
            coloring: coloring
        )
        if let cached = cache[key] { return cached }
        let image = draw(key)
        cache[key] = image
        return image
    }

    private static func draw(_ key: Key) -> NSImage {
        let width: CGFloat = 22
        let scale: CGFloat = 1.8
        let tint = key.state.tint ?? .white
        let base = key.coloring == .wholeIcon ? tint : .white
        let numberColor = key.coloring == .symbolOnly ? .white : tint
        let font = NSFont.monospacedDigitSystemFont(ofSize: 12.5, weight: .bold)
        let text = key.label.map {
            NSAttributedString(string: $0, attributes: [.font: font, .foregroundColor: numberColor, .kern: -0.4])
        }
        let textOrigin = NSPoint(x: 13.3 * scale, y: font.descender + 0.3)
        let imageWidth = max(width * scale, textOrigin.x + (text?.size().width ?? 0))
        let image = NSImage(size: NSSize(width: imageWidth, height: 12 * scale), flipped: false) { _ in
            func p(_ x: CGFloat, _ y: CGFloat) -> NSPoint { NSPoint(x: x * scale, y: y * scale) }
            func mirrored(_ x: CGFloat, _ y: CGFloat) -> NSPoint { p(width - x, y) }
            func rect(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> NSRect {
                NSRect(x: x * scale, y: y * scale, width: w * scale, height: h * scale)
            }
            func knockOut(_ path: NSBezierPath) {
                NSGraphicsContext.current?.compositingOperation = .destinationOut
                path.lineJoinStyle = .round
                path.lineWidth = 1.6
                path.stroke()
                path.fill()
                NSGraphicsContext.current?.compositingOperation = .sourceOver
            }

            let bat = NSBezierPath()
            bat.move(to: p(0.5, 9.5))
            bat.curve(to: p(7.6, 8.0), controlPoint1: p(3.5, 11.0), controlPoint2: p(5.5, 10.0))
            bat.line(to: p(9.4, 8.6))
            bat.line(to: p(9.8, 11.2))
            bat.line(to: p(10.6, 9.5))
            bat.line(to: mirrored(10.6, 9.5))
            bat.line(to: mirrored(9.8, 11.2))
            bat.line(to: mirrored(9.4, 8.6))
            bat.line(to: mirrored(7.6, 8.0))
            bat.curve(to: mirrored(0.5, 9.5), controlPoint1: mirrored(5.5, 10.0), controlPoint2: mirrored(3.5, 11.0))
            bat.line(to: mirrored(2.4, 5.6))
            bat.curve(to: mirrored(5.4, 5.4), controlPoint1: mirrored(3.9, 6.9), controlPoint2: mirrored(3.9, 6.9))
            bat.curve(to: mirrored(8.6, 3.6), controlPoint1: mirrored(7.0, 5.8), controlPoint2: mirrored(7.0, 5.8))
            bat.line(to: p(11.0, 0.6))
            bat.line(to: p(8.6, 3.6))
            bat.curve(to: p(5.4, 5.4), controlPoint1: p(7.0, 5.8), controlPoint2: p(7.0, 5.8))
            bat.curve(to: p(2.4, 5.6), controlPoint1: p(3.9, 6.9), controlPoint2: p(3.9, 6.9))
            bat.close()
            base.setFill()
            bat.fill()

            switch key.glyph {
            case .bolt:
                let bolt = NSBezierPath()
                bolt.move(to: p(8.33, 10.81))
                bolt.line(to: p(3.87, 4.56))
                bolt.line(to: p(6.31, 4.56))
                bolt.line(to: p(5.52, 0.1))
                bolt.line(to: p(9.33, 6.21))
                bolt.line(to: p(6.82, 6.21))
                bolt.close()
                knockOut(bolt)
                tint.setFill()
                bolt.fill()
            case .plug:
                let prongs = [rect(4.75, 7.4, 0.75, 2.9), rect(6.3, 7.4, 0.75, 2.9)]
                    .map { NSBezierPath(roundedRect: $0, xRadius: 0.3 * scale, yRadius: 0.3 * scale) }
                let head = NSBezierPath(roundedRect: rect(4.1, 3.9, 3.6, 3.9), xRadius: 0.9 * scale, yRadius: 0.9 * scale)
                let cable = NSBezierPath(rect: rect(5.45, 0.1, 0.9, 4.0))
                let plug = NSBezierPath()
                (prongs + [head, cable]).forEach(plug.append)
                knockOut(plug)
                tint.setFill()
                (prongs + [head, cable]).forEach { $0.fill() }
            case .battery(let level):
                let body = NSBezierPath(roundedRect: rect(4.1, 0.3, 3.6, 8.7), xRadius: 0.9 * scale, yRadius: 0.9 * scale)
                let cap = NSBezierPath(roundedRect: rect(5.05, 9.0, 1.7, 1.0), xRadius: 0.35 * scale, yRadius: 0.35 * scale)
                let outline = NSBezierPath()
                outline.append(body)
                outline.append(cap)
                knockOut(outline)
                tint.set()
                cap.fill()
                let inset = 0.55 * scale
                let rim = NSBezierPath(roundedRect: body.bounds.insetBy(dx: inset / 2, dy: inset / 2), xRadius: 0.65 * scale, yRadius: 0.65 * scale)
                rim.lineWidth = inset
                rim.stroke()
                let well = rect(4.1, 0.3, 3.6, 8.7).insetBy(dx: 0.95 * scale, dy: 0.95 * scale)
                let fillHeight = well.height * CGFloat(min(max(level, 0), 100)) / 100
                NSBezierPath(roundedRect: NSRect(x: well.minX, y: well.minY, width: well.width, height: fillHeight), xRadius: 0.3 * scale, yRadius: 0.3 * scale).fill()
            case nil:
                break
            }

            if let text {
                let outline = NSMutableAttributedString(attributedString: text)
                outline.addAttributes([.strokeWidth: 13, .strokeColor: NSColor.black], range: NSRange(location: 0, length: outline.length))
                NSGraphicsContext.current?.compositingOperation = .destinationOut
                outline.draw(at: textOrigin)
                NSGraphicsContext.current?.compositingOperation = .sourceOver
                text.draw(at: textOrigin)
            }
            return true
        }
        return image
    }
}

@MainActor
final class PowerSourceWatcher {
    private let onChange: () -> Void
    private nonisolated(unsafe) var source: CFRunLoopSource?

    init(onChange: @escaping () -> Void) {
        self.onChange = onChange
        let context = Unmanaged.passUnretained(self).toOpaque()
        guard let source = IOPSNotificationCreateRunLoopSource({ context in
            guard let context else { return }
            let watcher = Unmanaged<PowerSourceWatcher>.fromOpaque(context).takeUnretainedValue()
            MainActor.assumeIsolated { watcher.onChange() }
        }, context)?.takeRetainedValue() else { return }
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        self.source = source
    }

    deinit {
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
    }
}
