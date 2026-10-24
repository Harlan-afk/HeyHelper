import Foundation
import llama

/// Helper's brain: an open-source language model (Llama 3.2 1B) running entirely on the iPhone
/// through llama.cpp. No internet, no AI service. It runs on the CPU so it keeps working while
/// the phone is locked (iOS does not allow GPU work from the background).
final class LlamaBrain: @unchecked Sendable {
    struct Message {
        var role: String
        var content: String
    }

    enum BrainError: LocalizedError {
        case loadFailed, contextFailed, notLoaded, promptTooLong, decodeFailed(Int32)

        var errorDescription: String? {
            switch self {
            case .loadFailed: return "The brain file could not be opened. Try downloading it again in Settings."
            case .contextFailed: return "There wasn't enough memory to start the brain. Close some apps and try again."
            case .notLoaded: return "The brain isn't loaded yet."
            case .promptTooLong: return "That was too long for me to think about at once."
            case .decodeFailed(let code): return "The brain hit an error (\(code))."
            }
        }
    }

    private let queue = DispatchQueue(label: "helper.brain", qos: .userInitiated)
    private var model: OpaquePointer?
    private var context: OpaquePointer?
    private var vocab: OpaquePointer?
    private var sampler: UnsafeMutablePointer<llama_sampler>?
    private var chatTemplate: String?
    /// Tokens currently held in the model's memory, so repeated prompt prefixes are not re-read.
    private var cachedTokens: [llama_token] = []

    private let contextSize: Int32 = 2048
    private let batchSize: Int32 = 512

    private let jobLock = NSLock()
    private var currentJob = 0

    private(set) var isLoaded = false

    deinit {
        if let sampler { llama_sampler_free(sampler) }
        if let context { llama_free(context) }
        if let model { llama_model_free(model) }
    }

    // MARK: - Loading

