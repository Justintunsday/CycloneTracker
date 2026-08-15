import SwiftUI

extension Color {
    static let oceanGlass = Color(hex: 0x1E6FD9)
}

struct CircleGlassButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.88 : 1)
            .animation(.spring(duration: 0.35, bounce: 0.5), value: configuration.isPressed)
    }
}

extension View {
    func circleGlass(tintOpacity: Double = 0.10) -> some View {
        glassEffect(.regular.tint(.oceanGlass.opacity(tintOpacity)), in: Circle())
    }
}
