import AudioToolbox
import SwiftUI
import UIKit

struct ChatMessage: Identifiable, Equatable {
    enum Role { case user, helper }

    let id = UUID()
    let role: Role
    /// What's shown and spoken.
    var text: String
    /// Exactly what the brain wrote, including [commands], so it stays consistent next turn.
    var raw: String
    /// Things Helper added after trying a command (like "I couldn't find that song").
    var notes = ""
}

/// Connects everything: ears -> brain -> voice and hands, plus Pip on the lock screen.
@MainActor
final class AppModel: ObservableObject {
    enum Phase: Equatable {
        case setup
        case loadingBrain
        /// Waiting for the wake phrase.
        case waiting
        case listening
        case thinking
        case speaking
        /// Not listening for the wake phrase; the reason is shown to the user.
        case paused(String)
    }

    @Published private(set) var phase: Phase = .setup { didSet { refreshLockScreen() } }
    @Published private(set) var messages: [ChatMessage] = []
    @Published private(set) var heard = "" { didSet { if phase == .listening { refreshLockScreen() } } }
    @Published private(set) var startupProblem: String?

    let settings = HelperSettings.shared
    let modelStore = ModelStore()
    private let brain = LlamaBrain()
    private let listener = Listener()
    private let speaker = Speaker()
    private let hands = PhoneActions()
    private let lockScreen = LockScreenCompanion()
    private let knowledge = Knowledge()

    private var replyTask: Task<Void, Never>?
    private var turn = 0
    private var replyDone = true
    private var currentReply = ""

    init() {
        listener.onWake = { [weak self] in self?.wakeWordHeard() }
        listener.onTranscript = { [weak self] text in self?.heard = text }
        listener.onCommand = { [weak self] text in self?.handle(text) }
        listener.onProblem = { [weak self] message in self?.phase = .paused(message) }
        speaker.onIdle = { [weak self] in self?.finishTurnIfDone() }
    }

    var isReady: Bool { phase != .setup && phase != .loadingBrain }

    var mood: CompanionMood {
        switch phase {
        case .setup, .waiting: return .idle
        case .loadingBrain, .thinking: return .thinking
        case .listening: return .listening
        case .speaking: return .speaking
        case .paused: return .sleeping
        }
    }

    var statusLine: String {
        switch phase {
        case .setup: return ""
        case .loadingBrain: return "Waking up my brain…"
        case .waiting: return "Say “\(settings.wakePhrase)” or tap me"
        case .listening: return heard.isEmpty ? "I'm listening…" : "“\(heard)”"
        case .thinking: return "Thinking…"
        case .speaking: return "Tap me to stop"
        case .paused(let reason): return reason
        }
    }

    // MARK: - Starting up

    func start() async {
        guard phase == .setup, modelStore.isReady, Permissions.ready else { return }
        startupProblem = nil
        phase = .loadingBrain
        do {
            try await brain.load(path: modelStore.modelURL.path)
        } catch {
            startupProblem = error.localizedDescription
            phase = .setup
            return
        }
        brain.warmUp(PromptBuilder.fixedPrefix(settings: settings))
        resumeListening()
        refreshLockScreen(start: true)
    }

    func resumeListening() {
        guard brain.isLoaded else { return }
        heard = ""
        guard settings.listenEnabled else {
            listener.stop()
            phase = .paused("Wake word is off. Tap me to talk.")
            return
        }
        do {
            try listener.start()
            listener.listenForWake()
            phase = .waiting
        } catch {
            phase = .paused(error.localizedDescription)
        }
    }

    func scenePhaseChanged(_ newPhase: ScenePhase) {
        guard newPhase == .active, isReady else { return }
        if case .paused = phase, settings.listenEnabled { resumeListening() }
        refreshLockScreen(start: true)
    }

    // MARK: - Talking

    func companionTapped() {
        switch phase {
        case .thinking, .speaking:
            stopReply()
            resumeListening()
        case .listening:
            listener.finishNow()
        case .waiting, .paused:
            startManualListening()
        case .setup, .loadingBrain:
            break
        }
    }

