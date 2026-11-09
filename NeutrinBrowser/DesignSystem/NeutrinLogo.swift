import SwiftUI

/// The official app icon, rounded like on the Home Screen.
struct AppIconImage: View {
    var size: CGFloat = 76

    var body: some View {
        Image("AppLogo")
            .resizable()
            .interpolation(.high)
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: size * 0.225, style: .continuous))
            .shadow(color: Color.neutrinDeep.opacity(0.25), radius: size * 0.12, y: size * 0.06)
            .accessibilityHidden(true)
    }
}

/// The flowing "N" mark (used small, e.g. on the start-page tab card).
struct NeutrinLogo: View {
    var body: some View {
        GeometryReader { geometry in
            let w = geometry.size.width
            let h = geometry.size.height
            Path { path in
                path.move(to: CGPoint(x: w * 0.12, y: h * 0.85))
                path.addCurve(to: CGPoint(x: w * 0.35, y: h * 0.20),
                              control1: CGPoint(x: w * 0.18, y: h * 0.55),
                              control2: CGPoint(x: w * 0.25, y: h * 0.20))
                path.addCurve(to: CGPoint(x: w * 0.62, y: h * 0.80),
                              control1: CGPoint(x: w * 0.48, y: h * 0.20),
                              control2: CGPoint(x: w * 0.50, y: h * 0.80))
                path.addCurve(to: CGPoint(x: w * 0.88, y: h * 0.15),
                              control1: CGPoint(x: w * 0.75, y: h * 0.80),
                              control2: CGPoint(x: w * 0.82, y: h * 0.45))
            }
            .stroke(LinearGradient.neutrin,
                    style: StrokeStyle(lineWidth: h * 0.2, lineCap: .round, lineJoin: .round))
            .shadow(color: Color.neutrinBlue.opacity(0.35), radius: h * 0.08, x: 0, y: h * 0.05)
        }
        .aspectRatio(1.4, contentMode: .fit)
        .accessibilityHidden(true)
    }
}