    func load(path: String) async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            queue.async {
                do {
                    try self.loadOnQueue(path: path)
                    cont.resume()
                } catch {
                    cont.resume(throwing: error)
                }
            }
        }
    }

    private func loadOnQueue(path: String) throws {
        if isLoaded { return }
        llama_backend_init()

        var modelParams = llama_model_default_params()
        modelParams.n_gpu_layers = 0
        // An empty device list keeps everything on the CPU.
        var noDevices: [ggml_backend_dev_t?] = [nil]
        let loaded: OpaquePointer? = noDevices.withUnsafeMutableBufferPointer { devices in
            modelParams.devices = devices.baseAddress
            return llama_model_load_from_file(path, modelParams)
        }
        guard let loaded else { throw BrainError.loadFailed }

        var contextParams = llama_context_default_params()
        contextParams.n_ctx = UInt32(contextSize)
        contextParams.n_batch = UInt32(batchSize)
        contextParams.n_ubatch = UInt32(batchSize)
        let threads = Int32(max(2, min(4, ProcessInfo.processInfo.activeProcessorCount - 2)))
        contextParams.n_threads = threads
        contextParams.n_threads_batch = threads
        contextParams.offload_kqv = false
        contextParams.op_offload = false
        guard let ctx = llama_init_from_model(loaded, contextParams) else {
            llama_model_free(loaded)
            throw BrainError.contextFailed
        }

        model = loaded
        context = ctx
        vocab = llama_model_get_vocab(loaded)
        if let tmpl = llama_model_chat_template(loaded, nil) {
            chatTemplate = String(cString: tmpl)
        }

        let chain = llama_sampler_chain_init(llama_sampler_chain_default_params())
        llama_sampler_chain_add(chain, llama_sampler_init_penalties(llama_vocab_n_tokens(vocab), 64, 1.1, 0.0, 0.0))
        llama_sampler_chain_add(chain, llama_sampler_init_top_p(0.9, 1))
        llama_sampler_chain_add(chain, llama_sampler_init_min_p(0.05, 1))
        llama_sampler_chain_add(chain, llama_sampler_init_temp(0.6))
        llama_sampler_chain_add(chain, llama_sampler_init_dist(UInt32.random(in: 0..<UInt32.max)))
        sampler = chain

        cachedTokens = []
        isLoaded = true
    }

    // MARK: - Thinking

    /// Streams the reply piece by piece. `pinned` leading messages are never trimmed when the
    /// conversation gets too long for the brain's memory.
    func generate(_ messages: [Message], pinned: Int, maxTokens: Int) -> AsyncThrowingStream<String, Error> {
        let job = startJob()
        return AsyncThrowingStream { continuation in
            queue.async {
                do {
                    try self.run(messages, pinned: pinned, maxTokens: maxTokens, job: job) { continuation.yield($0) }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { [weak self] _ in self?.cancel(job: job) }
        }
    }

    /// Reads the fixed start of the prompt ahead of time so the first answer comes faster.
    func warmUp(_ messages: [Message]) {
        let job = startJob()
        queue.async {
            guard self.isLoaded, self.isCurrent(job) else { return }
            let tokens = self.tokenize(self.format(messages))
            try? self.prefill(tokens, job: job)
        }
    }

    func cancel() {
        jobLock.lock()
        currentJob += 1
        jobLock.unlock()
    }

    private func startJob() -> Int {
        jobLock.lock()
        defer { jobLock.unlock() }
        currentJob += 1
        return currentJob
    }

    private func cancel(job: Int) {
        jobLock.lock()
        if currentJob == job { currentJob += 1 }
        jobLock.unlock()
    }

    private func isCurrent(_ job: Int) -> Bool {
        jobLock.lock()
        defer { jobLock.unlock() }
        return currentJob == job
    }

    private func run(_ messages: [Message], pinned: Int, maxTokens: Int, job: Int, emit: (String) -> Void) throws {
        guard isLoaded, let context, let sampler else { throw BrainError.notLoaded }

        var msgs = messages
        var tokens = tokenize(format(msgs))
        while tokens.count + maxTokens > Int(contextSize), msgs.count > pinned + 1 {
            msgs.remove(at: pinned)
            tokens = tokenize(format(msgs))
        }
        guard !tokens.isEmpty, tokens.count + maxTokens <= Int(contextSize) else { throw BrainError.promptTooLong }

        try prefill(tokens, job: job)
        llama_sampler_reset(sampler)

        var pendingBytes: [UInt8] = []
        for _ in 0..<maxTokens {
            guard isCurrent(job) else { throw CancellationError() }
            let token = llama_sampler_sample(sampler, context, -1)
            if llama_vocab_is_eog(vocab, token) { break }

            pendingBytes += piece(for: token)
            if let text = String(bytes: pendingBytes, encoding: .utf8) {
                emit(text)
                pendingBytes.removeAll()
            } else if pendingBytes.count > 8 {
                emit(String(decoding: pendingBytes, as: UTF8.self))
                pendingBytes.removeAll()
            }
            try decode([token], job: job)
        }
        if !pendingBytes.isEmpty { emit(String(decoding: pendingBytes, as: UTF8.self)) }
    }

    // MARK: - llama.cpp plumbing

    /// Feeds the prompt, reusing whatever matching beginning is already in memory.
    private func prefill(_ tokens: [llama_token], job: Int) throws {
        guard !tokens.isEmpty else { return }
        var keep = 0
        while keep < cachedTokens.count, keep < tokens.count, cachedTokens[keep] == tokens[keep] {
            keep += 1
        }
        // Always re-read at least the last token so fresh predictions are available.
        if keep == tokens.count { keep -= 1 }

        if keep < cachedTokens.count {
            let memory = llama_get_memory(context)
            if !llama_memory_seq_rm(memory, 0, Int32(keep), -1) {
                llama_memory_clear(memory, true)
                keep = 0
                cachedTokens.removeAll()
            } else {
                cachedTokens.removeSubrange(keep...)
            }
        }
        try decode(Array(tokens[keep...]), job: job)
    }

    private func decode(_ tokens: [llama_token], job: Int) throws {
        var start = 0
        while start < tokens.count {
            guard isCurrent(job) else { throw CancellationError() }
            let end = min(start + Int(batchSize), tokens.count)
            var chunk = Array(tokens[start..<end])
            let result = chunk.withUnsafeMutableBufferPointer { buffer in
                llama_decode(context, llama_batch_get_one(buffer.baseAddress, Int32(buffer.count)))
            }
            if result != 0 {
                // Memory is in an unknown state now; start clean next time.
                llama_memory_clear(llama_get_memory(context), true)
                cachedTokens.removeAll()
                throw BrainError.decodeFailed(result)
            }
            cachedTokens.append(contentsOf: chunk)
            start = end
        }
    }

    private func tokenize(_ text: String) -> [llama_token] {
        let byteCount = Int32(text.utf8.count)
        var capacity = byteCount + 8
        var tokens = [llama_token](repeating: 0, count: Int(capacity))
        var count = llama_tokenize(vocab, text, byteCount, &tokens, capacity, true, true)
        if count < 0 {
            capacity = -count
            tokens = [llama_token](repeating: 0, count: Int(capacity))
            count = llama_tokenize(vocab, text, byteCount, &tokens, capacity, true, true)
        }
        return count > 0 ? Array(tokens.prefix(Int(count))) : []
    }

    private func piece(for token: llama_token) -> [UInt8] {
        var capacity: Int32 = 32
        var buffer = [CChar](repeating: 0, count: Int(capacity))
        var count = llama_token_to_piece(vocab, token, &buffer, capacity, 0, false)
        if count < 0 {
            capacity = -count
            buffer = [CChar](repeating: 0, count: Int(capacity))
            count = llama_token_to_piece(vocab, token, &buffer, capacity, 0, false)
        }
        return count > 0 ? buffer.prefix(Int(count)).map { UInt8(bitPattern: $0) } : []
    }

    /// Turns the conversation into the exact text format the model was trained on.
    private func format(_ messages: [Message]) -> String {
        if let template = chatTemplate {
            let roles = messages.map { strdup($0.role) }
            let contents = messages.map { strdup($0.content) }
            defer {
                roles.forEach { free($0) }
                contents.forEach { free($0) }
            }
            let chat = zip(roles, contents).map { llama_chat_message(role: UnsafePointer($0), content: UnsafePointer($1)) }
            let messageCount = chat.count
            var capacity: Int32 = 16_384
            var buffer = [CChar](repeating: 0, count: Int(capacity))
            var length = llama_chat_apply_template(template, chat, messageCount, true, &buffer, capacity)
            if length > capacity {
                capacity = length + 1
                buffer = [CChar](repeating: 0, count: Int(capacity))
                length = llama_chat_apply_template(template, chat, messageCount, true, &buffer, capacity)
            }
            if length > 0 {
                return String(decoding: buffer.prefix(Int(length)).map { UInt8(bitPattern: $0) }, as: UTF8.self)
            }
        }
        // Fallback: Llama 3 format written out by hand.
        var text = ""
        for message in messages {
            text += "<|start_header_id|>\(message.role)<|end_header_id|>\n\n\(message.content)<|eot_id|>"
        }
        return text + "<|start_header_id|>assistant<|end_header_id|>\n\n"
    }
}
