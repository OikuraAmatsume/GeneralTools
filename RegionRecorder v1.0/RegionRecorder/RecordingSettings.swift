import Foundation

enum RecordingFormat: Int, CaseIterable {
    case mp4
    case gif

    var title: String {
        switch self {
        case .mp4: "MP4"
        case .gif: "GIF"
        }
    }

    var filenameExtension: String {
        switch self {
        case .mp4: "mp4"
        case .gif: "gif"
        }
    }
}

struct RecordingSettings: Equatable {
    var format: RecordingFormat = .mp4
    var frameRate: Int = 30
    var outputScale: Double = 1.0

    static let availableFrameRates = [15, 24, 30, 60]
    static let availableScales = [0.25, 0.5, 0.75, 1.0]
}
