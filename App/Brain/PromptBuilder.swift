import Foundation

/// Builds what the brain reads before answering: who it is, how to control the phone,
/// a few examples, and the recent conversation.
enum PromptBuilder {
    /// Messages at the start that must never be trimmed (system prompt + examples).
    static var pinnedCount: Int { 1 + examples.count * 2 }

    static func messages(history: [ChatMessage], settings: HelperSettings, phoneInfo: String) -> [LlamaBrain.Message] {
        var out = fixedPrefix(settings: settings)
        let recent = Array(history.suffix(9))
        for (index, message) in recent.enumerated() {
            let isLast = index == recent.count - 1
            if isLast && message.role == .user {
                out.append(.init(role: "system", content: "Phone info (only mention if asked): \(phoneInfo)"))
            }
            switch message.role {
            case .user: out.append(.init(role: "user", content: message.text))
            case .helper: out.append(.init(role: "assistant", content: message.raw))
            }
        }
        return out
    }

    /// The part that stays the same every time, so the brain can read it once and remember it.
    static func fixedPrefix(settings: HelperSettings) -> [LlamaBrain.Message] {
        var out = [LlamaBrain.Message(role: "system", content: systemPrompt(settings))]
        for (user, helper) in examples {
            out.append(.init(role: "user", content: user))
            out.append(.init(role: "assistant", content: helper))
        }
        return out
    }

    private static func systemPrompt(_ settings: HelperSettings) -> String {
        """
        You are Helper, a voice assistant that lives inside the user's iPhone. You talk out loud through the phone's speaker.

        Personality: \(settings.personalityDescription)

        Rules:
        - Your reply is read aloud. \(settings.replyLength.instruction) Never use lists, markdown, or emojis.
        - The user's words come from speech recognition and are often misheard or misspelled. Work out what they most likely meant, for example "you tube" means YouTube and "spot a fly" means Spotify.
        - You have no internet. If you don't know something, or it may have changed recently (news, scores, prices, weather), say so honestly instead of guessing.
        - To control the phone, add exactly one command in square brackets at the end of your reply. The commands are:
          [open: app name]
          [call: contact name or phone number]
          [text: contact name or phone number | message]
          [timer: number of seconds | label]
          [reminder: HH:MM in 24-hour time | what to remember]
          [flashlight: on] or [flashlight: off]
          [music: play] or [music: pause] or [music: next] or [music: previous]
          [maps: place or address]
          [shortcut: name of a Shortcut]
          [search: words to search the web for]
        - Only use a command when the user asks you to do something on the phone. Never make up other commands.
        """
    }

    private static let examples: [(String, String)] = [
        ("can you open you tube", "Opening YouTube. [open: YouTube]"),
        ("whats the biggest planet", "Jupiter is the biggest planet in our solar system. It's so big that all the other planets could fit inside it."),
        ("set a timer for ten minutes", "Ten minute timer, starting now. [timer: 600 | Timer]"),
        ("text mom im on my way", "Texting Mom. [text: Mom | I'm on my way]"),
        ("who won the game last night", "I can't go on the internet, so I don't know last night's score. I can search it for you if you want."),
        ("turn on the flash light", "Flashlight on. [flashlight: on]"),
        ("remind me to take out the trash at 7 pm", "Okay, I'll remind you at 7 PM. [reminder: 19:00 | Take out the trash]"),
        ("how do i say thank you in spanish", "In Spanish, thank you is gracias."),
    ]
}
