import SwiftUI

enum Personality: String, CaseIterable, Identifiable {
    case friendly, funny, calm, custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .friendly: return "Friendly & chill"
        case .funny: return "Funny"
        case .calm: return "Calm & smart"
        case .custom: return "Make my own"
        }
    }

    var description: String {
        switch self {
        case .friendly: return "You are friendly, warm and laid-back, like a chill best friend. Casual words are fine."
        case .funny: return "You are playful and funny. Add a quick joke or witty remark when it fits, but still actually help."
        case .calm: return "You are calm, clear, polite and thoughtful, and you explain things simply."
        case .custom: return ""
        }
    }
}

enum ReplyLength: String, CaseIterable, Identifiable {
    case short, medium, long

    var id: String { rawValue }

    var title: String {
        switch self {
        case .short: return "Short"
        case .medium: return "Medium"
        case .long: return "Long"
        }
    }

    var instruction: String {
        switch self {
        case .short: return "Keep it to one or two short sentences."
        case .medium: return "Keep it to two to four sentences."
        case .long: return "You may use up to a short paragraph when the question needs it."
        }
    }

    var maxTokens: Int {
        switch self {
        case .short: return 120
        case .medium: return 200
        case .long: return 320
        }
    }
}

enum WakeSensitivity: String, CaseIterable, Identifiable {
    case strict, normal, relaxed

    var id: String { rawValue }

    var title: String {
        switch self {
        case .strict: return "Strict"
        case .normal: return "Normal"
        case .relaxed: return "Relaxed"
        }
    }

    /// How many letters can be misheard and still count as the wake phrase.
    func allowedEdits(forLength length: Int) -> Int {
        switch self {
        case .strict: return length >= 8 ? 1 : 0
        case .normal: return length / 4
        case .relaxed: return length / 3
        }
    }
}

enum MusicApp: String, CaseIterable, Identifiable {
    case appleMusic, spotify

    var id: String { rawValue }

    var title: String {
        switch self {
        case .appleMusic: return "Apple Music"
        case .spotify: return "Spotify"
        }
    }
}

/// An app the user taught Helper to open: a link like `camera://` or the name of a Shortcut.
struct CustomApp: Codable, Identifiable, Hashable {
    var id = UUID()
    var name: String
    var target: String

    var url: URL? {
        let trimmed = target.trimmingCharacters(in: .whitespaces)
        if trimmed.contains(":") { return URL(string: trimmed) }
        guard let encoded = trimmed.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else { return nil }
        return URL(string: "shortcuts://run-shortcut?name=\(encoded)")
    }
}

/// Everything you can change in Helper's settings. Saved on the phone.
final class HelperSettings: ObservableObject {
    static let shared = HelperSettings()
    private static let defaults = UserDefaults.standard

    @Published var personality: Personality { didSet { save(personality.rawValue, "personality") } }
    @Published var customPersonality: String { didSet { save(customPersonality, "customPersonality") } }
    @Published var replyLength: ReplyLength { didSet { save(replyLength.rawValue, "replyLength") } }
    @Published var voiceID: String { didSet { save(voiceID, "voiceID") } }
    @Published var speechRate: Double { didSet { save(speechRate, "speechRate") } }
    @Published var speechPitch: Double { didSet { save(speechPitch, "speechPitch") } }
    @Published var listenEnabled: Bool { didSet { save(listenEnabled, "listenEnabled") } }
    @Published var wakePhrase: String { didSet { save(wakePhrase, "wakePhrase") } }
    @Published var wakeSensitivity: WakeSensitivity { didSet { save(wakeSensitivity.rawValue, "wakeSensitivity") } }
    @Published var followUp: Bool { didSet { save(followUp, "followUp") } }
    @Published var lockScreenCompanion: Bool { didSet { save(lockScreenCompanion, "lockScreenCompanion") } }
    @Published var internetEnabled: Bool { didSet { save(internetEnabled, "internetEnabled") } }
    @Published var musicApp: MusicApp { didSet { save(musicApp.rawValue, "musicApp") } }
    /// Facts the user asked Helper to remember. Shown in Settings, where they can be deleted.
    @Published var memories: [String] { didSet { save(memories, "memories") } }
    @Published var customApps: [CustomApp] {
        didSet { save((try? JSONEncoder().encode(customApps)) ?? Data(), "customApps") }
    }

    private init() {
        let d = Self.defaults
        personality = Personality(rawValue: d.string(forKey: "personality") ?? "") ?? .friendly
        customPersonality = d.string(forKey: "customPersonality") ?? "You are an excited space nerd who loves fun facts."
        replyLength = ReplyLength(rawValue: d.string(forKey: "replyLength") ?? "") ?? .short
        voiceID = d.string(forKey: "voiceID") ?? ""
        speechRate = d.object(forKey: "speechRate") as? Double ?? 1.0
        speechPitch = d.object(forKey: "speechPitch") as? Double ?? 1.05
        listenEnabled = d.object(forKey: "listenEnabled") as? Bool ?? true
        wakePhrase = d.string(forKey: "wakePhrase") ?? "Hey Helper"
        wakeSensitivity = WakeSensitivity(rawValue: d.string(forKey: "wakeSensitivity") ?? "") ?? .normal
        followUp = d.object(forKey: "followUp") as? Bool ?? true
        lockScreenCompanion = d.object(forKey: "lockScreenCompanion") as? Bool ?? true
        internetEnabled = d.object(forKey: "internetEnabled") as? Bool ?? true
        musicApp = MusicApp(rawValue: d.string(forKey: "musicApp") ?? "") ?? .appleMusic
        memories = d.stringArray(forKey: "memories") ?? []
        customApps = d.data(forKey: "customApps").flatMap { try? JSONDecoder().decode([CustomApp].self, from: $0) } ?? []
    }

    private func save(_ value: Any, _ key: String) {
        Self.defaults.set(value, forKey: key)
    }

    func remember(_ fact: String) {
        let clean = fact.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty, !memories.contains(where: { $0.caseInsensitiveCompare(clean) == .orderedSame }) else { return }
        memories.append(clean)
        if memories.count > 40 { memories.removeFirst(memories.count - 40) }
    }

    var personalityDescription: String {
        if personality == .custom {
            let custom = customPersonality.trimmingCharacters(in: .whitespacesAndNewlines)
            return custom.isEmpty ? Personality.friendly.description : custom
        }
        return personality.description
    }
}
