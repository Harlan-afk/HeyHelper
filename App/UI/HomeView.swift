import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var model: AppModel
    @State private var showSettings = false
    @State private var typed = ""
    @FocusState private var typing: Bool

    var body: some View {
        VStack(spacing: 0) {
            header

            LivePip(mood: model.mood, size: 180)
                .frame(height: 210)
                .contentShape(Rectangle())
                .onTapGesture { model.companionTapped() }
                .accessibilityLabel("Pip. Tap to talk.")

            Text(model.statusLine)
                .font(.headline)
                .multilineTextAlignment(.center)
                .foregroundStyle(.white.opacity(0.85))
                .lineLimit(3)
                .frame(minHeight: 48)
                .padding(.horizontal, 24)

            ChatList(messages: model.messages)

            inputBar
        }
        .foregroundStyle(.white)
        .sheet(isPresented: $showSettings) {
            SettingsView()
                .environmentObject(model)
                .environmentObject(model.settings)
        }
    }

    private var header: some View {
        HStack {
            Text("Helper").font(.title2.bold())
            Spacer()
            Button {
                showSettings = true
            } label: {
                Image(systemName: "gearshape.fill").font(.title3)
            }
            .accessibilityLabel("Settings")
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
    }

    private var inputBar: some View {
        HStack(spacing: 10) {
            TextField("Type to Pip…", text: $typed)
                .focused($typing)
                .submitLabel(.send)
                .onSubmit(sendTyped)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Theme.card, in: Capsule())

            Button {
                if typed.trimmingCharacters(in: .whitespaces).isEmpty {
                    model.startManualListening()
                } else {
                    sendTyped()
                }
            } label: {
                Image(systemName: typed.isEmpty ? "mic.fill" : "arrow.up")
                    .font(.headline)
                    .foregroundStyle(.black)
                    .frame(width: 42, height: 42)
                    .background(Theme.accent, in: Circle())
            }
            .accessibilityLabel(typed.isEmpty ? "Talk" : "Send")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private func sendTyped() {
        let text = typed.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        typed = ""
        typing = false
        model.send(text)
    }
}

private struct ChatList: View {
    let messages: [ChatMessage]

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 10) {
                    if messages.isEmpty {
                        Text("Ask me anything, or tell me to open an app, set a timer, text someone, or turn on the flashlight.")
                            .font(.subheadline)
                            .multilineTextAlignment(.center)
                            .foregroundStyle(.white.opacity(0.5))
                            .padding(.top, 20)
                            .padding(.horizontal, 30)
                    }
                    ForEach(messages) { message in
                        Bubble(message: message).id(message.id)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }
            .onChange(of: messages.last?.text) { _, _ in
                if let last = messages.last {
                    withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(last.id, anchor: .bottom) }
                }
            }
        }
    }
}

private struct Bubble: View {
    let message: ChatMessage

    var body: some View {
        let fromUser = message.role == .user
        HStack {
            if fromUser { Spacer(minLength: 40) }
            Text(message.text.isEmpty ? "…" : message.text)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(fromUser ? Theme.userBubble : Theme.card, in: RoundedRectangle(cornerRadius: 18))
                .textSelection(.enabled)
            if !fromUser { Spacer(minLength: 40) }
        }
    }
}
