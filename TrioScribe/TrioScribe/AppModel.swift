import AppKit
import Foundation
import UniformTypeIdentifiers

@MainActor
final class AppModel: ObservableObject {
    @Published var mode: CaptureMode = .live
    @Published var language: TranscriptionLanguage = .chinese
    @Published var applications: [CaptureApplication] = []
    @Published var selectedProcessID: Int32 = 0
    @Published private(set) var state: SessionState = .idle
    @Published private(set) var elapsed: TimeInterval = 0
    @Published private(set) var audioLevel: Float = 0
    @Published private(set) var segments: [TranscriptSegment] = []
    @Published private(set) var partialTranscript = ""
    @Published private(set) var importedFileName: String?
    @Published private(set) var currentSessionDirectory: URL?
    @Published private(set) var recognitionStatus = "等待开始"
    @Published private(set) var sessionMessage = ""
    @Published var errorMessage: String?

    private let capture = SystemAudioCapture()
    private let transcriber = SpeechTranscriber()
    private let storage: SessionStorage
    private var sessionFiles: SessionFiles?
    private var timerTask: Task<Void, Never>?
    private var generation = UUID()
    private var recognitionOffset: TimeInterval = 0
    private var partialTimestamp: TimeInterval = 0
    private var recognitionFailure: Error?
    private var startingTask: Task<Void, Never>?
    private var preparationTask: Task<URL, Error>?

    var engineDescription: String { SpeechTranscriber.engineDescription }

    init(storage: SessionStorage = SessionStorage(), refreshApplications: Bool = true) {
        self.storage = storage
        do {
            _ = try storage.ensureRootDirectory()
        } catch {
            errorMessage = error.localizedDescription
        }
        if refreshApplications { Task { await self.refreshApplications() } }
    }

    var outputDirectoryPath: String {
        (try? storage.rootDirectory.path) ?? "~/Desktop/TrioScribe"
    }

    var elapsedLabel: String {
        TranscriptSegment.format(elapsed)
    }

    var statusLabel: String {
        switch state {
        case .idle: "准备就绪"
        case .starting: "正在启动"
        case .capturing: "正在收音"
        case .paused: "已暂停"
        case .importing: "正在处理文件"
        case .stopping: "正在完成文字稿"
        }
    }

