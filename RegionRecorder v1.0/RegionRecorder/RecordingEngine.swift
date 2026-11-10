import AudioToolbox
import AVFoundation
import CoreMedia
import CoreVideo
import Foundation
import ScreenCaptureKit

enum RecordingError: LocalizedError {
    case displayUnavailable
    case applicationFilterUnavailable
    case cannotCreateTemporaryDirectory
    case cannotConfigureEncoder
    case encoderFailed(String)
    case noFramesCaptured
    case gifCreationFailed
    case gifEncodingFailed
    case temporaryCleanupFailed(String)

    var errorDescription: String? {
        switch self {
        case .displayUnavailable:
            "找不到选区所在的显示器。请重新创建录制区域。"
        case .applicationFilterUnavailable:
            "无法从屏幕捕获中过滤本应用的边框和菜单。"
        case .cannotCreateTemporaryDirectory:
            "无法创建本地临时目录。"
        case .cannotConfigureEncoder:
            "无法配置本地视频编码器。"
        case .encoderFailed(let details):
            "视频编码失败：\(details)"
        case .noFramesCaptured:
            "没有捕获到可导出的画面。"
        case .gifCreationFailed:
            "无法创建 GIF 文件。"
        case .gifEncodingFailed:
            "GIF 编码失败。"
        case .temporaryCleanupFailed(let details):
            "无法清理录制临时文件：\(details)"
        }
    }
}

struct RecordingTemporaryStore {
    static let rootDirectoryName = "com.local.RegionRecorder.recording-cache"

    let rootURL: URL
    let sessionURL: URL
    let movieURL: URL
    let gifURL: URL

    static func create(
        fileManager: FileManager = .default,
        temporaryRoot: URL? = nil
    ) throws -> RecordingTemporaryStore {
        let rootURL = (temporaryRoot ?? fileManager.temporaryDirectory)
            .appendingPathComponent(rootDirectoryName, isDirectory: true)
        try fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)

        let sessionURL = rootURL
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fileManager.createDirectory(at: sessionURL, withIntermediateDirectories: false)

        return RecordingTemporaryStore(
            rootURL: rootURL,
            sessionURL: sessionURL,
            movieURL: sessionURL.appendingPathComponent("capture.mp4"),
            gifURL: sessionURL.appendingPathComponent("capture.gif")
        )
    }

    static func removeStaleArtifacts(
        fileManager: FileManager = .default,
        temporaryRoot: URL? = nil
    ) throws {
        let rootURL = (temporaryRoot ?? fileManager.temporaryDirectory)
            .appendingPathComponent(rootDirectoryName, isDirectory: true)
        guard fileManager.fileExists(atPath: rootURL.path) else { return }
        try fileManager.removeItem(at: rootURL)
    }

    func removeAllArtifacts(fileManager: FileManager = .default) throws {
        if fileManager.fileExists(atPath: sessionURL.path) {
            try fileManager.removeItem(at: sessionURL)
        }

        guard fileManager.fileExists(atPath: rootURL.path) else { return }
        let remainingItems = try fileManager.contentsOfDirectory(
            at: rootURL,
            includingPropertiesForKeys: nil
        )
        if remainingItems.isEmpty {
            try fileManager.removeItem(at: rootURL)
        }
    }
}

final class RecordingEngine: NSObject, SCStreamOutput, SCStreamDelegate {
    var onUnexpectedStop: ((Error) -> Void)?

    private let sampleQueue = DispatchQueue(label: "com.local.RegionRecorder.capture", qos: .userInitiated)
    private var stream: SCStream?
    private var writer: AVAssetWriter?
    private var videoWriterInput: AVAssetWriterInput?
    private var audioWriterInput: AVAssetWriterInput?
    private var sessionStarted = false
    private var framesWritten = 0
    private var sampleError: Error?
    private var stopping = false

    private var temporaryStore: RecordingTemporaryStore?
    private var destinationURL: URL?
    private var settings: RecordingSettings?

