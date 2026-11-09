import SwiftUI

extension Color {
    static let neutrinBlue = Color(red: 0.17, green: 0.42, blue: 0.96)
    static let neutrinDeep = Color(red: 0.08, green: 0.24, blue: 0.78)
    static let neutrinSky = Color(red: 0.33, green: 0.72, blue: 1.0)
}

extension LinearGradient {
    static let neutrin = LinearGradient(
        colors: [.neutrinDeep, .neutrinBlue, .neutrinSky],
        startPoint: .bottomLeading,
        endPoint: .topTrailing
    )
}

/// Frosted "glass" surface used for cards, bars and buttons.
struct GlassBackground: ViewModifier {
    var cornerRadius: CGFloat
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        content
            .background(.ultraThinMaterial, in: shape)
            .overlay(shape.strokeBorder(Color.white.opacity(colorScheme == .dark ? 0.12 : 0.6), lineWidth: 0.5))
            .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.3 : 0.07), radius: 14, x: 0, y: 6)
    }
}

extension View {
    func glass(cornerRadius: CGFloat = 20) -> some View {
        modifier(GlassBackground(cornerRadius: cornerRadius))
    }
}

/// Soft blue-grey backdrop with a flowing wave, as in the concept.
struct AppBackground: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            LinearGradient(
                colors: colorScheme == .dark
                    ? [Color(red: 0.05, green: 0.07, blue: 0.13), Color(red: 0.08, green: 0.11, blue: 0.20)]
                    : [Color(red: 0.95, green: 0.96, blue: 0.99), Color(red: 0.86, green: 0.90, blue: 0.97)],
                startPoint: .top,
                endPoint: .bottom
            )
            WaveShape()
                .fill(
                    LinearGradient(
                        colors: [Color.neutrinBlue.opacity(colorScheme == .dark ? 0.25 : 0.14), .clear],
                        startPoint: .topTrailing,
                        endPoint: .bottomLeading
                    )
                )
                .frame(height: 380)
                .frame(maxHeight: .infinity, alignment: .top)
        }
        .ignoresSafeArea()
    }
}

struct WaveShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: 0, y: rect.height * 0.62))
        path.addCurve(
            to: CGPoint(x: rect.width, y: rect.height * 0.38),
            control1: CGPoint(x: rect.width * 0.35, y: rect.height * 0.18),
            control2: CGPoint(x: rect.width * 0.65, y: rect.height * 0.85)
        )
        path.addLine(to: CGPoint(x: rect.width, y: 0))
        path.addLine(to: .zero)
        path.closeSubpath()
        return path
    }
}

struct SectionHeader: View {
    let title: String
    var actionTitle = "See All"
    var action: (() -> Void)?

    var body: some View {
        HStack {
            Text(title).font(.title3.weight(.bold))
            Spacer()
            if let action {
                Button(action: action) {
                    HStack(spacing: 2) {
                        Text(actionTitle)
                        Image(systemName: "chevron.right").font(.caption.weight(.semibold))
                    }
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Color.neutrinBlue)
                }
            }
        }
    }
}
