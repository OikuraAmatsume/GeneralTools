import AVFoundation
import ImageIO
import XCTest
@testable import RegionRecorder

final class MediaExportTests: XCTestCase {
    func testRecordingTemporaryStoreRemovesEveryIntermediateArtifact() throws {
        let temporaryRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("RegionRecorderStoreTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporaryRoot) }

        let store = try RecordingTemporaryStore.create(temporaryRoot: temporaryRoot)
        XCTAssertTrue(FileManager.default.createFile(atPath: store.movieURL.path, contents: Data("movie".utf8)))
        XCTAssertTrue(FileManager.default.createFile(atPath: store.gifURL.path, contents: Data("gif".utf8)))
        let nestedCache = store.sessionURL.appendingPathComponent("encoder-cache", isDirectory: true)
        try FileManager.default.createDirectory(at: nestedCache, withIntermediateDirectories: false)
        XCTAssertTrue(FileManager.default.createFile(
            atPath: nestedCache.appendingPathComponent("frame.cache").path,
            contents: Data("frame".utf8)
        ))

        try store.removeAllArtifacts()

        XCTAssertFalse(FileManager.default.fileExists(atPath: store.sessionURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.rootURL.path))
    }

    func testRecordingTemporaryStorePurgesArtifactsFromInterruptedSession() throws {
        let temporaryRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("RegionRecorderStaleStoreTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporaryRoot) }

        let store = try RecordingTemporaryStore.create(temporaryRoot: temporaryRoot)
        XCTAssertTrue(FileManager.default.createFile(atPath: store.movieURL.path, contents: Data("partial".utf8)))

        try RecordingTemporaryStore.removeStaleArtifacts(temporaryRoot: temporaryRoot)

        XCTAssertFalse(FileManager.default.fileExists(atPath: store.rootURL.path))
    }

    func testSilentMP4TranscodesToLoopingGIF() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("RegionRecorderMediaTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let movieURL = directory.appendingPathComponent("synthetic.mp4")
        let gifURL = directory.appendingPathComponent("synthetic.gif")
        let frameCount = 3
        let frameRate = 10
        try await createSyntheticSilentMovie(
            at: movieURL,
            frameCount: frameCount,
            frameRate: frameRate
        )

        let asset = AVURLAsset(url: movieURL)
        let videoTracks = try await asset.loadTracks(withMediaType: .video)
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        XCTAssertEqual(videoTracks.count, 1)
        XCTAssertEqual(audioTracks.count, 0)

        try await GIFExporter.export(
            movieURL: movieURL,
            outputURL: gifURL,
            expectedFrameCount: frameCount,
            frameRate: frameRate
        )

        guard let source = CGImageSourceCreateWithURL(gifURL as CFURL, nil) else {
            return XCTFail("GIF should be readable by ImageIO")
        }
        XCTAssertEqual(CGImageSourceGetCount(source), frameCount)

        let properties = CGImageSourceCopyProperties(source, nil) as? [CFString: Any]
        let gifProperties = properties?[kCGImagePropertyGIFDictionary] as? [CFString: Any]
        XCTAssertEqual(gifProperties?[kCGImagePropertyGIFLoopCount] as? Int, 0)
    }

    private func createSyntheticSilentMovie(
        at url: URL,
        frameCount: Int,
        frameRate: Int
    ) async throws {
        let dimensions = CGSize(width: 64, height: 64)
        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        let input = AVAssetWriterInput(
            mediaType: .video,
            outputSettings: [
                AVVideoCodecKey: AVVideoCodecType.h264,
                AVVideoWidthKey: Int(dimensions.width),
                AVVideoHeightKey: Int(dimensions.height)
            ]
        )
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: Int(dimensions.width),
                kCVPixelBufferHeightKey as String: Int(dimensions.height)
            ]
        )

        XCTAssertTrue(writer.canAdd(input))
        writer.add(input)
        XCTAssertTrue(writer.startWriting())
        writer.startSession(atSourceTime: .zero)

        for index in 0..<frameCount {
            while !input.isReadyForMoreMediaData {
                try await Task.sleep(nanoseconds: 1_000_000)
            }
            guard let pixelBuffer = makePixelBuffer(
                width: Int(dimensions.width),
                height: Int(dimensions.height),
                blue: UInt8(index * 80)
            ) else {
                return XCTFail("Could not create pixel buffer")
            }
            XCTAssertTrue(adaptor.append(
                pixelBuffer,
                withPresentationTime: CMTime(value: CMTimeValue(index), timescale: CMTimeScale(frameRate))
            ))
        }

        input.markAsFinished()
        await withCheckedContinuation { continuation in
            writer.finishWriting { continuation.resume() }
        }
        XCTAssertEqual(writer.status, .completed, writer.error?.localizedDescription ?? "")
    }

    private func makePixelBuffer(width: Int, height: Int, blue: UInt8) -> CVPixelBuffer? {
        var buffer: CVPixelBuffer?
        let result = CVPixelBufferCreate(
            kCFAllocatorDefault,
            width,
            height,
            kCVPixelFormatType_32BGRA,
            [kCVPixelBufferIOSurfacePropertiesKey: [:]] as CFDictionary,
            &buffer
        )
        guard result == kCVReturnSuccess, let buffer else { return nil }

        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        guard let baseAddress = CVPixelBufferGetBaseAddress(buffer) else { return nil }
        let byteCount = CVPixelBufferGetBytesPerRow(buffer) * height
        let bytes = baseAddress.assumingMemoryBound(to: UInt8.self)
        for offset in stride(from: 0, to: byteCount, by: 4) {
            bytes[offset] = blue
            bytes[offset + 1] = 80
            bytes[offset + 2] = 220
            bytes[offset + 3] = 255
        }
        return buffer
    }
}