    @MainActor
    func start(
        descriptor: CaptureRegionDescriptor,
        settings: RecordingSettings,
        destinationURL: URL
    ) async throws {
        do {
            try RecordingTemporaryStore.removeStaleArtifacts()
        } catch {
            throw RecordingError.temporaryCleanupFailed(error.localizedDescription)
        }

        let temporaryStore: RecordingTemporaryStore
        do {
            temporaryStore = try RecordingTemporaryStore.create()
        } catch {
            throw RecordingError.cannotCreateTemporaryDirectory
        }

        self.temporaryStore = temporaryStore
        self.destinationURL = destinationURL
        self.settings = settings

        do {
            let content = try await SCShareableContent.excludingDesktopWindows(
                false,
                onScreenWindowsOnly: true
            )
            guard let display = content.displays.first(where: { $0.displayID == descriptor.displayID }) else {
                throw RecordingError.displayUnavailable
            }
            guard let currentApplication = content.applications.first(where: {
                $0.processID == ProcessInfo.processInfo.processIdentifier
            }) else {
                throw RecordingError.applicationFilterUnavailable
            }

            // Excluding this application removes the passive border, edge panels, size label,
            // status item menu, save panel, and alerts from the recorded image.
            let filter = SCContentFilter(
                display: display,
                excludingApplications: [currentApplication],
                exceptingWindows: []
            )

            let sourceRect = CaptureGeometry.sourceRect(
                captureFrame: descriptor.captureFrame,
                in: descriptor.screenFrame
            )
            let pixelSize = CaptureGeometry.outputPixelSize(
                captureSize: descriptor.captureFrame.size,
                backingScaleFactor: descriptor.backingScaleFactor,
                outputScale: settings.outputScale
            )

            let configuration = SCStreamConfiguration()
            configuration.sourceRect = sourceRect
            configuration.width = Int(pixelSize.width)
            configuration.height = Int(pixelSize.height)
            configuration.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(settings.frameRate))
            configuration.queueDepth = 6
            configuration.pixelFormat = kCVPixelFormatType_32BGRA
            configuration.showsCursor = true
            configuration.capturesAudio = settings.shouldCaptureSystemAudio
            configuration.excludesCurrentProcessAudio = true
            if settings.shouldCaptureSystemAudio {
                configuration.sampleRate = Self.systemAudioSampleRate
                configuration.channelCount = Self.systemAudioChannelCount
            }
            configuration.preservesAspectRatio = true
            configuration.captureResolution = .best
            configuration.shouldBeOpaque = true

            try configureWriter(
                at: temporaryStore.movieURL,
                width: Int(pixelSize.width),
                height: Int(pixelSize.height),
                frameRate: settings.frameRate,
                capturesSystemAudio: settings.shouldCaptureSystemAudio
            )

            let stream = SCStream(filter: filter, configuration: configuration, delegate: self)
            try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: sampleQueue)
            if settings.shouldCaptureSystemAudio {
                try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: sampleQueue)
            }
            self.stream = stream
            try await stream.startCapture()
        } catch {
            abort()
            throw error
        }
    }

    func stopAndExport() async throws -> URL {
        guard let stream, let writer, let videoWriterInput,
              let temporaryStore,
              let destinationURL, let settings else {
            throw RecordingError.cannotConfigureEncoder
        }

        stopping = true
        do {
            try await stream.stopCapture()
            self.stream = nil

            let captureState: (Bool, Int, Error?) = sampleQueue.sync {
                let state = (sessionStarted, framesWritten, sampleError)
                videoWriterInput.markAsFinished()
                audioWriterInput?.markAsFinished()
                return state
            }

            if let sampleError = captureState.2 {
                throw sampleError
            }
            guard captureState.0, captureState.1 > 0 else {
                writer.cancelWriting()
                throw RecordingError.noFramesCaptured
            }

            await finishWriting(writer)
            guard writer.status == .completed else {
                throw RecordingError.encoderFailed(writer.error?.localizedDescription ?? "未知错误")
            }

            let producedURL: URL
            switch settings.format {
            case .mp4:
                producedURL = temporaryStore.movieURL
            case .gif:
                try await GIFExporter.export(
                    movieURL: temporaryStore.movieURL,
                    outputURL: temporaryStore.gifURL,
                    expectedFrameCount: captureState.1,
                    frameRate: settings.frameRate
                )
                try FileManager.default.removeItem(at: temporaryStore.movieURL)
                producedURL = temporaryStore.gifURL
            }

            try install(producedURL, at: destinationURL)
            try cleanupTemporaryFiles()
            return destinationURL
        } catch {
            try? cleanupTemporaryFiles()
            throw error
        }
    }

    func abort() {
        stopping = true
        if let stream {
            stream.stopCapture { _ in }
        }
        self.stream = nil
        writer?.cancelWriting()
        try? cleanupTemporaryFiles()
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        guard !stopping else { return }
        DispatchQueue.main.async { [weak self] in
            self?.onUnexpectedStop?(error)
        }
    }

    func stream(
        _ stream: SCStream,
        didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
        of outputType: SCStreamOutputType
    ) {
        guard sampleBuffer.isValid,
              let writer,
              writer.status == .writing else {
            return
        }

        switch outputType {
        case .screen:
            appendVideoSample(sampleBuffer, to: writer)
        case .audio:
            appendAudioSample(sampleBuffer, to: writer)
        default:
            break
        }
    }

    private func appendVideoSample(_ sampleBuffer: CMSampleBuffer, to writer: AVAssetWriter) {
        guard isCompleteFrame(sampleBuffer), let videoWriterInput else { return }

        startSessionIfNeeded(at: sampleBuffer.presentationTimeStamp, writer: writer)

        guard videoWriterInput.isReadyForMoreMediaData else { return }
        if videoWriterInput.append(sampleBuffer) {
            framesWritten += 1
        } else if sampleError == nil {
            sampleError = RecordingError.encoderFailed(writer.error?.localizedDescription ?? "无法写入视频帧")
        }
    }

    private func appendAudioSample(_ sampleBuffer: CMSampleBuffer, to writer: AVAssetWriter) {
        // Anchor the movie timeline to the first complete video frame. Audio arriving before
        // that frame is intentionally dropped so it can never precede the writer session.
        guard sessionStarted, let audioWriterInput else { return }

        guard audioWriterInput.isReadyForMoreMediaData else { return }
        if !audioWriterInput.append(sampleBuffer), sampleError == nil {
            sampleError = RecordingError.encoderFailed(writer.error?.localizedDescription ?? "无法写入系统声音")
        }
    }

    private func startSessionIfNeeded(at sourceTime: CMTime, writer: AVAssetWriter) {
        guard !sessionStarted else { return }
        writer.startSession(atSourceTime: sourceTime)
        sessionStarted = true
    }

    private func isCompleteFrame(_ sampleBuffer: CMSampleBuffer) -> Bool {
        guard let attachments = CMSampleBufferGetSampleAttachmentsArray(
            sampleBuffer,
            createIfNecessary: false
        ) as? [[SCStreamFrameInfo: Any]],
        let statusValue = attachments.first?[.status] as? Int,
        let status = SCFrameStatus(rawValue: statusValue) else {
            return false
        }
        return status == .complete
    }

    private func configureWriter(
        at url: URL,
        width: Int,
        height: Int,
        frameRate: Int,
        capturesSystemAudio: Bool
    ) throws {
        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        let bitsPerSecond = min(30_000_000, max(6_000_000, width * height * 6))
        let outputSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: bitsPerSecond,
                AVVideoExpectedSourceFrameRateKey: frameRate,
                AVVideoMaxKeyFrameIntervalKey: frameRate * 2,
                AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel
            ]
        ]
        let videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: outputSettings)
        videoInput.expectsMediaDataInRealTime = true

        guard writer.canAdd(videoInput) else {
            throw RecordingError.cannotConfigureEncoder
        }
        writer.add(videoInput)

        var audioInput: AVAssetWriterInput?
        if capturesSystemAudio {
            let input = AVAssetWriterInput(
                mediaType: .audio,
                outputSettings: Self.systemAudioOutputSettings()
            )
            input.expectsMediaDataInRealTime = true
            guard writer.canAdd(input) else {
                throw RecordingError.cannotConfigureEncoder
            }
            writer.add(input)
            audioInput = input
        }

        guard writer.startWriting() else {
            throw RecordingError.encoderFailed(writer.error?.localizedDescription ?? "编码器未能启动")
        }

        self.writer = writer
        videoWriterInput = videoInput
        audioWriterInput = audioInput
    }

    static let systemAudioSampleRate = 48_000
    static let systemAudioChannelCount = 2

    static func systemAudioOutputSettings() -> [String: Any] {
        [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: systemAudioSampleRate,
            AVNumberOfChannelsKey: systemAudioChannelCount,
            AVEncoderBitRateKey: 192_000
        ]
    }

    private func finishWriting(_ writer: AVAssetWriter) async {
        await withCheckedContinuation { continuation in
            writer.finishWriting {
                continuation.resume()
            }
        }
    }

    private func install(_ temporaryURL: URL, at destinationURL: URL) throws {
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: destinationURL.path) {
            _ = try fileManager.replaceItemAt(
                destinationURL,
                withItemAt: temporaryURL,
                backupItemName: nil,
                options: .usingNewMetadataOnly
            )
        } else {
            try fileManager.moveItem(at: temporaryURL, to: destinationURL)
        }
    }

    private func cleanupTemporaryFiles() throws {
        let store = temporaryStore

        stream = nil
        videoWriterInput = nil
        audioWriterInput = nil
        writer = nil
        temporaryStore = nil
        destinationURL = nil
        settings = nil
        sessionStarted = false
        framesWritten = 0
        sampleError = nil

        guard let store else { return }
        do {
            try store.removeAllArtifacts()
        } catch {
            // Releasing the encoder above normally removes all file handles. Retry once so a
            // transient filesystem race cannot leave a completed recording cache behind.
            do {
                try store.removeAllArtifacts()
            } catch {
                throw RecordingError.temporaryCleanupFailed(error.localizedDescription)
            }
        }
    }
}
