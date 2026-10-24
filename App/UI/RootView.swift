import SwiftUI

enum Theme {
    static let background = LinearGradient(
        colors: [Color(red: 0.04, green: 0.06, blue: 0.16), Color(red: 0.10, green: 0.14, blue: 0.33)],
        startPoint: .top, endPoint: .bottom)
    static let card = Color.white.opacity(0.08)
    static let accent = Color(red: 0.33, green: 0.90, blue: 0.80)
    static let userBubble = Color(red: 0.25, green: 0.45, blue: 0.97)
}

struct RootView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            if model.phase == .setup {
                SetupView()
            } else {
                HomeView()
            }
        }
        .task { await model.start() }
    }
}

/// Pip, animated.
struct LivePip: View {
    var mood: CompanionMood
    var size: CGFloat

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
            CompanionView(mood: mood, size: size, time: timeline.date.timeIntervalSinceReferenceDate)
        }
    }
}
