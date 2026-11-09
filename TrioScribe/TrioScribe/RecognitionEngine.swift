import AVFoundation
import Foundation
import Speech

typealias AudioSink = @Sendable (AVAudioPCMBuffer) -> Void
typealias TranscriptUpdate = @MainActor (String, TimeInterval, Bool) -> Void
typealias RecognitionStatus = @MainActor (String) -> Void
typealias RecognitionFailure = @MainActor (Error) -> Void

enum TranscriptionError: LocalizedError {
    case unavailable, unsupportedLanguage, invalidAudio, timedOut, endedEarly
    case system(Error)

    var errorDescription: String? {
        switch self {
        case .unavailable:
            return "当前设备的语音识别不可用。请检查系统设置中的语音识别授权。"
        case .unsupportedLanguage:
            return "当前设备不支持所选语言的本地识别。"
        case .invalidAudio:
            return "无法读取有效音频。请确认文件含有音轨，或选择正在播放声音的应用。"
        case .timedOut:
            return "等待识别结果超时。音频和已有文字已保留，可稍后导入 Audio.wav 重试。"
        case .endedEarly:
            return "系统的旧版识别服务已结束本次会话。已有文字和音频已保留，请重新开始收音。"
        case .system(let error):
            let nsError = error as NSError
            if nsError.domain == "kLSRErrorDomain", nsError.code == 201 {
                return "系统听写已关闭。请打开“系统设置 → 键盘 → 听写”，再重新转写。macOS 26 上的新版本地引擎不依赖此开关。"
            }
            if nsError.domain == "kLSRErrorDomain", nsError.code == 102 {
                return "该语言的本地识别模型尚未安装。请在系统的听写设置中添加对应语言。"
            }
            if nsError.domain == "kAFAssistantErrorDomain", nsError.code == 1110 {
                return "未识别到人声。请检查音频来源、播放音量和识别语言。"
            }
            return "语音识别失败：\(nsError.localizedDescription)（\(nsError.domain) / \(nsError.code)）。音频和已有文字已保留。"
        }
    }

    static func describe(_ error: Error) -> String {
        (error as? TranscriptionError)?.localizedDescription ?? TranscriptionError.system(error).localizedDescription
    }
}

@MainActor
private protocol RecognitionSession: AnyObject {
    func startLive() async throws -> AudioSink
    func transcribeFile(at url: URL) async throws
    func finish() async throws
    func cancel() async
}

/// Lifecycle and result callbacks run on the main actor; audio sinks are synchronized.
@MainActor
final class SpeechTranscriber {
    private var session: (any RecognitionSession)?

    static var engineDescription: String {
        if #available(macOS 26.0, *), Speech.SpeechTranscriber.isAvailable {
            return "Apple SpeechAnalyzer · 本地识别"
        }
        return "Apple Speech · 需要系统听写"
    }

    static func requestAuthorization() async -> Bool {
        if #available(macOS 26.0, *), Speech.SpeechTranscriber.isAvailable { return true }
        return await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
    }

    func start(language: TranscriptionLanguage, onUpdate: @escaping TranscriptUpdate, onStatus: @escaping RecognitionStatus, onError: @escaping RecognitionFailure) async throws -> AudioSink {
        await cancel()
        let session = makeSession(language, onUpdate, onStatus, onError)
        self.session = session
        return try await session.startLive()
    }

    func transcribeFile(at url: URL, language: TranscriptionLanguage, onUpdate: @escaping TranscriptUpdate, onStatus: @escaping RecognitionStatus, onError: @escaping RecognitionFailure) async throws {
        await cancel()
        let session = makeSession(language, onUpdate, onStatus, onError)
        self.session = session
        try await session.transcribeFile(at: url)
    }

    func finish() async throws { try await session?.finish() }

    func cancel() async {
        let previous = session
        session = nil
        await previous?.cancel()
    }

    private func makeSession(_ language: TranscriptionLanguage, _ onUpdate: @escaping TranscriptUpdate, _ onStatus: @escaping RecognitionStatus, _ onError: @escaping RecognitionFailure) -> any RecognitionSession {
        if #available(macOS 26.0, *), Speech.SpeechTranscriber.isAvailable {
            return AnalyzerSession(language: language, onUpdate: onUpdate, onStatus: onStatus, onError: onError)
        }
        return LegacySpeechSession(language: language, onUpdate: onUpdate, onStatus: onStatus, onError: onError)
    }
}

