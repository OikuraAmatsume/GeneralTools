import AppKit
import AVFoundation
import CoreMedia
import Foundation
import ScreenCaptureKit

final class SystemAudioCapture: NSObject, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
    enum CaptureError: LocalizedError {
        case noDisplay
        case sourceUnavailable

        var errorDescription: String? {
            switch self {
            case .noDisplay:
                "没有找到可用的显示器。"
            case .sourceUnavailable:
                "选择的音频来源已经退出，请重新选择。"
            }
        }
    }

    private let audioQueue = DispatchQueue(label: "com.oikuraamatsume.trioscribe.audio", qos: .userInitiated)
    private var stream: SCStream?
    private var audioFile: AVAudioFile?
    private var recordingURL: URL?
    private var onAudioBuffer: AudioSink?
    private var onLevel: ((Float) -> Void)?
    private var onRecordingError: ((Error) -> Void)?
    private var reportedError = false

    func availableApplications() async throws -> [CaptureApplication] {
        let content = try await SCShareableContent.excludingDesktopWindows(
            false,
            onScreenWindowsOnly: true
        )

        let ownProcessID = getpid()
        return content.applications
            .filter { application in
                application.processID != ownProcessID && !application.applicationName.isEmpty
            }
            .map { application in
                CaptureApplication(
                    processID: application.processID,
                    name: application.applicationName,
                    bundleIdentifier: application.bundleIdentifier
                )
            }
            .sorted { lhs, rhs in
                lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
    }

    func start(
        processID: Int32,
        recordingURL: URL,
        onAudioBuffer: @escaping AudioSink,
        onLevel: @escaping (Float) -> Void,
        onRecordingError: @escaping (Error) -> Void
    ) async throws {
        if stream != nil {
            try await stop()
        }

        let content = try await SCShareableContent.excludingDesktopWindows(
            false,
            onScreenWindowsOnly: true
        )

        guard let display = content.displays.first else {
            throw CaptureError.noDisplay
        }

        let filter: SCContentFilter
        if processID == 0 {
            let currentBundleIdentifier = Bundle.main.bundleIdentifier
            let excludedApplications = content.applications.filter {
                $0.processID == getpid() || $0.bundleIdentifier == currentBundleIdentifier
            }
            filter = SCContentFilter(
                display: display,
                excludingApplications: excludedApplications,
                exceptingWindows: []
            )
        } else {
            guard let application = content.applications.first(where: { $0.processID == processID }) else {
                throw CaptureError.sourceUnavailable
            }
            filter = SCContentFilter(
                display: display,
                including: [application],
                exceptingWindows: []
            )
        }

        let configuration = SCStreamConfiguration()
        configuration.capturesAudio = true
        configuration.excludesCurrentProcessAudio = true
        configuration.sampleRate = 16_000
        configuration.channelCount = 1
        configuration.width = 2
        configuration.height = 2
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: 1)

        audioQueue.sync {
            self.onAudioBuffer = onAudioBuffer
            self.onLevel = onLevel
            self.onRecordingError = onRecordingError
            self.reportedError = false
            if self.recordingURL == nil { self.recordingURL = recordingURL }
        }

        let stream = SCStream(filter: filter, configuration: configuration, delegate: self)
        try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: audioQueue)
        try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: audioQueue)
        self.stream = stream
        do {
            try await stream.startCapture()
        } catch {
            self.stream = nil
            throw error
        }
    }

    func stop() async throws {
        let activeStream = stream
        stream = nil
        defer {
            // Drain all audio callbacks before ending the recognition input.
            audioQueue.sync {
                onAudioBuffer = nil
                onLevel = nil
                onRecordingError = nil
            }
        }
        try await activeStream?.stopCapture()
    }

    func finishRecording() {
        audioQueue.sync {
            audioFile = nil
            recordingURL = nil
        }
    }

    func stream(
        _ stream: SCStream,
        didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
        of outputType: SCStreamOutputType
    ) {
        guard outputType == .audio, sampleBuffer.isValid else { return }

        do {
            let samples = try Self.ownedAudioBuffer(from: sampleBuffer)
            onLevel?(Self.level(from: samples))
            writeAudio(samples)
            onAudioBuffer?(samples)
        } catch {
            report(error)
        }
    }

    static func ownedAudioBuffer(from sampleBuffer: CMSampleBuffer) throws -> AVAudioPCMBuffer {
        try sampleBuffer.withAudioBufferList { audioBufferList, _ in
            guard var description = sampleBuffer.formatDescription?.audioStreamBasicDescription,
                  let format = AVAudioFormat(streamDescription: &description),
                  sampleBuffer.numSamples > 0,
                  let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(sampleBuffer.numSamples)) else {
                throw TranscriptionError.invalidAudio
            }
            buffer.frameLength = buffer.frameCapacity
            let destinations = UnsafeMutableAudioBufferListPointer(buffer.mutableAudioBufferList)
            guard destinations.count == audioBufferList.count else { throw TranscriptionError.invalidAudio }
            for index in 0..<destinations.count {
                guard let source = audioBufferList[index].mData, let destination = destinations[index].mData,
                      audioBufferList[index].mDataByteSize <= destinations[index].mDataByteSize else {
                    throw TranscriptionError.invalidAudio
                }
                memcpy(destination, source, Int(audioBufferList[index].mDataByteSize))
            }
            return buffer
        }
    }

    private func writeAudio(_ buffer: AVAudioPCMBuffer) {
        do {
            if audioFile == nil, let recordingURL {
                audioFile = try AVAudioFile(
                    forWriting: recordingURL,
                    settings: buffer.format.settings,
                    commonFormat: buffer.format.commonFormat,
                    interleaved: buffer.format.isInterleaved
                )
            }
            try audioFile?.write(from: buffer)
        } catch {
            report(error)
        }
    }

    private func report(_ error: Error) {
        guard !reportedError else { return }
        reportedError = true
        onRecordingError?(error)
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        audioQueue.async { [weak self] in self?.report(error) }
    }

    private static func level(from buffer: AVAudioPCMBuffer) -> Float {
        guard
            let channel = buffer.floatChannelData?.pointee,
            buffer.frameLength > 0
        else {
            return 0
        }

        let count = Int(buffer.frameLength)
        var sum: Float = 0
        for index in 0..<count {
            let sample = channel[index]
            sum += sample * sample
        }
        let rootMeanSquare = sqrt(sum / Float(count))
        return min(1, max(0, rootMeanSquare * 8))
    }
}

