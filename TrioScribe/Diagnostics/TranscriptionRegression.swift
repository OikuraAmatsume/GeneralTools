import AVFoundation
import Foundation

@main
@MainActor
struct TranscriptionRegression {
    static let root = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Desktop/TrioScribe/Diagnostics", isDirectory: true)

    static func require(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        if !condition() { throw NSError(domain: "TrioScribeRegression", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
    }

    static func main() async {
        do {
            let disabled = NSError(domain: "kLSRErrorDomain", code: 201)
            try require(TranscriptionError.describe(disabled).contains("听写已关闭"), "Error 201 must be actionable")
            let fixtures: [(TranscriptionLanguage, String, String)] = [
                (.chinese, "Chinese.aiff", "文字"),
                (.english, "English.aiff", "transcription"),
                (.japanese, "Japanese.aiff", "日本語")
            ]
            for (language, name, expected) in fixtures {
                try await verify(language: language, source: root.appendingPathComponent(name), live: false, expected: expected)
                try await verify(language: language, source: root.appendingPathComponent(name), live: true, expected: expected)
            }
            try await verify(language: .english, source: root.appendingPathComponent("English.aiff"), live: true, expected: "transcription", repeats: 12)
            try await verifySilenceAndCancellation()
            if let recordingPath = CommandLine.arguments.dropFirst().first {
                let recording = URL(fileURLWithPath: recordingPath)
                try await verify(language: .chinese, source: recording, live: true, expected: nil)
                try await verify(language: .chinese, source: recording, live: false, expected: nil, output: root.appendingPathComponent("Recovered-Transcript.md"))
            }
            print("PASS: error reporting, 3-language file/live transcription, >1-minute stream, silence, cancellation, Markdown persistence")
        } catch {
            print("FAIL: \(error.localizedDescription)")
            exit(1)
        }
    }

    static func verify(language: TranscriptionLanguage, source: URL, live: Bool, expected: String?, repeats: Int = 1, output: URL? = nil) async throws {
        let engine = SpeechTranscriber()
        var segments: [TranscriptSegment] = []
        var partial = ""
        var issues: [Error] = []
        let update: TranscriptUpdate = { text, time, final in
            if final {
                if !text.isEmpty { segments.append(TranscriptSegment(timestamp: time, text: text)) }
                partial = ""
            } else { partial = text }
        }
        let started = Date()
        if live {
            let sink = try await engine.start(language: language, onUpdate: update, onStatus: { print($0) }, onError: { issues.append($0) })
            let file = try AVAudioFile(forReading: source)
            for _ in 0..<repeats {
                file.framePosition = 0
                while file.framePosition < file.length {
                    let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: 1_024)!
                    try file.read(into: buffer)
                    sink(buffer)
                    try await Task.sleep(for: .milliseconds(5))
                }
            }
            try await engine.finish()
        } else {
            try await engine.transcribeFile(at: source, language: language, onUpdate: update, onStatus: { print($0) }, onError: { issues.append($0) })
        }
        let text = segments.map(\.text).joined(separator: " ")
        try require(issues.isEmpty, "Recognition error: \(issues.map(\.localizedDescription))")
        try require(!text.isEmpty, "Empty \(language.rawValue) \(live ? "live" : "file") transcript")
        try require(partial.isEmpty, "Finalization left uncommitted words")
        if let expected { try require(text.lowercased().contains(expected.lowercased()), "Missing expected word: \(expected)") }
        if repeats > 1 {
            try require(text.lowercased().components(separatedBy: "transcription").count - 1 >= repeats - 1, "Long stream lost repeated phrases")
        }
        let destination = output ?? root.appendingPathComponent("\(live ? "Live" : "File")-\(language.rawValue)-\(repeats).md")
        try SessionStorage().writeTranscript(segments: segments, partialText: "", title: "TrioScribe transcription verification", statusMessage: "使用 0.1.2 本地引擎生成。", to: destination)
        let saved = try String(contentsOf: destination, encoding: .utf8)
        try require(saved.contains(segments[0].text), "Saved Markdown lacks recognized content")
        let count = segments.count
        await engine.cancel()
        try await Task.sleep(for: .milliseconds(150))
        try require(count == segments.count, "Stale callbacks changed a completed transcript")
        print("PASS \(language.rawValue) \(live ? "live" : "file") x\(repeats): \(text.count) characters, \(segments.count) segments, \(String(format: "%.1f", Date().timeIntervalSince(started)))s")
    }

    static func verifySilenceAndCancellation() async throws {
        let engine = SpeechTranscriber()
        var text = ""
        var errors: [Error] = []
        let sink = try await engine.start(language: .chinese, onUpdate: { value, _, _ in text += value }, onStatus: { _ in }, onError: { errors.append($0) })
        let format = AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1)!
        for _ in 0..<32 {
            let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 1_024)!
            buffer.frameLength = 1_024
            memset(buffer.floatChannelData![0], 0, 4 * 1_024)
            sink(buffer)
        }
        try await engine.finish()
        try require(text.isEmpty && errors.isEmpty, "Silence must complete without fabricated words")
        await engine.cancel()
        _ = try await engine.start(language: .chinese, onUpdate: { value, _, _ in text += value }, onStatus: { _ in }, onError: { errors.append($0) })
        await engine.cancel()
        try await Task.sleep(for: .milliseconds(200))
        try require(text.isEmpty && errors.isEmpty, "Cancellation leaked results or errors")
        print("PASS silence and cancellation")
    }
}