@available(macOS 26.0, *)
@MainActor
private final class AnalyzerSession: RecognitionSession {
    let language: TranscriptionLanguage
    let onUpdate: TranscriptUpdate
    let onStatus: RecognitionStatus
    let onError: RecognitionFailure
    private var analyzer: SpeechAnalyzer?
    private var resultsTask: Task<Void, Error>?
    private var input: AnalyzerAudioInput?
    private var installation: AssetInstallationRequest?
    private var cancelled = false

    init(language: TranscriptionLanguage, onUpdate: @escaping TranscriptUpdate, onStatus: @escaping RecognitionStatus, onError: @escaping RecognitionFailure) {
        self.language = language
        self.onUpdate = onUpdate
        self.onStatus = onStatus
        self.onError = onError
    }

    private func prepare() async throws -> Speech.SpeechTranscriber {
        onStatus("正在检查\(language.displayName)本地模型…")
        guard let locale = await Speech.SpeechTranscriber.supportedLocale(equivalentTo: Locale(identifier: language.localeIdentifier)) else {
            throw TranscriptionError.unsupportedLanguage
        }
        let module = Speech.SpeechTranscriber(locale: locale, preset: .timeIndexedProgressiveTranscription)
        try await AssetInventory.reserve(locale: locale)
        if await AssetInventory.status(forModules: [module]) != .installed,
           let installation = try await AssetInventory.assetInstallationRequest(supporting: [module]) {
            self.installation = installation
            onStatus("正在下载\(language.displayName)本地模型，首次使用需要联网…")
            try await installation.downloadAndInstall()
            self.installation = nil
        }
        try Task.checkCancellation()
        guard !cancelled else { throw CancellationError() }
        analyzer = SpeechAnalyzer(modules: [module])
        resultsTask = Task { [weak self] in
            do {
                for try await result in module.results {
                    guard let self, !self.cancelled else { return }
                    let text = String(result.text.characters).trimmingCharacters(in: .whitespacesAndNewlines)
                    self.onUpdate(text, max(0, result.range.start.seconds), result.isFinal)
                }
            } catch {
                if let self, !self.cancelled { self.onError(error) }
                throw error
            }
        }
        onStatus("本地模型已就绪")
        return module
    }

    func startLive() async throws -> AudioSink {
        let module = try await prepare()
        guard let analyzer, let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [module]) else {
            throw TranscriptionError.invalidAudio
        }
        let input = AnalyzerAudioInput(format: format)
        self.input = input
        try await analyzer.prepareToAnalyze(in: format)
        try await analyzer.start(inputSequence: input.stream)
        return { [weak self] buffer in
            do { try input.append(buffer) }
            catch {
                Task { @MainActor in
                    guard let self, !self.cancelled else { return }
                    self.onError(error)
                }
            }
        }
    }

    func transcribeFile(at url: URL) async throws {
        _ = try await prepare()
        guard let analyzer else { throw TranscriptionError.unavailable }
        let file = try AVAudioFile(forReading: url)
        guard file.length > 0 else { throw TranscriptionError.invalidAudio }
        onStatus("正在本地转写…")
        try await analyzer.start(inputAudioFile: file, finishAfterFile: true)
        try await resultsTask?.value
    }

    func finish() async throws {
        guard !cancelled, let analyzer else { return }
        input?.finish()
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask { try await analyzer.finalizeAndFinishThroughEndOfInput() }
            group.addTask {
                try await Task.sleep(for: .seconds(25))
                await analyzer.cancelAndFinishNow()
                throw TranscriptionError.timedOut
            }
            defer { group.cancelAll() }
            try await group.next()
        }
        try await resultsTask?.value
        self.analyzer = nil
    }

    func cancel() async {
        cancelled = true
        installation?.progress.cancel()
        input?.finish()
        resultsTask?.cancel()
        await analyzer?.cancelAndFinishNow()
        analyzer = nil
    }
}

