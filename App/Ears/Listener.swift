import AVFoundation
import Speech

/// Keeps the microphone open, waits for the wake phrase, then captures what you say next.
/// Speech recognition runs on the iPhone itself; no audio is sent anywhere.
/// Everything here is called on the main thread.
final class Listener: NSObject {
    enum Mode { case off, paused, wake, command }

    enum ListenerError: LocalizedError {
        case noRecognizer, noMicrophone

        var errorDescription: String? {
            switch self {
            case .noRecognizer: return "Speech recognition isn't available on this iPhone."
            case .noMicrophone: return "I can't reach the microphone. Check Settings > Helper > Microphone."
            }
        }
    }

    var onWake: (() -> Void)?
    var onTranscript: ((String) -> Void)?
    var onCommand: ((String) -> Void)?
    /// Called when listening stopped on its own and needs the app to be opened again.
    var onProblem: ((String) -> Void)?

    private(set) var mode: Mode = .off
    var isOnDevice: Bool { recognizer?.supportsOnDeviceRecognition ?? false }

    private let engine = AVAudioEngine()
    private var recognizer: SFSpeechRecognizer?
    private var task: SFSpeechRecognitionTask?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private let requestLock = NSLock()
    private var session = 0
    private var sessionStarted = Date()
    private var commandText = ""
    private var commandFromWake = false
    private var silenceTimer: Timer?
    private var limitTimer: Timer?
    private var restartWork: DispatchWorkItem?
    private var observing = false

    // MARK: - Control

    func start() throws {
        if recognizer == nil { recognizer = Self.makeRecognizer() }
        guard recognizer != nil else { throw ListenerError.noRecognizer }
        try configureAudioSession()
        try startEngine()
        observeAudioEvents()
        if mode == .off { mode = .paused }
    }

