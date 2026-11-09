import AVFoundation
import Foundation

@main
@MainActor
struct SessionLifecycleTests {
    static func check(_ value: @autoclosure () -> Bool, _ message: String) throws {
        if !value() { throw NSError(domain: "SessionLifecycleTests", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
    }

    static func main() async {
        do {
            let root = try SessionStorage().rootDirectory.appendingPathComponent("Diagnostics", isDirectory: true)
            let storage = SessionStorage(rootDirectory: root.appendingPathComponent("SessionTests"))
            let model = AppModel(storage: storage, refreshApplications: false)
            model.language = .english
            await model.transcribeMedia(at: root.appendingPathComponent("English.aiff"))
            try check(model.state == .idle && model.errorMessage == nil, "Import failed to return to idle")
            try check(model.segments.count >= 2 && model.partialTranscript.isEmpty, "Import lost segments or left a draft")
            let transcript = try String(contentsOf: model.currentSessionDirectory!.appendingPathComponent("Transcript.md"), encoding: .utf8)
            try check(transcript.contains("transcription") && transcript.contains("saved"), "App failed to persist the full import")
            print("PASS: multi-segment import and completed Markdown")

            await model.transcribeMedia(at: root.appendingPathComponent("Missing.wav"))
            try check(model.state == .idle && model.errorMessage != nil, "Read failure was hidden or stuck")
            let failed = try String(contentsOf: model.currentSessionDirectory!.appendingPathComponent("Transcript.md"), encoding: .utf8)
            try check(failed.contains("失败") || failed.contains("无法"), "Failed session saved an unexplained empty document")
            print("PASS: import failure is visible and persisted")

            let oldTask = Task { await model.transcribeMedia(at: root.appendingPathComponent("English.aiff")) }
            try await Task.sleep(for: .milliseconds(10))
            await model.cancelImport()
            try check(model.state == .idle && model.recognitionStatus == "已取消", "Cancel failed")
            model.language = .japanese
            await model.transcribeMedia(at: root.appendingPathComponent("Japanese.aiff"))
            await oldTask.value
            try check(model.errorMessage == nil && model.state == .idle, "Cancelled operation changed the next session")
            try check(model.segments.map(\.text).joined().contains("日本語"), "New session did not retain its own results")
            print("PASS: cancel and immediately start a different language without stale callbacks")
        } catch {
            print("FAIL: \(error.localizedDescription)")
            exit(1)
        }
    }
}