@available(macOS 26.0, *)
private final class AnalyzerAudioInput: @unchecked Sendable {
    let stream: AsyncStream<AnalyzerInput>
    private let continuation: AsyncStream<AnalyzerInput>.Continuation
    private let format: AVAudioFormat
    private let lock = NSLock()
    private var converter: AVAudioConverter?
    private var ended = false

    init(format: AVAudioFormat) {
        self.format = format
        (stream, continuation) = AsyncStream.makeStream(of: AnalyzerInput.self, bufferingPolicy: .bufferingOldest(512))
    }

    func append(_ buffer: AVAudioPCMBuffer) throws {
        lock.lock()
        defer { lock.unlock() }
        guard !ended, buffer.frameLength > 0 else { return }
        let output: AVAudioPCMBuffer
        if buffer.format == format {
            output = buffer // The capture path supplies owned PCM storage.
        } else {
            if converter?.inputFormat != buffer.format { converter = AVAudioConverter(from: buffer.format, to: format) }
            guard let converter,
                  let converted = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(ceil(Double(buffer.frameLength) * format.sampleRate / buffer.format.sampleRate)) + 32) else {
                throw TranscriptionError.invalidAudio
            }
            var supplied = false
            var error: NSError?
            let status = converter.convert(to: converted, error: &error) { _, inputStatus in
                if supplied { inputStatus.pointee = .noDataNow; return nil }
                supplied = true
                inputStatus.pointee = .haveData
                return buffer
            }
            if let error { throw error }
            guard status != .error else { throw TranscriptionError.invalidAudio }
            output = converted
        }
        guard output.frameLength > 0 else { return }
        if case .dropped = continuation.yield(AnalyzerInput(buffer: output)) { throw TranscriptionError.timedOut }
    }

    func finish() {
        lock.lock()
        defer { lock.unlock() }
        guard !ended else { return }
        ended = true
        continuation.finish()
    }
}

/// Compatibility path for macOS 14/15 and hardware without SpeechAnalyzer.
@MainActor
private final class LegacySpeechSession: RecognitionSession {
    let language: TranscriptionLanguage
    let onUpdate: TranscriptUpdate
    let onStatus: RecognitionStatus
    let onError: RecognitionFailure
    private var recognizer: SFSpeechRecognizer?
    private var task: SFSpeechRecognitionTask?
    private var input: LegacyAudioInput?
    private var completion: Result<Void, Error>?
    private var cancelled = false
    private var finishing = false
    private var fileMode = false

    init(language: TranscriptionLanguage, onUpdate: @escaping TranscriptUpdate, onStatus: @escaping RecognitionStatus, onError: @escaping RecognitionFailure) {
        self.language = language
        self.onUpdate = onUpdate
        self.onStatus = onStatus
        self.onError = onError
    }

