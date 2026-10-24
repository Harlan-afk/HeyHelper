import SwiftUI

/// What Pip is doing right now. Shared with the lock screen.
enum CompanionMood: String, Codable, Hashable {
    case sleeping, idle, listening, thinking, speaking
}

/// Pip, Helper's companion: a little floating orb with big eyes and a glowing antenna.
/// `time` (in seconds) drives the animation; pass a fixed value for a still pose.
struct CompanionView: View {
    var mood: CompanionMood
    var size: CGFloat = 160
    var time: Double = 0

    static let bodyTop = Color(red: 0.33, green: 0.90, blue: 0.80)
    static let bodyBottom = Color(red: 0.25, green: 0.45, blue: 0.97)

    private var s: CGFloat { size }

    var body: some View {
        ZStack {
            if mood == .listening { listeningRings }
            antenna
            orb
            face.offset(y: s * 0.06)
            if mood == .thinking { thinkingDots }
            if mood == .sleeping { sleepyZs }
        }
        .frame(width: s, height: s)
        .offset(y: bob)
    }

    // MARK: - Parts

    private var bob: CGFloat {
        CGFloat(sin(time * (mood == .sleeping ? 1.0 : 2.2))) * s * 0.025
    }

    private var glow: Color {
        switch mood {
        case .listening: return Color(red: 1.0, green: 0.84, blue: 0.30)
        case .thinking: return Color(red: 0.78, green: 0.58, blue: 1.0)
        case .speaking: return Color(red: 0.45, green: 1.0, blue: 0.70)
        case .idle: return Color(red: 0.62, green: 0.95, blue: 1.0)
        case .sleeping: return Color(white: 0.6)
        }
    }

    private var orb: some View {
        ZStack {
            Circle()
                .fill(LinearGradient(colors: [Self.bodyTop, Self.bodyBottom], startPoint: .top, endPoint: .bottom))
                .shadow(color: Self.bodyBottom.opacity(0.5), radius: s * 0.06, y: s * 0.03)
            Ellipse()
                .fill(Color.white.opacity(0.35))
                .frame(width: s * 0.22, height: s * 0.11)
                .rotationEffect(.degrees(-30))
                .offset(x: -s * 0.15, y: -s * 0.17)
        }
        .frame(width: s * 0.72, height: s * 0.72)
        .offset(y: s * 0.06)
    }

    private var antenna: some View {
        let sway = mood == .sleeping ? -14.0 : sin(time * 1.7) * 9
        return VStack(spacing: 0) {
            Circle()
                .fill(glow)
                .frame(width: s * 0.11, height: s * 0.11)
                .shadow(color: glow.opacity(mood == .sleeping ? 0 : 0.9), radius: s * 0.04)
            Capsule()
                .fill(Self.bodyTop)
                .frame(width: s * 0.035, height: s * 0.14)
        }
        .rotationEffect(.degrees(sway), anchor: .bottom)
        .offset(y: -s * 0.385)
    }

    private var face: some View {
        let blinking = time.truncatingRemainder(dividingBy: 4.2) < 0.14
        let eyesClosed = mood == .sleeping || (blinking && mood != .listening)
        return ZStack {
            HStack(spacing: s * 0.11) {
                eye(closed: eyesClosed)
                eye(closed: eyesClosed)
            }
            .offset(y: -s * 0.04)

            HStack(spacing: s * 0.34) {
                cheek
                cheek
            }
            .offset(y: s * 0.06)

            mouth.offset(y: s * 0.11)
        }
    }