    func refreshApplications() async {
        do {
            applications = try await capture.availableApplications()
            if selectedProcessID != 0,
               !applications.contains(where: { $0.processID == selectedProcessID }) {
                selectedProcessID = 0
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func startNewSession() async {
        guard state == .idle else { return }
        elapsed = 0
        segments = []
        partialTranscript = ""
        importedFileName = nil
        sessionFiles = nil
        currentSessionDirectory = nil
        sessionMessage = ""
        let task = Task { await beginCapture() }
        startingTask = task
        await task.value
        startingTask = nil
    }

    func importMedia() async {
        guard state == .idle else { return }

        let panel = NSOpenPanel()
        panel.title = "选择音频或视频文件"
        panel.prompt = "开始转写"
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.audio, .movie]

        guard panel.runModal() == .OK, let url = panel.url else { return }
        await transcribeMedia(at: url)
    }

    func transcribeMedia(at url: URL) async {
        guard state == .idle else { return }
        guard await SpeechTranscriber.requestAuthorization() else {
            errorMessage = "请在系统设置中允许 TrioScribe 使用语音识别。"
            return
        }

        importedFileName = url.lastPathComponent
        elapsed = 0
        segments = []
        partialTranscript = ""
        errorMessage = nil
        state = .importing
        generation = UUID()
        let token = generation
        recognitionOffset = 0
        recognitionFailure = nil
        sessionMessage = "正在准备转写，尚未生成文字。"
        sessionFiles = nil
        currentSessionDirectory = nil

        do {
            let files = try storage.createImportSession(fileName: url.lastPathComponent)
            sessionFiles = files
            currentSessionDirectory = files.directory
            try saveTranscript()
            let preparation = Task { try await MediaPreparation.readableAudio(at: url, in: files.directory) }
            preparationTask = preparation
            let audioURL = try await preparation.value
            guard generation == token else { return }
            preparationTask = nil
            try await transcriber.transcribeFile(at: audioURL, language: language, onUpdate: { [weak self] text, time, final in
                guard let self, self.generation == token else { return }
                self.receiveTranscript(text, timestamp: time, isFinal: final)
            }, onStatus: { [weak self] status in
                guard let self, self.generation == token else { return }
                self.recognitionStatus = status
            }, onError: { [weak self] error in
                guard let self, self.generation == token else { return }
                self.recognitionFailure = error
            })
            guard generation == token else { return }
            commitPartial()
            completeTranscript()
            await transcriber.cancel()
            state = .idle
        } catch {
            guard generation == token else { return }
            await transcriber.cancel()
            recognitionFailure = error
            commitPartial()
            completeTranscript()
            state = .idle
        }
    }

    func cancelImport() async {
        guard state == .importing || state == .starting else { return }
        state = .stopping
        generation = UUID()
        let pendingStart = startingTask
        pendingStart?.cancel()
        preparationTask?.cancel()
        await transcriber.cancel()
        await pendingStart?.value
        do { try await capture.stop() }
        catch { errorMessage = error.localizedDescription }
        capture.finishRecording()
        commitPartial()
        sessionMessage = "转写已取消，已有文字已保留。"
        recognitionStatus = "已取消"
        persistTranscript()
        state = .idle
    }

    func openSessionFolder() {
        guard let url = currentSessionDirectory ?? (try? storage.ensureRootDirectory()) else { return }
        NSWorkspace.shared.open(url)
    }

    func openTranscript() {
        guard let url = sessionFiles?.transcriptURL else { return }
        NSWorkspace.shared.open(url)
    }

    func exportTranscript() {
        guard !segments.isEmpty else { return }

        let panel = NSSavePanel()
        panel.title = "导出文字稿"
        panel.prompt = "导出"
        panel.nameFieldStringValue = "TrioScribe-Transcript.md"
        panel.allowedContentTypes = [UTType(filenameExtension: "md") ?? .plainText, .plainText]
        panel.directoryURL = currentSessionDirectory ?? (try? storage.ensureRootDirectory())

        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            try storage.writeTranscript(
                segments: segments,
                partialText: "",
                title: importedFileName ?? "TrioScribe Transcript",
                to: url
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func resumeSession() async {
        guard state == .paused else { return }
        let task = Task { await beginCapture() }
        startingTask = task
        await task.value
        startingTask = nil
    }

    func pauseSession() async {
        guard state == .capturing else { return }
        await finishCapture(pausing: true)
    }

    func endSession() async {
        guard state == .capturing || state == .paused else { return }
        await finishCapture(pausing: false)
    }

    private func finishCapture(pausing: Bool) async {
        let wasCapturing = state == .capturing
        state = .stopping
        timerTask?.cancel()
        timerTask = nil
        do {
            try await capture.stop()
            if wasCapturing { try await transcriber.finish() }
        } catch {
            recognitionFailure = recognitionFailure ?? error
            await transcriber.cancel()
        }
        commitPartial()
        completeTranscript()
        if !pausing || recognitionFailure != nil { capture.finishRecording() }
        audioLevel = 0
        state = pausing && recognitionFailure == nil ? .paused : .idle
    }

    private func beginCapture() async {
        guard state == .idle || state == .paused else { return }
        errorMessage = nil
        state = .starting
        generation = UUID()
        let token = generation
        recognitionOffset = elapsed
        recognitionFailure = nil
        sessionMessage = "正在识别，文字稿会自动保存。"

        guard await SpeechTranscriber.requestAuthorization() else {
            errorMessage = "请在系统设置中允许 TrioScribe 使用语音识别。"
            state = .idle
            return
        }

        do {
            guard generation == token else { return }
            if sessionFiles == nil {
                let files = try storage.createLiveSession()
                sessionFiles = files
                currentSessionDirectory = files.directory
                try saveTranscript()
            }

            guard let recordingURL = sessionFiles?.audioURL else {
                throw SessionStorage.StorageError.desktopUnavailable
            }

            let sink = try await transcriber.start(language: language, onUpdate: { [weak self] text, time, final in
                guard let self, self.generation == token else { return }
                self.receiveTranscript(text, timestamp: self.recognitionOffset + time, isFinal: final)
            }, onStatus: { [weak self] status in
                guard let self, self.generation == token else { return }
                self.recognitionStatus = status
            }, onError: { [weak self] error in
                guard let self, self.generation == token else { return }
                self.receiveRecognitionError(error)
            })
            guard generation == token else { return }
            if let recognitionFailure { throw recognitionFailure }

            try await capture.start(
                processID: selectedProcessID,
                recordingURL: recordingURL,
                onAudioBuffer: sink,
                onLevel: { [weak self] level in
                    Task { @MainActor in
                        guard let self, self.generation == token else { return }
                        self.audioLevel = level
                    }
                },
                onRecordingError: { [weak self] error in
                    Task { @MainActor in
                        guard let self, self.generation == token else { return }
                        self.receiveRecognitionError(error)
                    }
                }
            )

            guard generation == token else { try await capture.stop(); capture.finishRecording(); return }
            if let recognitionFailure { throw recognitionFailure }
            state = .capturing
            recognitionStatus = "正在本地识别"
            startTimer()
        } catch {
            guard generation == token else { return }
            await transcriber.cancel()
            do { try await capture.stop() } catch { /* Preserve the original failure below. */ }
            capture.finishRecording()
            recognitionFailure = recognitionFailure ?? error
            completeTranscript()
            state = .idle
        }
    }

    private func receiveTranscript(_ text: String, timestamp: TimeInterval, isFinal: Bool) {
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else {
            if isFinal { commitPartial(); persistTranscript() }
            return
        }

        if isFinal {
            segments.append(TranscriptSegment(timestamp: timestamp, text: cleaned))
            partialTranscript = ""
        } else {
            partialTranscript = cleaned
            partialTimestamp = timestamp
        }
        persistTranscript()
    }

    private func receiveRecognitionError(_ error: Error) {
        guard recognitionFailure == nil else { return }
        recognitionFailure = error
        recognitionStatus = "识别失败"
        if state == .capturing {
            Task { await endSession() }
        }
    }

    private func commitPartial() {
        let text = partialTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.isEmpty { segments.append(TranscriptSegment(timestamp: partialTimestamp, text: text)) }
        partialTranscript = ""
    }

    private func completeTranscript() {
        if let recognitionFailure {
            sessionMessage = TranscriptionError.describe(recognitionFailure)
            recognitionStatus = "识别失败"
            errorMessage = sessionMessage
        } else if segments.isEmpty {
            sessionMessage = "未识别到人声。请确认视频正在播放、音频来源正确，并选择对应的识别语言。"
            recognitionStatus = "未识别到文字"
        } else {
            sessionMessage = "已生成 \(segments.count) 段文字稿，保存于本次录音文件夹。"
            recognitionStatus = "转写完成"
        }
        persistTranscript()
    }

    private func persistTranscript() {
        do { try saveTranscript() }
        catch { errorMessage = "文字稿保存失败：\(error.localizedDescription)" }
    }

    private func saveTranscript() throws {
        guard let sessionFiles else { return }
        try storage.writeTranscript(
            segments: segments,
            partialText: partialTranscript,
            title: importedFileName ?? "TrioScribe Recording",
            statusMessage: sessionMessage.isEmpty ? nil : sessionMessage,
            to: sessionFiles.transcriptURL
        )
    }

    private func startTimer() {
        timerTask?.cancel()
        timerTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { return }
                self?.elapsed += 1
            }
        }
    }
}

