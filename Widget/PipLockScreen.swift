import ActivityKit
import SwiftUI
import WidgetKit

@main
struct PipWidgets: WidgetBundle {
    var body: some Widget {
        PipLiveActivity()
    }
}

/// Pip on the lock screen (and in the Dynamic Island on phones that have one).
struct PipLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: HelperActivityAttributes.self) { context in
            PipLockScreenView(state: context.state)
                .activityBackgroundTint(Color(red: 0.05, green: 0.07, blue: 0.18).opacity(0.85))
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    CompanionView(mood: context.state.mood, size: 52)
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(context.state.caption)
                        .font(.subheadline)
                        .lineLimit(3)
                }
            } compactLeading: {
                CompanionView(mood: context.state.mood, size: 24)
            } compactTrailing: {
                Text(PipLockScreenView.title(for: context.state.mood))
                    .font(.caption2)
            } minimal: {
                CompanionView(mood: context.state.mood, size: 22)
            }
        }
    }
}

struct PipLockScreenView: View {
    let state: HelperActivityAttributes.ContentState

    var body: some View {
        HStack(spacing: 14) {
            CompanionView(mood: state.mood, size: 66, time: 0.6)
            VStack(alignment: .leading, spacing: 4) {
                Text(Self.title(for: state.mood))
                    .font(.headline)
                    .foregroundStyle(.white)
                Text(state.caption)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.8))
                    .lineLimit(3)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    static func title(for mood: CompanionMood) -> String {
        switch mood {
        case .sleeping: return "Pip is dozing"
        case .idle: return "Pip"
        case .listening: return "Listening…"
        case .thinking: return "Thinking…"
        case .speaking: return "Pip says"
        }
    }
}