    private func recognize(_ request: SFSpeechRecognitionRequest) throws {
        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: language.localeIdentifier)), recognizer.isAvailable else { throw TranscriptionError.unavailable }
        guard recognizer.supportsOnDeviceRecognition else { throw TranscriptionError.unsupportedLanguage }
        self.recognizer = recognizer
        request.requiresOnDeviceRecognition = true
        request.shouldReportPartialResults = true
        request.taskHint = .dictation
        onStatus("正在使用系统本地听写…")
        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            Task { @MainActor in
                guard let self, !self.cancelled, self.completion == nil else { return }
                if let result {
                    self.onUpdate(result.bestTranscription.formattedString, 0, result.isFinal)
                    if result.isFinal {
                        self.completion = .success(())
                        if !self.finishing && !self.fileMode { self.onError(TranscriptionError.endedEarly) }
                        return
                    }
                }
                if let error { self.completion = .failure(error); self.onError(error) }
            }
        }
    }

    func startLive() async throws -> AudioSink {
        let request = SFSpeechAudioBufferRecognitionRequest()
        let input = LegacyAudioInput(request: request)
        self.input = input
        try recognize(request)
        return { buffer in input.append(buffer) }
    }

    func transcribeFile(at url: URL) async throws {
        fileMode = true
        try recognize(SFSpeechURLRecognitionRequest(url: url))
        try await waitForResult(timeout: 180)
    }

    func finish() async throws {
        finishing = true
        input?.finish()
        try await waitForResult(timeout: 20)
    }

    private func waitForResult(timeout: TimeInterval) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while completion == nil, !cancelled {
            try Task.checkCancellation()
            guard Date() < deadline else { throw TranscriptionError.timedOut }
            try await Task.sleep(for: .milliseconds(100))
        }
        guard !cancelled else { throw CancellationError() }
        try completion?.get()
    }

    func cancel() async {
        cancelled = true
        input?.finish()
        task?.cancel()
        task = nil
        recognizer = nil
    }
}

private final class LegacyAudioInput: @unchecked Sendable {
    private let lock = NSLock()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    init(request: SFSpeechAudioBufferRecognitionRequest) { self.request = request }
    func append(_ buffer: AVAudioPCMBuffer) {
        lock.lock()
        defer { lock.unlock() }
        request?.append(buffer)
    }
    func finish() {
        lock.lock()
        defer { lock.unlock() }
        request?.endAudio()
        request = nil
    }
}

enum MediaPreparation {
    /// AVAudioFile handles WAV/M4A/etc. Video containers are decoded into the session folder.
    static func readableAudio(at url: URL, in directory: URL) async throws -> URL {
        if let file = try? AVAudioFile(forReading: url), file.length > 0 { return url }
        let asset = AVURLAsset(url: url)
        guard let track = try await asset.loadTracks(withMediaType: .audio).first else {
            throw TranscriptionError.invalidAudio
        }
        let task = Task.detached(priority: .userInitiated) {
            let reader = try AVAssetReader(asset: asset)
            let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
                AVFormatIDKey: kAudioFormatLinearPCM,
                AVSampleRateKey: 16_000,
                AVNumberOfChannelsKey: 1,
                AVLinearPCMBitDepthKey: 32,
                AVLinearPCMIsFloatKey: true,
                AVLinearPCMIsBigEndianKey: false,
                AVLinearPCMIsNonInterleaved: false
            ])
            guard reader.canAdd(output) else { throw TranscriptionError.invalidAudio }
            reader.add(output)
            guard reader.startReading() else { throw reader.error ?? TranscriptionError.invalidAudio }
            defer { reader.cancelReading() }
            let destination = directory.appendingPathComponent("PreparedAudio.caf")
            var audioFile: AVAudioFile?
            var frames: AVAudioFramePosition = 0
            while let sample = output.copyNextSampleBuffer() {
                try Task.checkCancellation()
                let buffer = try SystemAudioCapture.ownedAudioBuffer(from: sample)
                if audioFile == nil {
                    audioFile = try AVAudioFile(forWriting: destination, settings: buffer.format.settings,
                                                commonFormat: buffer.format.commonFormat, interleaved: buffer.format.isInterleaved)
                }
                try audioFile?.write(from: buffer)
                frames += AVAudioFramePosition(buffer.frameLength)
            }
            if reader.status == .failed { throw reader.error ?? TranscriptionError.invalidAudio }
            guard frames > 0 else { throw TranscriptionError.invalidAudio }
            audioFile = nil
            return destination
        }
        return try await withTaskCancellationHandler { try await task.value } onCancel: { task.cancel() }
    }
}
