import SwiftUI

/// First launch: allow the microphone, download the brain, start.
struct SetupView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var store: ModelStore
    @State private var microphone = Permissions.microphone
    @State private var speech = Permissions.speech

    private var permissionsDone: Bool { microphone && speech }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                LivePip(mood: .idle, size: 150)
                    .frame(height: 170)
                    .padding(.top, 24)

                Text("Hi, I'm Pip!")
                    .font(.largeTitle.bold())
                Text("I'm your Helper. Two quick steps and I'll be ready to listen for “\(model.settings.wakePhrase)”.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white.opacity(0.75))

                StepCard(number: 1, title: "Let me hear you",
                         detail: "Microphone and speech recognition. What I hear stays on this iPhone.",
                         done: permissionsDone) {
                    Button("Allow") { Task { await askPermissions() } }
                        .buttonStyle(.borderedProminent)
                }

                StepCard(number: 2, title: "Download my brain",
                         detail: "A one-time \(store.sizeText) download, so use Wi-Fi. After this I work with no internet.",
                         done: store.isReady) {
                    if store.isVerifying {
                        Label("Checking the download…", systemImage: "checkmark.shield")
                    } else if store.isDownloading {
                        VStack(alignment: .leading, spacing: 6) {
                            ProgressView(value: store.progress)
                            Text("\(Int(store.progress * 100))%: keep Helper open until it finishes")
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.7))
                        }
                    } else {
                        Button("Download") { store.download() }
                            .buttonStyle(.borderedProminent)
                    }
                    if let problem = store.problem {
                        Text(problem).font(.caption).foregroundStyle(.orange)
                    }
                }

                if let problem = model.startupProblem {
                    Text(problem).font(.callout).foregroundStyle(.orange).multilineTextAlignment(.center)
                }

                Button {
                    Task { await model.start() }
                } label: {
                    Text("Start Helper").font(.headline).frame(maxWidth: .infinity).padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.accent)
                .foregroundStyle(.black)
                .disabled(!(permissionsDone && store.isReady))
                .padding(.top, 8)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 32)
        }
        .foregroundStyle(.white)
    }

    private func askPermissions() async {
        microphone = await Permissions.requestMicrophone()
        speech = await Permissions.requestSpeech()
        await Notifier.requestPermission()
    }
}

private struct StepCard<Content: View>: View {
    let number: Int
    let title: String
    let detail: String
    let done: Bool
    @ViewBuilder let content: () -> Content

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            ZStack {
                Circle().fill(done ? Theme.accent : Color.white.opacity(0.15))
                if done {
                    Image(systemName: "checkmark").font(.headline).foregroundStyle(.black)
                } else {
                    Text("\(number)").font(.headline)
                }
            }
            .frame(width: 34, height: 34)

            VStack(alignment: .leading, spacing: 8) {
                Text(title).font(.headline)
                Text(detail).font(.subheadline).foregroundStyle(.white.opacity(0.7))
                if !done { content() }
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 18))
    }
}