    @ViewBuilder
    private func eye(closed: Bool) -> some View {
        let width = s * (mood == .listening ? 0.16 : 0.14)
        let height = s * (mood == .listening ? 0.19 : 0.17)
        if closed {
            SmileArc()
                .stroke(Color(white: 0.1), style: StrokeStyle(lineWidth: s * 0.022, lineCap: .round))
                .frame(width: width, height: height * 0.3)
                .frame(width: width, height: height)
        } else {
            ZStack {
                Ellipse().fill(Color.white)
                Circle()
                    .fill(Color(white: 0.08))
                    .frame(width: width * 0.58)
                    .offset(pupilOffset(width: width))
                Circle()
                    .fill(Color.white)
                    .frame(width: width * 0.2)
                    .offset(x: pupilOffset(width: width).width + width * 0.1, y: pupilOffset(width: width).height - width * 0.12)
            }
            .frame(width: width, height: height)
        }
    }

    private func pupilOffset(width: CGFloat) -> CGSize {
        switch mood {
        case .thinking: return CGSize(width: width * 0.14, height: -width * 0.22)
        case .speaking: return CGSize(width: CGFloat(sin(time * 0.8)) * width * 0.06, height: width * 0.04)
        default: return CGSize(width: 0, height: width * 0.06)
        }
    }

    private var cheek: some View {
        Ellipse()
            .fill(Color(red: 1.0, green: 0.55, blue: 0.65).opacity(0.55))
            .frame(width: s * 0.09, height: s * 0.05)
    }

    @ViewBuilder
    private var mouth: some View {
        switch mood {
        case .speaking:
            let open = 0.25 + 0.75 * abs(sin(time * 9.0))
            Capsule()
                .fill(Color(red: 0.25, green: 0.05, blue: 0.12))
                .frame(width: s * 0.11, height: s * (0.025 + 0.065 * open))
        case .listening:
            Ellipse()
                .fill(Color(red: 0.25, green: 0.05, blue: 0.12))
                .frame(width: s * 0.06, height: s * 0.07)
        case .thinking:
            SmileArc()
                .stroke(Color(white: 0.1), style: StrokeStyle(lineWidth: s * 0.02, lineCap: .round))
                .frame(width: s * 0.07, height: s * 0.02)
                .offset(x: s * 0.03)
        case .idle, .sleeping:
            SmileArc()
                .stroke(Color(white: 0.1), style: StrokeStyle(lineWidth: s * 0.02, lineCap: .round))
                .frame(width: s * 0.12, height: s * 0.045)
        }
    }

    private var listeningRings: some View {
        ZStack {
            ForEach(0..<2, id: \.self) { index in
                let phase = (time * 0.9 + Double(index) * 0.5).truncatingRemainder(dividingBy: 1)
                Circle()
                    .stroke(glow, lineWidth: s * 0.02)
                    .frame(width: s * 0.72, height: s * 0.72)
                    .scaleEffect(1 + CGFloat(phase) * 0.38)
                    .opacity((1 - phase) * 0.8)
            }
        }
        .offset(y: s * 0.06)
    }

    private var thinkingDots: some View {
        HStack(spacing: s * 0.03) {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .fill(Color.white)
                    .frame(width: s * 0.05, height: s * 0.05)
                    .opacity(0.35 + 0.65 * max(0, sin(time * 4 - Double(index) * 0.8)))
            }
        }
        .offset(x: s * 0.36, y: -s * 0.36)
    }

    private var sleepyZs: some View {
        ZStack {
            ForEach(0..<2, id: \.self) { index in
                let rise = (time * 0.35 + Double(index) * 0.5).truncatingRemainder(dividingBy: 1)
                Text("z")
                    .font(.system(size: s * (0.09 + 0.04 * CGFloat(index)), weight: .heavy, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.8 * (1 - rise * 0.7)))
                    .offset(x: s * (0.3 + 0.08 * CGFloat(index)), y: -s * (0.22 + 0.1 * CGFloat(index)) - s * 0.08 * CGFloat(rise))
            }
        }
    }
}

/// A curve like ‿, used for smiles and closed eyes.
struct SmileArc: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY),
                          control: CGPoint(x: rect.midX, y: rect.maxY * 2 - rect.minY))
        return path
    }
}
