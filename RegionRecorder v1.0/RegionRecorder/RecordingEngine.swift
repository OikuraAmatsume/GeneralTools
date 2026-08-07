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

    private var temporaryDirectory: URL?
    private var temporaryMovieURL: URL?
    private var destinationURL: URL?
    private var settings: RecordingSettings?

    @MainActor
    func start(
        descriptor: CaptureRegionDescriptor,
        settings: RecordingSettings,
        destinationURL: URL
    ) async throws {
        let fileManager = FileManager.default
        let temporaryDirectory = fileManager.temporaryDirectory
            .appendingPathComponent("RegionRecorder-\(UUID().uuidString)", isDirectory: true)

        do {
            try fileManager.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        } catch {
            throw RecordingError.cannotCreateTemporaryDirectory
        }

        let temporaryMovieURL = temporaryDirectory.appendingPathComponent("capture.mp4")
        self.temporaryDirectory = temporaryDirectory
        self.temporaryMovieURL = temporaryMovieURL
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
                at: temporaryMovieURL,
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
              let temporaryDirectory, let temporaryMovieURL,
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
                producedURL = temporaryMovieURL
            case .gif:
                let gifURL = temporaryDirectory.appendingPathComponent("capture.gif")
                try await GIFExporter.export(
                    movieURL: temporaryMovieURL,
                    outputURL: gifURL,
                    expectedFrameCount: captureState.1,
                    frameRate: settings.frameRate
                )
                try? FileManager.default.removeItem(at: temporaryMovieURL)
                producedURL = gifURL
            }

            try install(producedURL, at: destinationURL)
            cleanupTemporaryFiles()
            return destinationURL
        } catch {
            cleanupTemporaryFiles()
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
        cleanupTemporaryFiles()
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

    private func cleanupTemporaryFiles() {
        if let temporaryDirectory {
            try? FileManager.default.removeItem(at: temporaryDirectory)
        }
        temporaryDirectory = nil
        temporaryMovieURL = nil
    }
}
