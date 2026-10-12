import SwiftUI

/// Segmented appearance choice (Settings → General). The track is a standard fill (content layer); only the
/// selection thumb is Liquid Glass, the way system controls turn their knob into glass. One thumb slides to the
/// selected segment, so a change reads as a single fluid move instead of a hop.
struct AppearancePicker: View {
    @Binding var selection: AppAppearance
    @Namespace private var segments
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 2) {
            ForEach(AppAppearance.allCases, id: \.self) { choice in
                segment(choice)
            }
        }
        .background {
            // Not `.interactive()`: the segments take the clicks, an interactive thumb would swallow them.
            Capsule()
                .fill(.clear)
                .glassEffect(.regular, in: .capsule)
                .matchedGeometryEffect(id: selection, in: segments, isSource: false)
        }
        .padding(3)
        .background(.fill.tertiary, in: .capsule)
        .fixedSize()
        .accessibilityElement(children: .contain)
    }

    private func segment(_ choice: AppAppearance) -> some View {
        let isSelected = choice == selection
        return Button {
            guard !isSelected else { return }
            withAnimation(reduceMotion ? nil : .bouncy(duration: 0.4, extraBounce: 0.05)) { selection = choice }
        } label: {
            Label(choice.localizedName, systemImage: choice.symbolName)
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .foregroundStyle(isSelected ? .primary : .secondary)
        .matchedGeometryEffect(id: choice, in: segments)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
