import SwiftUI

struct LiquidPressButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.88 : 1)
            .opacity(configuration.isPressed ? 0.8 : 1)
            .animation(.spring(duration: 0.4, bounce: 0.6), value: configuration.isPressed)
    }
}

struct SpecularRim<S: Shape>: ViewModifier {
    let shape: S

    func body(content: Content) -> some View {
        content.overlay {
            shape
                .strokeBorder(
                    LinearGradient(
                        colors: [Color.white.opacity(0.65), Color.white.opacity(0.22), Color.white.opacity(0.0)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
                .allowsHitTesting(false)
        }
    }
}

extension View {
    func specularRim<S: Shape>(in shape: S) -> some View {
        modifier(SpecularRim(shape: shape))
    }
}

extension Color {
    static let oceanGlass = Color(hex: 0x1E6FD9)
}
