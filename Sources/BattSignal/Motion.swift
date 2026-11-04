import SwiftUI

/// SwiftUI port of the transitions.dev motion tokens.
enum Motion {
    /// Card resize: --resize-dur 300ms, --ease-smooth-out.
    static let resize = Animation.timingCurve(0.22, 1, 0.36, 1, duration: 0.30)
    /// Panel reveal / list change: --duration-slow 400ms, --ease-smooth-out.
    static let reveal = Animation.timingCurve(0.22, 1, 0.36, 1, duration: 0.40)
    /// Number pop-in: --digit-dur 500ms with its overshoot curve.
    static let numberPop = Animation.timingCurve(0.34, 1.45, 0.64, 1, duration: 0.50)
    /// Tabs sliding: --duration-fast 250ms, --ease-smooth-out.
    static let tabsSlide = Animation.timingCurve(0.22, 1, 0.36, 1, duration: 0.25)
    /// Icon swap: --icon-swap-dur 250ms, ease-in-out.
    static let iconSwap = Animation.easeInOut(duration: 0.25)

    static func animation(_ animation: Animation, reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : animation
    }

    /// Panel reveal cross-blur for swapping tab content; a plain fade when Reduce Motion is on.
    static func tabContent(reduceMotion: Bool) -> AnyTransition {
        reduceMotion ? .opacity : AnyTransition(.blurReplace)
    }
}

/// Re-enters changed digits (number pop-in) instead of hard-swapping the text.
struct NumericPop<Value: Equatable>: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let value: Value

    func body(content: Content) -> some View {
        content
            .contentTransition(reduceMotion ? .identity : .numericText())
            .animation(Motion.animation(Motion.numberPop, reduceMotion: reduceMotion), value: value)
    }
}

extension View {
    func numericPop<Value: Equatable>(_ value: Value) -> some View {
        modifier(NumericPop(value: value))
    }
}

extension Motion {
    /// Success check pop: --duration-very-slow 500ms with the badge bounce curve.
    static let successIn = Animation.timingCurve(0.34, 1.36, 0.64, 1, duration: 0.50)
    /// Shimmer sweep: --shimmer-dur 2000ms, linear, looping.
    static let shimmer = Animation.linear(duration: 2.0).repeatForever(autoreverses: false)
}

/// Sweeps a highlight band across text while work is in progress (shimmer text).
struct Shimmer: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let active: Bool
    @State private var phase: CGFloat = 0

    func body(content: Content) -> some View {
        if active && !reduceMotion {
            content
                .overlay {
                    GeometryReader { geometry in
                        let band = geometry.size.width * 0.6
                        LinearGradient(colors: [.clear, .primary, .clear], startPoint: .leading, endPoint: .trailing)
                            .frame(width: band)
                            .offset(x: -band + phase * (geometry.size.width + band))
                    }
                    .mask(content)
                }
                .onAppear {
                    phase = 0
                    withAnimation(Motion.shimmer) { phase = 1 }
                }
        } else {
            content
        }
    }
}

extension View {
    func shimmer(_ active: Bool) -> some View {
        modifier(Shimmer(active: active))
    }
}

/// Pops a green check for a moment after an action succeeds, then fades it out.
struct SuccessCheck: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let trigger: Date?
    @State private var visible = false

    var body: some View {
        ZStack {
            if visible {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .transition(reduceMotion ? .opacity : .scale(scale: 0.4).combined(with: .opacity))
                    .accessibilityLabel("Done")
            }
        }
        .frame(width: 16, height: 16)
        .task(id: trigger) {
            guard let trigger, Date.now.timeIntervalSince(trigger) < 3 else { return }
            withAnimation(Motion.animation(Motion.successIn, reduceMotion: reduceMotion)) { visible = true }
            try? await Task.sleep(for: .seconds(1.8))
            withAnimation(.easeOut(duration: 0.15)) { visible = false }
        }
    }
}
