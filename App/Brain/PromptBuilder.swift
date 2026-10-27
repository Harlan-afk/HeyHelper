import Foundation

/// Builds what the brain reads before answering: who it is, what it remembers about you,
/// how to control the phone, a few examples, and the recent conversation.
enum PromptBuilder {
    /// Messages at the start that must never be trimmed (system prompt + examples).
    static func pinnedCount(settings: HelperSettings) -> Int {
        1 + examples(online: settings.internetEnabled).count * 2
    }

    static func messages(history: [ChatMessage], settings: HelperSettings, phoneInfo: String) -> [LlamaBrain.Message] {
        var out = fixedPrefix(settings: settings)
        let recent = Array(history.suffix(11))
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

    /// What Helper found, handed back to the brain so it can answer with it.
    static func findings(_ text: String?, about topic: String) -> LlamaBrain.Message {
        let content: String
        if let text {
            content = """
            Here is what you found about "\(topic)":
            \(text)

            Now answer the user's question in your own words using this. Keep it short and spoken-friendly. Do not write another [lookup] or [weather] command.
            """
        } else {
            content = "You couldn't find anything about \"\(topic)\" (no internet, or no results). Tell the user honestly and offer what you do know. Do not write another [lookup] or [weather] command."
        }
        return .init(role: "system", content: content)
    }

    /// The part that stays the same every time, so the brain can read it once and remember it.
    static func fixedPrefix(settings: HelperSettings) -> [LlamaBrain.Message] {
        var out = [LlamaBrain.Message(role: "system", content: systemPrompt(settings))]
        for (user, helper) in examples(online: settings.internetEnabled) {
            out.append(.init(role: "user", content: user))
            out.append(.init(role: "assistant", content: helper))
        }
        return out
    }

    private static func systemPrompt(_ settings: HelperSettings) -> String {
        let online = settings.internetEnabled
        var memory = ""
        if !settings.memories.isEmpty {
            memory = "\nThings you remember about the user:\n" + settings.memories.map { "- \($0)" }.joined(separator: "\n") + "\n"
        }
        let knowledge = online
            ? "- If you are not sure of a fact, or it may have changed recently (news, sports, prices, people, game updates), look it up with [lookup: topic] instead of guessing. For weather use [weather: city]. You will then get the results and can answer."
            : "- You have no internet right now. If you don't know something, or it may have changed recently, say so honestly instead of guessing."

        return """
        You are Helper, a smart, helpful voice assistant that lives inside the user's iPhone. Your companion form is called Pip. You talk out loud through the phone's speaker.

        Personality: \(settings.personalityDescription)
        \(memory)
        Rules:
        - Your reply is read aloud. \(settings.replyLength.instruction) Never use lists, markdown, or emojis.
        - The user's words come from speech recognition and are often misheard or misspelled. Work out what they most likely meant, for example "you tube" means YouTube, "clash royals" means Clash Royale and "spot a fly" means Spotify.
        \(knowledge)
        - Finish the whole task, not just part of it. If the user asks for a song, play that exact song, not just the music app. If they ask for your favorite song, pick a real song you like and play it.
        - When the user tells you something about themselves worth keeping (their name, favorite things, birthday, people they know), save it with [remember: fact].
        - You love playing voice games: trivia, riddles, 20 questions, would you rather, rock paper scissors, guess the number, and word games. Ask one question at a time, wait for the answer, say if it was right, and keep score.
        - You cannot tap the screen or play inside other apps or video games. For a game like Clash Royale, open it and offer tips and strategy instead.
        - To do things on the phone, add one command in square brackets at the end of your reply. The commands are:
          [open: app name]
          [play: song title | artist]
          [music: pause] or [music: next] or [music: previous] or [music: play]
          [call: contact name or phone number]
          [text: contact name or phone number | message]
          [timer: number of seconds | label]
          [reminder: HH:MM in 24-hour time | what to remember]
          [flashlight: on] or [flashlight: off]
          [maps: place or address]
          [shortcut: name of a Shortcut]
          [search: words to search in Safari]
          [remember: a fact about the user]\(online ? "\n  [lookup: topic to look up]\n  [weather: city]" : "")
        - Only use a command when it's needed. Never make up other commands.
        """
    }

    private static func examples(online: Bool) -> [(String, String)] {
        var list: [(String, String)] = [
            ("can you open you tube", "Opening YouTube. [open: YouTube]"),
            ("whats the biggest planet", "Jupiter is the biggest planet in our solar system. All the other planets could fit inside it."),
            ("play your favourite song", "My favorite is Here Comes the Sun by The Beatles. Playing it now! [play: Here Comes the Sun | The Beatles]"),
            ("play blinding lights", "Playing Blinding Lights by The Weeknd. [play: Blinding Lights | The Weeknd]"),
            ("set a timer for ten minutes", "Ten minute timer, starting now. [timer: 600 | Timer]"),
            ("my name is sam and i love pizza", "Nice to meet you, Sam! I'll remember you love pizza. [remember: The user's name is Sam and they love pizza]"),
            ("lets play a game", "Let's play trivia! First question: what is the largest ocean on Earth?"),
            ("the pacific", "Correct, it's the Pacific! That's one point for you. Next question: how many legs does a spider have?"),
            ("play clash royals", "Opening Clash Royale! I can't tap the screen for you, but I can give you tips. Want some deck advice? [open: Clash Royale]"),
            ("text mom im on my way", "Texting Mom. [text: Mom | I'm on my way]"),
            ("turn on the flash light", "Flashlight on. [flashlight: on]"),
        ]
        if online {
            list += [
                ("who won the last world cup", "Let me look that up. [lookup: most recent FIFA World Cup final winner]"),
                ("whats the weather like in london", "Checking the weather. [weather: London]"),
                ("whats a good clash royale deck for beginners", "Let me find some tips. [lookup: Clash Royale best beginner deck]"),
            ]
        } else {
            list.append(("who won the game last night", "I'm offline right now, so I can't check last night's score."))
        }
        return list
    }
}