    func stop() {
        pause()
        engine.stop()
        engine.inputNode.removeTap(onBus: 0)
        mode = .off
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    func pause() {
        cancelTimers()
        if mode != .off { mode = .paused }
        endRecognition()
    }

    /// Waits for "Hey Helper".
    func listenForWake() {
        guard mode != .off else { return }
        cancelTimers()
        mode = .wake
        beginRecognition()
    }

    /// Listens for a question right away (follow-up, or after tapping the companion).
    func listenForCommand(timeout: TimeInterval) {
        guard mode != .off else { return }
        cancelTimers()
        mode = .command
        commandText = ""
        commandFromWake = false
        beginRecognition()
        armSilence(after: timeout)
        armLimit()
    }

    /// Stop waiting and use what was heard so far.
    func finishNow() {
        if mode == .command { finishCommand() }
    }

    // MARK: - Audio

    private static func makeRecognizer() -> SFSpeechRecognizer? {
        var locales: [Locale] = []
        if Locale.current.language.languageCode?.identifier == "en" { locales.append(Locale.current) }
        locales.append(Locale(identifier: "en-US"))
        for locale in locales {
            if let recognizer = SFSpeechRecognizer(locale: locale), recognizer.supportsOnDeviceRecognition {
                return recognizer
            }
        }
        return SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    }

    private func configureAudioSession() throws {
        let audio = AVAudioSession.sharedInstance()
        try audio.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetooth, .mixWithOthers])
        try audio.setAllowHapticsAndSystemSoundsDuringRecording(true)
        try audio.setActive(true)
    }

    private func startEngine() throws {
        guard !engine.isRunning else { return }
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else { throw ListenerError.noMicrophone }
        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            self?.feed(buffer)
        }
        engine.prepare()
        try engine.start()
    }

    /// Runs on the audio thread.
    private func feed(_ buffer: AVAudioPCMBuffer) {
        requestLock.lock()
        let current = request
        requestLock.unlock()
        current?.append(buffer)
    }

    private func setRequest(_ newValue: SFSpeechAudioBufferRecognitionRequest?) {
        requestLock.lock()
        request = newValue
        requestLock.unlock()
    }

    private func observeAudioEvents() {
        guard !observing else { return }
        observing = true
        let center = NotificationCenter.default
        center.addObserver(self, selector: #selector(audioInterrupted(_:)), name: AVAudioSession.interruptionNotification, object: nil)
        center.addObserver(self, selector: #selector(audioNeedsRestart), name: AVAudioSession.mediaServicesWereResetNotification, object: nil)
        center.addObserver(self, selector: #selector(audioNeedsRestart), name: .AVAudioEngineConfigurationChange, object: engine)
    }

    @objc private func audioInterrupted(_ note: Notification) {
        guard let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: raw) else { return }
        if type == .ended { audioNeedsRestart() }
    }

    /// Phone calls, Siri, or other apps can stop the microphone. Try to get it back.
    @objc private func audioNeedsRestart() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
            guard let self, self.mode != .off else { return }
            let resumeMode = self.mode
            self.endRecognition()
            self.engine.stop()
            do {
                try self.configureAudioSession()
                try self.startEngine()
                if resumeMode == .wake || resumeMode == .command { self.listenForWake() }
            } catch {
                self.mode = .paused
                self.onProblem?("I stopped listening after another app used the microphone. Open Helper to wake me up.")
            }
        }
    }

    // MARK: - Recognition

    private func beginRecognition() {
        endRecognition()
        guard let recognizer, recognizer.isAvailable else {
            scheduleRestart(after: 2)
            return
        }
        let newRequest = SFSpeechAudioBufferRecognitionRequest()
        newRequest.shouldReportPartialResults = true
        newRequest.requiresOnDeviceRecognition = recognizer.supportsOnDeviceRecognition
        newRequest.addsPunctuation = false
        newRequest.contextualStrings = [HelperSettings.shared.wakePhrase, "Helper", "Hey Helper"]

        session += 1
        let id = session
        sessionStarted = Date()
        setRequest(newRequest)
        task = recognizer.recognitionTask(with: newRequest) { [weak self] result, error in
            let text = result?.bestTranscription.formattedString
            let isFinal = result?.isFinal ?? false
            let failed = error != nil
            DispatchQueue.main.async {
                self?.received(text: text, isFinal: isFinal, failed: failed, session: id)
            }
        }
    }

    private func endRecognition() {
        restartWork?.cancel()
        restartWork = nil
        let old = request
        setRequest(nil)
        old?.endAudio()
        task?.cancel()
        task = nil
        session += 1
    }

    private func received(text: String?, isFinal: Bool, failed: Bool, session id: Int) {
        guard id == session else { return }
        let settings = HelperSettings.shared

        switch mode {
        case .wake:
            if let text, let rest = WakeWordMatcher.remainder(after: settings.wakePhrase, in: text, sensitivity: settings.wakeSensitivity) {
                mode = .command
                commandFromWake = true
                commandText = rest
                onWake?()
                onTranscript?(rest)
                armSilence(after: rest.isEmpty ? 6 : 1.5)
                armLimit()
                if isFinal || failed { handleCommandTaskEnded() }
                return
            }
            if isFinal || failed {
                scheduleRestart(after: Date().timeIntervalSince(sessionStarted) < 1 ? 1.5 : 0.2)
            } else if (text?.count ?? 0) > 160 || Date().timeIntervalSince(sessionStarted) > 50 {
                // Keep the running transcript short and fresh.
                beginRecognition()
            }

        case .command:
            if let text {
                let heard: String
                if commandFromWake {
                    heard = WakeWordMatcher.remainder(after: settings.wakePhrase, in: text, sensitivity: settings.wakeSensitivity) ?? commandText
                } else {
                    heard = text
                }
                if heard != commandText {
                    commandText = heard
                    onTranscript?(heard)
                    if !heard.isEmpty { armSilence(after: 1.4) }
                }
            }
            if isFinal || failed { handleCommandTaskEnded() }

        case .off, .paused:
            break
        }
    }

    private func handleCommandTaskEnded() {
        if commandText.isEmpty {
            // Nothing said yet: keep waiting with a fresh recognizer until the silence timer fires.
            commandFromWake = false
            scheduleRestart(after: 0.1)
        } else {
            finishCommand()
        }
    }

    private func finishCommand() {
        guard mode == .command else { return }
        cancelTimers()
        let text = commandText.trimmingCharacters(in: .whitespacesAndNewlines)
        mode = .paused
        endRecognition()
        onCommand?(text)
    }

    private func scheduleRestart(after delay: TimeInterval) {
        restartWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.mode == .wake || self.mode == .command else { return }
            self.beginRecognition()
        }
        restartWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    // MARK: - Timers

    private func armSilence(after seconds: TimeInterval) {
        silenceTimer?.invalidate()
        silenceTimer = Timer.scheduledTimer(withTimeInterval: seconds, repeats: false) { [weak self] _ in
            self?.finishCommand()
        }
    }

    private func armLimit() {
        limitTimer?.invalidate()
        limitTimer = Timer.scheduledTimer(withTimeInterval: 20, repeats: false) { [weak self] _ in
            self?.finishCommand()
        }
    }

    private func cancelTimers() {
        silenceTimer?.invalidate()
        silenceTimer = nil
        limitTimer?.invalidate()
        limitTimer = nil
    }
}