    func startManualListening() {
        guard brain.isLoaded else { return }
        stopReply()
        do {
            try listener.start()
        } catch {
            phase = .paused(error.localizedDescription)
            return
        }
        listener.listenForCommand(timeout: 7)
        wakeWordHeard()
    }

    /// Typed questions go through the same brain as spoken ones.
    func send(_ typed: String) {
        handle(typed)
    }

    private func wakeWordHeard() {
        stopReply()
        heard = ""
        phase = .listening
        AudioServicesPlaySystemSound(1113)
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    private func handle(_ spoken: String) {
        let text = spoken.trimmingCharacters(in: .whitespacesAndNewlines)
        heard = ""
        guard !text.isEmpty else {
            resumeListening()
            return
        }
        guard brain.isLoaded else { return }
        listener.pause()
        stopReply()

        messages.append(ChatMessage(role: .user, text: text, raw: text))
        currentReply = ""
        replyDone = false
        turn += 1
        let thisTurn = turn
        phase = .thinking

        let prompt = PromptBuilder.messages(history: messages, settings: settings, phoneInfo: PhoneInfo.summary())
        replyTask = Task { await self.reply(to: prompt, turn: thisTurn) }
    }

    private func reply(to firstPrompt: [LlamaBrain.Message], turn thisTurn: Int) async {
        var prompt = firstPrompt
        var messageIndex: Int?
        var earlierText = ""
        var earlierRaw = ""
        var rounds = 0
        do {
            // Round 1 answers or asks to look something up; round 2 answers with what was found.
            while true {
                var parser = ReplyParser()
                var research: [PhoneAction] = []
                let stream = brain.generate(prompt, pinned: PromptBuilder.pinnedCount(settings: settings),
                                            maxTokens: settings.replyLength.maxTokens)
                for try await piece in stream {
                    guard thisTurn == turn else { return }
                    let output = parser.feed(piece)
                    show(parser, after: earlierText, earlierRaw, at: &messageIndex)
                    research += await act(on: output, turn: thisTurn, messageIndex: messageIndex)
                }
                guard thisTurn == turn else { return }
                let output = parser.finish()
                show(parser, after: earlierText, earlierRaw, at: &messageIndex)
                research += await act(on: output, turn: thisTurn, messageIndex: messageIndex)

                guard let question = research.first, rounds < 2 else { break }
                rounds += 1
                let found = await investigate(question)
                guard thisTurn == turn else { return }
                prompt.append(.init(role: "assistant", content: parser.raw))
                prompt.append(found)
                if let index = messageIndex, messages.indices.contains(index) {
                    earlierText = messages[index].text
                    earlierRaw = messages[index].raw
                    messages[index].notes = ""
                }
            }
        } catch {
            guard thisTurn == turn else { return }
            speaker.speak("Sorry, my brain glitched. Can you say that again?")
            phase = .speaking
        }
        guard thisTurn == turn else { return }
        replyDone = true
        finishTurnIfDone()
    }

    /// Fetches what the brain asked for and hands it back as a message it can read.
    private func investigate(_ action: PhoneAction) async -> LlamaBrain.Message {
        let online = settings.internetEnabled
        switch action {
        case .weather(let place):
            return PromptBuilder.findings(await knowledge.weather(place, online: online), about: "the weather in \(place)")
        case .lookup(let topic):
            return PromptBuilder.findings(await knowledge.lookup(topic, online: online), about: topic)
        default:
            return PromptBuilder.findings(nil, about: "that")
        }
    }

    private func show(_ parser: ReplyParser, after earlierText: String, _ earlierRaw: String, at index: inout Int?) {
        let visible = parser.visible.trimmingCharacters(in: .whitespacesAndNewlines)
        let text = [earlierText, visible].filter { !$0.isEmpty }.joined(separator: " ")
        let raw = [earlierRaw, parser.raw.trimmingCharacters(in: .whitespacesAndNewlines)].filter { !$0.isEmpty }.joined(separator: " ")
        guard !raw.isEmpty else { return }
        currentReply = text
        if let existing = index, messages.indices.contains(existing) {
            let notes = messages[existing].notes
            messages[existing].text = [text, notes].filter { !$0.isEmpty }.joined(separator: " ")
            messages[existing].raw = raw
        } else {
            messages.append(ChatMessage(role: .helper, text: text, raw: raw))
            index = messages.count - 1
        }
    }

    /// Speaks finished sentences and carries out phone commands. Returns lookups for the brain to do.
    private func act(on output: ReplyParser.Output, turn thisTurn: Int, messageIndex: Int?) async -> [PhoneAction] {
        for sentence in output.sentences {
            speaker.speak(sentence)
            if phase == .speaking { refreshLockScreen() } else { phase = .speaking }
        }
        var research: [PhoneAction] = []
        for action in output.actions {
            if action.isResearch {
                research.append(action)
                continue
            }
            if case .remember(let fact) = action {
                settings.remember(fact)
                continue
            }
            guard let note = await hands.perform(action), thisTurn == turn else { continue }
            speaker.speak(note)
            if let index = messageIndex, messages.indices.contains(index) {
                messages[index].notes = [messages[index].notes, note].filter { !$0.isEmpty }.joined(separator: " ")
                messages[index].text = [messages[index].text, note].filter { !$0.isEmpty }.joined(separator: " ")
                currentReply = messages[index].text
            }
            if phase == .speaking { refreshLockScreen() } else { phase = .speaking }
        }
        return research
    }

    private func finishTurnIfDone() {
        guard replyDone, !speaker.isSpeaking else { return }
        guard phase == .speaking || phase == .thinking else { return }
        if settings.followUp {
            // Keep listening a few seconds for a follow-up question, no wake phrase needed.
            do {
                try listener.start()
                listener.listenForCommand(timeout: 5)
                heard = ""
                phase = .listening
            } catch {
                resumeListening()
            }
        } else {
            resumeListening()
        }
    }

    private func stopReply() {
        turn += 1
        brain.cancel()
        replyTask?.cancel()
        replyTask = nil
        speaker.stop()
        replyDone = true
    }

    // MARK: - Settings hooks

    func listeningSettingChanged() {
        switch phase {
        case .waiting, .paused: resumeListening()
        default: break
        }
    }

    func lockScreenSettingChanged() {
        if settings.lockScreenCompanion { refreshLockScreen(start: true) } else { lockScreen.hide() }
    }

    func personalityChanged() {
        guard phase == .waiting || mood == .sleeping else { return }
        brain.warmUp(PromptBuilder.fixedPrefix(settings: settings))
    }

    func forgetConversation() {
        stopReply()
        messages.removeAll()
        if isReady { resumeListening() }
    }

    var learnedCount: Int { knowledge.learnedCount }

    func forgetLearned() {
        knowledge.forgetLearned()
        objectWillChange.send()
    }

    func testVoice() {
        speaker.speak("Hi! I'm Pip, your Helper. This is how I sound.")
    }

    // MARK: - Lock screen

    private func refreshLockScreen(start: Bool = false) {
        let mood: CompanionMood
        let caption: String
        switch phase {
        case .setup:
            return
        case .loadingBrain:
            mood = .thinking
            caption = "Waking up…"
        case .waiting:
            mood = .sleeping
            caption = "Say “\(settings.wakePhrase)” to wake me."
        case .listening:
            mood = .listening
            caption = heard.isEmpty ? "I'm listening…" : heard
        case .thinking:
            mood = .thinking
            caption = messages.last(where: { $0.role == .user })?.text ?? "Thinking…"
        case .speaking:
            mood = .speaking
            caption = currentReply.isEmpty ? "…" : currentReply
        case .paused(let reason):
            mood = .sleeping
            caption = reason
        }
        if start {
            lockScreen.show(mood: mood, caption: caption)
        } else {
            lockScreen.update(mood: mood, caption: caption)
        }
    }
}
