import AVFoundation
import Speech
import UIKit

enum Permissions {
    static var microphone: Bool { AVAudioApplication.shared.recordPermission == .granted }
    static var speech: Bool { SFSpeechRecognizer.authorizationStatus() == .authorized }
    static var ready: Bool { microphone && speech }

    static func requestMicrophone() async -> Bool {
        await AVAudioApplication.requestRecordPermission()
    }

    static func requestSpeech() async -> Bool {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0 == .authorized) }
        }
    }
}

enum PhoneInfo {
    /// Facts the brain can't know by itself: the time and the battery.
    @MainActor
    static func summary() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, MMMM d, yyyy 'at' h:mm a"
        var parts = ["It is \(formatter.string(from: Date()))."]

        let device = UIDevice.current
        device.isBatteryMonitoringEnabled = true
        if device.batteryLevel >= 0 {
            let percent = Int((device.batteryLevel * 100).rounded())
            let charging = device.batteryState == .charging || device.batteryState == .full
            parts.append("The battery is at \(percent) percent\(charging ? " and charging" : "").")
        }
        return parts.joined(separator: " ")
    }
}
