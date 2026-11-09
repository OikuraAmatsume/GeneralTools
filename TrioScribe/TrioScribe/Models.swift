import Foundation

enum CaptureMode: String, CaseIterable, Identifiable {
    case live = "实时收音"
    case importMedia = "导入视频"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .live: "waveform"
        case .importMedia: "square.and.arrow.down"
        }
    }
}

enum TranscriptionLanguage: String, CaseIterable, Identifiable {
    case chinese
    case english
    case japanese

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .chinese: "中文"
        case .english: "English"
        case .japanese: "日本語"
        }
    }

    var localeIdentifier: String {
        switch self {
        case .chinese: "zh-CN"
        case .english: "en-US"
        case .japanese: "ja-JP"
        }
    }
}

struct CaptureApplication: Identifiable, Hashable {
    let processID: Int32
    let name: String
    let bundleIdentifier: String

    var id: Int32 { processID }
}

struct TranscriptSegment: Identifiable, Equatable {
    let id = UUID()
    let timestamp: TimeInterval
    let text: String

    var timestampLabel: String {
        Self.format(timestamp)
    }

    static func format(_ interval: TimeInterval) -> String {
        let totalSeconds = max(0, Int(interval))
        let hours = totalSeconds / 3_600
        let minutes = (totalSeconds % 3_600) / 60
        let seconds = totalSeconds % 60

        if hours > 0 {
            return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%02d:%02d", minutes, seconds)
    }
}

enum SessionState: Equatable {
    case idle
    case starting
    case capturing
    case paused
    case importing
    case stopping

    var isBusy: Bool {
        self == .starting || self == .importing || self == .stopping
    }
}

