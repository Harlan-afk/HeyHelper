import Foundation

/// Something the brain asked to do on the phone, written like `[open: YouTube]`.
enum PhoneAction: Equatable {
    case open(String)
    case call(String)
    case text(to: String, message: String)
    case timer(seconds: Int, label: String)
    case reminder(hour: Int, minute: Int, what: String)
    case flashlight(on: Bool)
    case music(String)
    case maps(String)
    case shortcut(String)
    case search(String)
    case play(song: String, artist: String)
    case lookup(String)
    case weather(String)
    case remember(String)

    /// Commands that fetch information for the brain instead of doing something on the phone.
    var isResearch: Bool {
        switch self {
        case .lookup, .weather: return true
        default: return false
        }
    }

    /// Parses the inside of a bracket, e.g. `timer: 300 | Pizza`. Forgiving about spacing and case.
    static func parse(_ inside: String) -> PhoneAction? {
        guard let colon = inside.firstIndex(of: ":") else { return nil }
        let name = inside[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
        let rest = String(inside[inside.index(after: colon)...])
        let parts = rest.split(separator: "|", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        let first = parts.first ?? ""
        let second = parts.count > 1 ? parts[1] : ""
        guard !first.isEmpty else { return nil }

        switch name {
        case "open", "open app", "launch":
            return .open(first)
        case "call", "phone":
            return .call(first)
        case "text", "message", "sms":
            return .text(to: first, message: second)
        case "timer":
            guard let seconds = parseSeconds(first) else { return nil }
            return .timer(seconds: seconds, label: second.isEmpty ? "Timer" : second)
        case "reminder", "alarm", "remind":
            guard let clock = parseClock(first) else { return nil }
            return .reminder(hour: clock.hour, minute: clock.minute, what: second.isEmpty ? "Reminder" : second)
        case "flashlight", "torch", "light":
            let value = first.lowercased()
            return .flashlight(on: !(value.contains("off") || value.contains("false")))
        case "music", "media":
            return .music(first.lowercased())
        case "play", "song", "play song":
            let lower = first.lowercased()
            if ["play", "pause", "stop", "next", "skip", "previous", "back", "music"].contains(lower) { return .music(lower) }
            return .play(song: first, artist: second)
        case "lookup", "look up", "find":
            return .lookup(first)
        case "weather", "forecast":
            return .weather(first)
        case "remember", "memory", "note":
            return .remember(first)
        case "maps", "map", "directions", "navigate":
            return .maps(first)
        case "shortcut", "run shortcut":
            return .shortcut(first)
        case "search", "web", "google":
            return .search(first)
        default:
            return nil
        }
    }

    private static func parseSeconds(_ text: String) -> Int? {
        let lower = text.lowercased()
        let digits = lower.prefix { $0.isNumber || $0 == "." }
        guard let value = Double(digits), value > 0 else { return nil }
        if lower.contains("hour") { return Int(value * 3600) }
        if lower.contains("min") { return Int(value * 60) }
        return Int(value)
    }

    private static func parseClock(_ text: String) -> (hour: Int, minute: Int)? {
        let lower = text.lowercased()
        let numbers = lower.split(whereSeparator: { !$0.isNumber }).compactMap { Int($0) }
        guard var hour = numbers.first else { return nil }
        let minute = numbers.count > 1 ? numbers[1] : 0
        if lower.contains("pm"), hour < 12 { hour += 12 }
        if lower.contains("am"), hour == 12 { hour = 0 }
        guard (0..<24).contains(hour), (0..<60).contains(minute) else { return nil }
        return (hour, minute)
    }
}
