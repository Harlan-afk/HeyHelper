import AVFoundation

/// Reads Helper's replies out loud with the iPhone's built-in voices, sentence by sentence
/// as the brain writes them. Nothing is pre-recorded.
final class Speaker: NSObject, AVSpeechSynthesizerDelegate {
    /// Called on the main thread when everything queued has been spoken.
    var onIdle: (() -> Void)?

    private let synthesizer = AVSpeechSynthesizer()
    private var pending = Set<ObjectIdentifier>()

    var isSpeaking: Bool { !pending.isEmpty }

    override init() {
        super.init()
        synthesizer.delegate = self
        synthesizer.usesApplicationAudioSession = true
    }

    func speak(_ text: String) {
        let clean = Self.clean(text)
        guard !clean.isEmpty else { return }
        let settings = HelperSettings.shared
        let utterance = AVSpeechUtterance(string: clean)
        utterance.voice = Self.voice(identifier: settings.voiceID)
        utterance.rate = min(AVSpeechUtteranceMaximumSpeechRate, AVSpeechUtteranceDefaultSpeechRate * Float(settings.speechRate))
        utterance.pitchMultiplier = Float(settings.speechPitch)
        utterance.postUtteranceDelay = 0.04
        pending.insert(ObjectIdentifier(utterance))
        synthesizer.speak(utterance)
    }

    /// Stops right away. Does not call `onIdle`.
    func stop() {
        pending.removeAll()
        synthesizer.stopSpeaking(at: .immediate)
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        done(with: utterance)
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        done(with: utterance)
    }

    private func done(with utterance: AVSpeechUtterance) {
        let id = ObjectIdentifier(utterance)
        DispatchQueue.main.async {
            guard self.pending.remove(id) != nil, self.pending.isEmpty else { return }
            self.onIdle?()
        }
    }

    // MARK: - Voices

    /// English voices on this phone, best quality first. Download nicer ones in
    /// iPhone Settings > Accessibility > Spoken Content > Voices.
    static var englishVoices: [AVSpeechSynthesisVoice] {
        AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language.hasPrefix("en") && !$0.voiceTraits.contains(.isNoveltyVoice) }
            .sorted { lhs, rhs in
                if lhs.quality.rawValue != rhs.quality.rawValue { return lhs.quality.rawValue > rhs.quality.rawValue }
                return lhs.name < rhs.name
            }
    }

    static func voice(identifier: String) -> AVSpeechSynthesisVoice? {
        if !identifier.isEmpty, let chosen = AVSpeechSynthesisVoice(identifier: identifier) { return chosen }
        let usEnglish = englishVoices.filter { $0.language == "en-US" }
        return usEnglish.first ?? englishVoices.first ?? AVSpeechSynthesisVoice(language: "en-US")
    }

    /// Removes symbols and emojis that sound silly when read aloud.
    private static func clean(_ text: String) -> String {
        let scalars = text.unicodeScalars.filter { scalar in
            !"*_#`~<>".unicodeScalars.contains(scalar) && !scalar.properties.isEmojiPresentation
        }
        return String(String.UnicodeScalarView(scalars)).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
