import ActivityKit
import Foundation

/// Shows Pip on the lock screen (a Live Activity) and updates it as Helper listens and talks.
/// iOS only allows starting it while the app is open; after that it can be updated from the background.
@MainActor
final class LockScreenCompanion {
    private var activity: Activity<HelperActivityAttributes>?
    private var lastState: HelperActivityAttributes.ContentState?

    func show(mood: CompanionMood, caption: String) {
        guard HelperSettings.shared.lockScreenCompanion, ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        if activity?.activityState != .active {
            activity = Activity<HelperActivityAttributes>.activities.first { $0.activityState == .active }
        }
        if activity != nil {
            update(mood: mood, caption: caption)
            return
        }
        let state = HelperActivityAttributes.ContentState(mood: mood, caption: Self.trim(caption))
        do {
            activity = try Activity.request(attributes: HelperActivityAttributes(),
                                            content: ActivityContent(state: state, staleDate: nil),
                                            pushType: nil)
            lastState = state
        } catch {
            activity = nil
        }
    }

    func update(mood: CompanionMood, caption: String) {
        let state = HelperActivityAttributes.ContentState(mood: mood, caption: Self.trim(caption))
        guard let activity, activity.activityState == .active, state != lastState else { return }
        lastState = state
        Task { await activity.update(ActivityContent(state: state, staleDate: nil)) }
    }

    func hide() {
        let all = Activity<HelperActivityAttributes>.activities
        activity = nil
        lastState = nil
        Task {
            for item in all { await item.end(nil, dismissalPolicy: .immediate) }
        }
    }

    private static func trim(_ caption: String) -> String {
        caption.count > 150 ? "…" + caption.suffix(149) : caption
    }
}
