import AVFoundation
import MediaPlayer
import UIKit

/// Carries out phone commands from the brain. Returns something to say out loud when it
/// couldn't do it, or when you need to finish it yourself (for example, while the phone is locked).
@MainActor
final class PhoneActions {
    private let contacts = ContactFinder()

    func perform(_ action: PhoneAction) async -> String? {
        switch action {
        case .open(let name):
            guard let app = AppDirectory.find(name, custom: HelperSettings.shared.customApps) else {
                return "I don't know how to open \(name) yet. You can teach me in my settings."
            }
            return await open(app.url, what: "open \(app.name)")

        case .call(let who):
            guard let number = await contacts.phoneNumber(for: who), let url = URL(string: "tel://\(number)") else {
                return "I couldn't find \(who) in your contacts."
            }
            return await open(url, what: "call \(who)")

        case .text(let who, let message):
            guard let number = await contacts.phoneNumber(for: who) else {
                return "I couldn't find \(who) in your contacts."
            }
            var link = "sms:\(number)"
            if !message.isEmpty, let body = message.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) {
                link += "&body=\(body)"
            }
            guard let url = URL(string: link) else { return "I couldn't start that message." }
            return await open(url, what: "text \(who)")

        case .timer(let seconds, let label):
            await Notifier.schedule(inSeconds: seconds, title: "⏰ \(label)", body: "Time's up!")
            return nil

        case .reminder(let hour, let minute, let what):
            await Notifier.schedule(hour: hour, minute: minute, title: "🔔 Reminder", body: what)
            return nil

        case .flashlight(let on):
            return setFlashlight(on)

        case .music(let command):
            return await controlMusic(command)

        case .maps(let place):
            guard let query = place.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
                  let url = URL(string: "maps://?q=\(query)") else { return nil }
            return await open(url, what: "open Maps")

        case .shortcut(let name):
            guard let encoded = name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
                  let url = URL(string: "shortcuts://run-shortcut?name=\(encoded)") else { return nil }
            return await open(url, what: "run \(name)")

        case .search(let words):
            guard let query = words.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
                  let url = URL(string: "x-web-search://?\(query)") else { return nil }
            return await open(url, what: "search for \(words)")
        }
    }

    /// iOS only lets apps open other apps while they're on screen. When locked or in the
    /// background, Helper leaves a notification you can tap instead.
    private func open(_ url: URL, what: String) async -> String? {
        if UIApplication.shared.applicationState == .active {
            let opened = await UIApplication.shared.open(url)
            return opened ? nil : "I couldn't \(what). The app might not be installed."
        }
        await Notifier.post(title: "Tap to \(what)", body: "Helper is ready to \(what).", url: url)
        return "Unlock your phone and tap my notification to \(what)."
    }

    private func setFlashlight(_ on: Bool) -> String? {
        guard let device = AVCaptureDevice.default(for: .video), device.hasTorch else {
            return "I can't find a flashlight on this phone."
        }
        do {
            try device.lockForConfiguration()
            if on {
                try device.setTorchModeOn(level: AVCaptureDevice.maxAvailableTorchLevel)
            } else {
                device.torchMode = .off
            }
            device.unlockForConfiguration()
            return nil
        } catch {
            return "The flashlight isn't available right now. Try again with Helper open."
        }
    }

    private func controlMusic(_ command: String) async -> String? {
        let status: MPMediaLibraryAuthorizationStatus = await withCheckedContinuation { continuation in
            MPMediaLibrary.requestAuthorization { continuation.resume(returning: $0) }
        }
        guard status == .authorized else { return "I need permission to use your music. You can allow it in iPhone Settings." }

        let player = MPMusicPlayerController.systemMusicPlayer
        if command.contains("pause") || command.contains("stop") {
            player.pause()
        } else if command.contains("next") || command.contains("skip") {
            player.skipToNextItem()
        } else if command.contains("previous") || command.contains("back") {
            player.skipToPreviousItem()
        } else {
            if player.nowPlayingItem == nil {
                player.setQueue(with: MPMediaQuery.songs())
                player.shuffleMode = .songs
            }
            player.play()
        }
        return nil
    }
}
