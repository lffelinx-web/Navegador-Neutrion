import SwiftUI

/// Small vector illustrations (no bundled photos needed).
struct ArtworkView: View {
    let artwork: Artwork

    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            switch artwork {
            case .mountains: mountains(size)
            case .leaf: leaf(size)
            case .waves: waves(size)
            case .sunset: sunset(size)
            }
        }
        .clipped()
        .accessibilityHidden(true)
    }

    private func mountains(_ size: CGSize) -> some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.98, green: 0.86, blue: 0.82),
                                    Color(red: 0.66, green: 0.75, blue: 0.92),
                                    Color(red: 0.42, green: 0.55, blue: 0.80)],
                           startPoint: .top, endPoint: .bottom)
            RidgeShape(points: [(0, 0.62), (0.2, 0.45), (0.38, 0.22), (0.5, 0.34), (0.66, 0.18), (0.82, 0.4), (1, 0.5)])
                .fill(LinearGradient(colors: [.white, Color(red: 0.55, green: 0.64, blue: 0.84)],
                                     startPoint: .top, endPoint: .bottom))
            RidgeShape(points: [(0, 0.72), (0.25, 0.55), (0.45, 0.68), (0.7, 0.5), (1, 0.66)])
                .fill(Color(red: 0.24, green: 0.34, blue: 0.60))
            LinearGradient(colors: [.clear, .white.opacity(0.85)], startPoint: .center, endPoint: .bottom)
        }
    }

    private func leaf(_ size: CGSize) -> some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.92, green: 0.94, blue: 0.90), Color(red: 0.78, green: 0.86, blue: 0.80)],
                           startPoint: .top, endPoint: .bottom)
            leafShape(size, angle: -35, x: 0.38, y: 0.62, scale: 1.0)
            leafShape(size, angle: 30, x: 0.64, y: 0.55, scale: 0.9)
            leafShape(size, angle: -5, x: 0.52, y: 0.42, scale: 0.75)
        }
    }

    private func leafShape(_ size: CGSize, angle: Double, x: CGFloat, y: CGFloat, scale: CGFloat) -> some View {
        Ellipse()
            .fill(LinearGradient(colors: [Color(red: 0.45, green: 0.66, blue: 0.36), Color(red: 0.18, green: 0.40, blue: 0.22)],
                                 startPoint: .top, endPoint: .bottom))
            .frame(width: size.width * 0.28 * scale, height: size.height * 0.85 * scale)
            .rotationEffect(.degrees(angle))
            .position(x: size.width * x, y: size.height * y)
    }

    private func waves(_ size: CGSize) -> some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.86, green: 0.90, blue: 0.97), Color(red: 0.45, green: 0.62, blue: 0.88)],
                           startPoint: .topTrailing, endPoint: .bottomLeading)
            RibbonShape(offset: 0)
                .fill(LinearGradient(colors: [.white.opacity(0.95), .white.opacity(0.2)],
                                     startPoint: .topTrailing, endPoint: .bottomLeading))
            RibbonShape(offset: 0.22)
                .fill(Color(red: 0.30, green: 0.48, blue: 0.82).opacity(0.55))
        }
    }

    private func sunset(_ size: CGSize) -> some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.48, green: 0.52, blue: 0.80),
                                    Color(red: 0.96, green: 0.70, blue: 0.62),
                                    Color(red: 0.99, green: 0.85, blue: 0.70)],
                           startPoint: .top, endPoint: .center)
            VStack(spacing: 0) {
                Spacer()
                LinearGradient(colors: [Color(red: 0.55, green: 0.55, blue: 0.78), Color(red: 0.25, green: 0.32, blue: 0.58)],
                               startPoint: .top, endPoint: .bottom)
                    .frame(height: size.height * 0.42)
            }
            Capsule()
                .fill(Color.white.opacity(0.5))
                .frame(width: size.width * 0.3, height: 2)
                .position(x: size.width * 0.5, y: size.height * 0.64)
        }
    }
}

private struct RidgeShape: Shape {
    let points: [(CGFloat, CGFloat)]

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        for (x, y) in points {
            path.addLine(to: CGPoint(x: rect.minX + x * rect.width, y: rect.minY + y * rect.height))
        }
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

private struct RibbonShape: Shape {
    let offset: CGFloat

    func path(in rect: CGRect) -> Path {
        let w = rect.width, h = rect.height, o = offset * h
        var path = Path()
        path.move(to: CGPoint(x: 0, y: h * 0.75 + o))
        path.addCurve(to: CGPoint(x: w, y: h * 0.1 + o),
                      control1: CGPoint(x: w * 0.4, y: h * 0.9 + o),
                      control2: CGPoint(x: w * 0.6, y: h * 0.05 + o))
        path.addLine(to: CGPoint(x: w, y: h * 0.32 + o))
        path.addCurve(to: CGPoint(x: 0, y: h * 0.95 + o),
                      control1: CGPoint(x: w * 0.6, y: h * 0.3 + o),
                      control2: CGPoint(x: w * 0.4, y: h * 1.05 + o))
        path.closeSubpath()
        return path
    }
}
