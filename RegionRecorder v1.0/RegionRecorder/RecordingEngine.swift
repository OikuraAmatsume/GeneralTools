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
    private var writerInput: AVAssetWriterInput?
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
            configuration.capturesAudio = false
            configuration.excludesCurrentProcessAudio = true
            configuration.preservesAspectRatio = true
            configuration.captureResolution = .best
            configuration.shouldBeOpaque = true

            try configureWriter(
                at: temporaryStore.movieURL,
                width: Int(pixelSize.width),
                height: Int(pixelSize.height),
                frameRate: settings.frameRate
            )

            let stream = SCStream(filter: filter, configuration: configuration, delegate: self)
            try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: sampleQueue)
            self.stream = stream
            try await stream.startCapture()
        } catch {
            abort()
            throw error
        }
    }

    func stopAndExport() async throws -> URL {
        guard let stream, let writer, let writerInput,
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
                writerInput.markAsFinished()
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
        guard outputType == .screen,
              sampleBuffer.isValid,
              isCompleteFrame(sampleBuffer),
              let writer,
              let writerInput,
              writer.status == .writing else {
            return
        }

        if !sessionStarted {
            writer.startSession(atSourceTime: sampleBuffer.presentationTimeStamp)
            sessionStarted = true
        }

        guard writerInput.isReadyForMoreMediaData else { return }
        if writerInput.append(sampleBuffer) {
            framesWritten += 1
        } else if sampleError == nil {
            sampleError = RecordingError.encoderFailed(writer.error?.localizedDescription ?? "无法写入视频帧")
        }
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

    private func configureWriter(at url: URL, width: Int, height: Int, frameRate: Int) throws {
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
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: outputSettings)
        input.expectsMediaDataInRealTime = true

        guard writer.canAdd(input) else {
            throw RecordingError.cannotConfigureEncoder
        }
        writer.add(input)
        guard writer.startWriting() else {
            throw RecordingError.encoderFailed(writer.error?.localizedDescription ?? "编码器未能启动")
        }

        self.writer = writer
        writerInput = input
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
        writerInput = nil
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
