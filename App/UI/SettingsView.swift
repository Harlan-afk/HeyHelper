import AVFoundation
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var settings: HelperSettings
    @Environment(\.dismiss) private var dismiss
    @State private var newAppName = ""
    @State private var newAppTarget = ""

    private let voices = Speaker.englishVoices

    var body: some View {
        NavigationStack {
            Form {
                personalitySection
                smartsSection
                voiceSection
                listeningSection
                appsSection
                memorySection
                aboutSection
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .onChange(of: settings.personality) { _, _ in model.personalityChanged() }
        .onChange(of: settings.replyLength) { _, _ in model.personalityChanged() }
        .onChange(of: settings.internetEnabled) { _, _ in model.personalityChanged() }
        .onChange(of: settings.memories) { _, _ in model.personalityChanged() }
        .onChange(of: settings.listenEnabled) { _, _ in model.listeningSettingChanged() }
        .onChange(of: settings.lockScreenCompanion) { _, _ in model.lockScreenSettingChanged() }
    }

    private var personalitySection: some View {
        Section {
            Picker("Personality", selection: $settings.personality) {
                ForEach(Personality.allCases) { Text($0.title).tag($0) }
            }
            if settings.personality == .custom {
                TextField("Describe Pip's personality", text: $settings.customPersonality, axis: .vertical)
                    .lineLimit(2...5)
                    .onSubmit { model.personalityChanged() }
            }
            Picker("Answer length", selection: $settings.replyLength) {
                ForEach(ReplyLength.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
        } header: {
            Text("Personality")
        } footer: {
            Text("Custom example: “You talk like a pirate and call me captain.”")
        }
    }

    private var smartsSection: some View {
        Section {
            Toggle("Look things up online", isOn: $settings.internetEnabled)
            Picker("Play songs with", selection: $settings.musicApp) {
                ForEach(MusicApp.allCases) { Text($0.title).tag($0) }
            }
            if settings.memories.isEmpty {
                Text("Nothing remembered yet. Try “remember my favorite food is tacos”.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(settings.memories, id: \.self) { Text($0) }
                    .onDelete { settings.memories.remove(atOffsets: $0) }
            }
            LabeledContent("Facts learned online", value: "\(model.learnedCount)")
            Button("Forget learned facts", role: .destructive) { model.forgetLearned() }
                .disabled(model.learnedCount == 0)
        } header: {
            Text("Smarts & memory")
        } footer: {
            Text("Online lookups use free public sources (Wikipedia, DuckDuckGo, Open-Meteo weather, Apple's song search), not an AI service. Everything I learn is saved on this iPhone, so I can answer again offline. Swipe a memory left to delete it.")
        }
    }

    private var voiceSection: some View {
        Section {
            Picker("Voice", selection: $settings.voiceID) {
                Text("Automatic").tag("")
                ForEach(voices, id: \.identifier) { voice in
                    Text("\(voice.name) (\(qualityName(voice)))").tag(voice.identifier)
                }
            }
            VStack(alignment: .leading) {
                Text("Speed")
                Slider(value: $settings.speechRate, in: 0.6...1.5)
            }
            VStack(alignment: .leading) {
                Text("Pitch")
                Slider(value: $settings.speechPitch, in: 0.6...1.6)
            }
            Button("Test voice") { model.testVoice() }
        } header: {
            Text("Voice")
        } footer: {
            Text("For a nicer voice, download an “Enhanced” or “Premium” one in iPhone Settings > Accessibility > Spoken Content > Voices > English.")
        }
    }

    private var listeningSection: some View {
        Section {
            Toggle("Listen for wake phrase", isOn: $settings.listenEnabled)
            TextField("Wake phrase", text: $settings.wakePhrase)
                .textInputAutocapitalization(.words)
            Picker("How picky", selection: $settings.wakeSensitivity) {
                ForEach(WakeSensitivity.allCases) { Text($0.title).tag($0) }
            }
            Toggle("Listen for a follow-up after answering", isOn: $settings.followUp)
            Toggle("Show Pip on the lock screen", isOn: $settings.lockScreenCompanion)
        } header: {
            Text("Listening")
        } footer: {
            Text("“Relaxed” wakes up more easily but may trigger by accident. Leave Helper open in the background (don't swipe it away) so it can hear you on the lock screen. The orange dot means the mic is on.")
        }
    }

    private var appsSection: some View {
        Section {
            ForEach(settings.customApps) { app in
                VStack(alignment: .leading) {
                    Text(app.name)
                    Text(app.target).font(.caption).foregroundStyle(.secondary)
                }
            }
            .onDelete { settings.customApps.remove(atOffsets: $0) }

            TextField("App name (e.g. Camera)", text: $newAppName)
            TextField("Link or Shortcut name", text: $newAppTarget)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            Button("Add app") {
                settings.customApps.append(CustomApp(name: newAppName, target: newAppTarget))
                newAppName = ""
                newAppTarget = ""
            }
            .disabled(newAppName.trimmingCharacters(in: .whitespaces).isEmpty || newAppTarget.trimmingCharacters(in: .whitespaces).isEmpty)

            DisclosureGroup("Apps I already know (\(AppDirectory.builtIn.count))") {
                ForEach(AppDirectory.builtIn, id: \.name) { Text($0.name) }
            }
        } header: {
            Text("Teach me apps")
        } footer: {
            Text("iPhones only let apps open other apps by their link. For any app without one, make a Shortcut in the Shortcuts app that opens it (for example named “Open Camera”), then add it here with that Shortcut name.")
        }
    }

    private var memorySection: some View {
        Section {
            Button("Forget our conversation", role: .destructive) { model.forgetConversation() }
        } header: {
            Text("Memory")
        } footer: {
            Text("I remember the last few things we said so you can ask follow-ups.")
        }
    }

    private var aboutSection: some View {
        Section("About") {
            LabeledContent("Brain", value: "Llama 3.2 1B (on this phone)")
            LabeledContent("Internet", value: settings.internetEnabled ? "Lookups only" : "Not used")
            LabeledContent("Speech", value: "On-device")
        }
    }

    private func qualityName(_ voice: AVSpeechSynthesisVoice) -> String {
        switch voice.quality {
        case .premium: return "Premium"
        case .enhanced: return "Enhanced"
        default: return "Basic"
        }
    }
}
