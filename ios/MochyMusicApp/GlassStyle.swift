import SwiftUI

private struct GlassSurface<Surface: InsettableShape>: ViewModifier {
    var shape: Surface
    var interactive: Bool
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    @ViewBuilder
    func body(content: Content) -> some View {
        if reduceTransparency {
            content
                .background(Color(uiColor: .secondarySystemBackground), in: shape)
                .overlay { shape.strokeBorder(.white.opacity(0.24), lineWidth: 1) }
        } else {
            #if compiler(>=6.2)
            if #available(iOS 26.0, *) {
                content.glassEffect(.regular.interactive(interactive), in: shape)
                    .shadow(color: .black.opacity(0.16), radius: 14, y: 6)
            } else {
                frosted(content)
            }
            #else
            frosted(content)
            #endif
        }
    }

    private func frosted(_ content: Content) -> some View {
        content
            .background(.ultraThinMaterial, in: shape)
            .overlay {
                shape.strokeBorder(
                    LinearGradient(colors: [.white.opacity(contrast == .increased ? 0.5 : 0.28), .white.opacity(0.05), .white.opacity(0.14)], startPoint: .topLeading, endPoint: .bottomTrailing),
                    lineWidth: 1
                )
            }
            .shadow(color: .black.opacity(0.24), radius: 16, y: 8)
    }
}

extension View {
    func glassPill(interactive: Bool = false) -> some View {
        modifier(GlassSurface(shape: Capsule(), interactive: interactive))
    }
    func glassCard(cornerRadius: CGFloat = 26) -> some View {
        modifier(GlassSurface(shape: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous), interactive: false))
    }
}

struct GlassButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isEnabled) private var isEnabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .contentShape(Capsule())
            .glassPill(interactive: true)
            .opacity(isEnabled ? 1 : 0.38)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.94 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.14), value: configuration.isPressed)
    }
}
