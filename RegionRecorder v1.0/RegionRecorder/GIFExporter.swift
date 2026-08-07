import AVFoundation
import CoreImage
import ImageIO
import UniformTypeIdentifiers

enum GIFExporter {
    static func export(
        movieURL: URL,
        outputURL: URL,
        expectedFrameCount: Int,
        frameRate: Int
    ) async throws {
        try await Task.detached(priority: .userInitiated) {
            let asset = AVURLAsset(url: movieURL)
            let tracks = try await asset.loadTracks(withMediaType: .video)
            guard let track = tracks.first else {
                throw RecordingError.noFramesCaptured
            }

            let reader = try AVAssetReader(asset: asset)
            let output = AVAssetReaderTrackOutput(
                track: track,
                outputSettings: [
                    kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
                ]
            )
            output.alwaysCopiesSampleData = false
            guard reader.canAdd(output) else {
                throw RecordingError.gifEncodingFailed
            }
            reader.add(output)

            guard let destination = CGImageDestinationCreateWithURL(
                outputURL as CFURL,
                UTType.gif.identifier as CFString,
                max(1, expectedFrameCount),
                nil
            ) else {
                throw RecordingError.gifCreationFailed
            }

            let globalProperties: [CFString: Any] = [
                kCGImagePropertyGIFDictionary: [
                    kCGImagePropertyGIFLoopCount: 0
                ] as [CFString: Any]
            ]
            CGImageDestinationSetProperties(destination, globalProperties as CFDictionary)

            let delay = 1.0 / Double(frameRate)
            let frameProperties: [CFString: Any] = [
                kCGImagePropertyGIFDictionary: [
                    kCGImagePropertyGIFDelayTime: delay,
                    kCGImagePropertyGIFUnclampedDelayTime: delay
                ] as [CFString: Any]
            ]
            let context = CIContext(options: [.cacheIntermediates: false])
            defer { context.clearCaches() }

            guard reader.startReading() else {
                throw reader.error ?? RecordingError.gifEncodingFailed
            }

            var decodedFrames = 0
            while let sampleBuffer = output.copyNextSampleBuffer() {
                try autoreleasepool {
                    guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
                        throw RecordingError.gifEncodingFailed
                    }
                    let image = CIImage(cvPixelBuffer: pixelBuffer)
                    guard let cgImage = context.createCGImage(image, from: image.extent) else {
                        throw RecordingError.gifEncodingFailed
                    }
                    CGImageDestinationAddImage(destination, cgImage, frameProperties as CFDictionary)
                    decodedFrames += 1
                }
            }

            guard reader.status == .completed,
                  decodedFrames == expectedFrameCount,
                  CGImageDestinationFinalize(destination) else {
                throw reader.error ?? RecordingError.gifEncodingFailed
            }
        }.value
    }
}
