import ActivityKit
import Foundation

/// The data the lock screen companion shows.
struct HelperActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var mood: CompanionMood
        var caption: String
    }
}
