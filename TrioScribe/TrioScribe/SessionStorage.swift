import Foundation

struct SessionFiles {
    let directory: URL
    let audioURL: URL?
    let transcriptURL: URL
}

final class SessionStorage {
    enum StorageError: LocalizedError {
        case desktopUnavailable

        var errorDescription: String? {
            "无法找到桌面文件夹。"
        }
    }

    private let fileManager = FileManager.default
    private let rootOverride: URL?

    init(rootDirectory: URL? = nil) { rootOverride = rootDirectory }

    var rootDirectory: URL {
        get throws {
            if let rootOverride { return rootOverride }
            guard let desktop = fileManager.urls(for: .desktopDirectory, in: .userDomainMask).first else {
                throw StorageError.desktopUnavailable
            }
            return desktop.appendingPathComponent("TrioScribe", isDirectory: true)
        }
    }

    func ensureRootDirectory() throws -> URL {
        let root = try rootDirectory
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    func createLiveSession() throws -> SessionFiles {
        let directory = try createSessionDirectory(prefix: "Recording")
        return SessionFiles(
            directory: directory,
            audioURL: directory.appendingPathComponent("Audio.wav"),
            transcriptURL: directory.appendingPathComponent("Transcript.md")
        )
    }

    func createImportSession(fileName: String) throws -> SessionFiles {
        let sourceName = URL(fileURLWithPath: fileName)
            .deletingPathExtension()
            .lastPathComponent
        let safeName = sanitized(sourceName)
        let prefix = safeName.isEmpty ? "Import" : "Import-\(safeName)"
        let directory = try createSessionDirectory(prefix: prefix)
        return SessionFiles(
            directory: directory,
            audioURL: nil,
            transcriptURL: directory.appendingPathComponent("Transcript.md")
        )
    }

    func writeTranscript(
        segments: [TranscriptSegment],
        partialText: String,
        title: String,
        statusMessage: String? = nil,
        to url: URL
    ) throws {
        let completed = segments
            .map { "**[\($0.timestampLabel)]** \($0.text)" }
            .joined(separator: "\n\n")
        let partial = partialText.trimmingCharacters(in: .whitespacesAndNewlines)
        let draft = partial.isEmpty ? "" : "\n\n> 正在识别：\(partial)"
        let status = statusMessage.map { "> \($0.replacingOccurrences(of: "\n", with: " "))\n\n" } ?? ""
        let document = "# \(title)\n\n\(status)\(completed)\(draft)\n"
        try document.write(to: url, atomically: true, encoding: .utf8)
    }

    private func createSessionDirectory(prefix: String) throws -> URL {
        let root = try ensureRootDirectory()
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let timestamp = formatter.string(from: Date())

        var directory = root.appendingPathComponent("\(prefix)-\(timestamp)", isDirectory: true)
        if fileManager.fileExists(atPath: directory.path) {
            directory = root.appendingPathComponent(
                "\(prefix)-\(timestamp)-\(UUID().uuidString.prefix(6))",
                isDirectory: true
            )
        }

        try fileManager.createDirectory(at: directory, withIntermediateDirectories: false)
        return directory
    }

    private func sanitized(_ value: String) -> String {
        let invalid = CharacterSet(charactersIn: "/:\\?%*|\"<>")
        return value
            .components(separatedBy: invalid)
            .joined(separator: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

