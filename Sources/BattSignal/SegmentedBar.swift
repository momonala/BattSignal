import SwiftUI

/// Full-width segmented control with equal segments and a sliding selection pill (tabs sliding).
struct SegmentedBar<Value: Hashable>: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var pill
    let options: [(value: Value, label: String)]
    @Binding var selection: Value

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options, id: \.value) { option in
                let isSelected = option.value == selection
                Button {
                    selection = option.value
                } label: {
                    Text(option.label)
                        .font(.callout)
                        .lineLimit(1)
                        .foregroundStyle(isSelected ? Color.white : Color.primary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                        .background {
                            if isSelected {
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(Color.accentColor)
                                    .matchedGeometryEffect(id: "pill", in: pill)
                            }
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .padding(2)
        .background(Color.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
        .animation(Motion.animation(Motion.tabsSlide, reduceMotion: reduceMotion), value: selection)
    }
}
