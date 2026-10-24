import CryptoKit
import Foundation
import UIKit

/// Downloads the brain file once and keeps it on the phone. After that Helper never needs the internet.
final class ModelStore: NSObject, ObservableObject {
    static let fileName = "Llama-3.2-1B-Instruct-Q4_K_M.gguf"
    static let downloadURL = URL(string: "https://huggingface.co/bartowski/Llama-3.2-1B-Instruct-GGUF/resolve/main/Llama-3.2-1B-Instruct-Q4_K_M.gguf")!
    static let expectedSize: Int64 = 807_694_464
    static let expectedSHA256 = "6f85a640a97cf2bf5b8e764087b1e83da0fdb51d7c9fab7d0fece9385611df83"

    @Published private(set) var progress: Double = 0
    @Published private(set) var isDownloading = false
    @Published private(set) var isVerifying = false
    @Published private(set) var isReady = false
    @Published var problem: String?

    let modelURL: URL
    private var session: URLSession!

    override init() {
        let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Brain", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        modelURL = folder.appendingPathComponent(Self.fileName)
        super.init()
        session = URLSession(configuration: .default, delegate: self, delegateQueue: nil)
        isReady = Self.hasExpectedSize(modelURL)
    }

    var sizeText: String {
        ByteCountFormatter.string(fromByteCount: Self.expectedSize, countStyle: .file)
    }

    func download() {
        guard !isDownloading, !isReady else { return }
        problem = nil
        progress = 0
        isDownloading = true
        UIApplication.shared.isIdleTimerDisabled = true
        session.downloadTask(with: Self.downloadURL).resume()
    }

    func deleteBrain() {
        try? FileManager.default.removeItem(at: modelURL)
        isReady = false
        progress = 0
    }

    private static func hasExpectedSize(_ url: URL) -> Bool {
        let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.int64Value
        return size == expectedSize
    }

    private static func sha256(of url: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        var hasher = SHA256()
        while true {
            let chunk = autoreleasepool { try? handle.read(upToCount: 8 * 1024 * 1024) }
            guard let chunk, !chunk.isEmpty else { break }
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private func finish(problem: String?) {
        DispatchQueue.main.async {
            UIApplication.shared.isIdleTimerDisabled = false
            self.isDownloading = false
            self.isVerifying = false
            self.problem = problem
            self.isReady = problem == nil
        }
    }
}

extension ModelStore: URLSessionDownloadDelegate {
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64,
                    totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        let total = totalBytesExpectedToWrite > 0 ? totalBytesExpectedToWrite : Self.expectedSize
        let value = min(1, Double(totalBytesWritten) / Double(total))
        DispatchQueue.main.async { self.progress = value }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        if let http = downloadTask.response as? HTTPURLResponse, http.statusCode != 200 {
            finish(problem: "The download server said no (error \(http.statusCode)). Try again later.")
            return
        }
        let fm = FileManager.default
        let staging = modelURL.appendingPathExtension("part")
        try? fm.removeItem(at: staging)
        do {
            try fm.moveItem(at: location, to: staging)
        } catch {
            finish(problem: "Couldn't save the brain. Is your iPhone storage full?")
            return
        }

        DispatchQueue.main.async { self.isVerifying = true }
        guard Self.hasExpectedSize(staging), Self.sha256(of: staging) == Self.expectedSHA256 else {
            try? fm.removeItem(at: staging)
            finish(problem: "The download got damaged. Please try again.")
            return
        }
        do {
            try? fm.removeItem(at: modelURL)
            try fm.moveItem(at: staging, to: modelURL)
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            var url = modelURL
            try? url.setResourceValues(values)
            finish(problem: nil)
        } catch {
            finish(problem: "Couldn't save the brain. Is your iPhone storage full?")
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let error else { return }
        finish(problem: "Download stopped: \(error.localizedDescription) Keep Helper open on Wi-Fi and try again.")
    }
}
