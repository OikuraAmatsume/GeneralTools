import Foundation

enum OutputDestinationError: LocalizedError {
    case desktopUnavailable
    case cannotCreateOutputFolder(String)

    var errorDescription: String? {
        switch self {
        case .desktopUnavailable:
            "无法找到桌面文件夹。"
        case .cannotCreateOutputFolder(let details):
            "无法创建桌面上的 RegionRecorder 文件夹：\(details)"
        }
    }
}

enum OutputDestination {
    static let folderName = "RegionRecorder"

    static func makeURL(
        for format: RecordingFormat,
        now: Date = Date(),
        fileManager: FileManager = .default,
        desktopDirectory: URL? = nil
    ) throws -> URL {
        guard let desktop = desktopDirectory ?? fileManager.urls(
            for: .desktopDirectory,
            in: .userDomainMask
        ).first else {
            throw OutputDestinationError.desktopUnavailable
        }

        let folder = desktop.appendingPathComponent(folderName, isDirectory: true)
        do {
            try fileManager.createDirectory(
                at: folder,
                withIntermediateDirectories: true,
                attributes: nil
            )
        } catch {
            throw OutputDestinationError.cannotCreateOutputFolder(error.localizedDescription)
        }

        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let baseName = "RegionRecorder-\(formatter.string(from: now))"

        var suffix = 1
        while true {
            let suffixText = suffix == 1 ? "" : "-\(suffix)"
            let candidate = folder.appendingPathComponent(
                "\(baseName)\(suffixText).\(format.filenameExtension)"
            )
            if !fileManager.fileExists(atPath: candidate.path) {
                return candidate
            }
            suffix += 1
        }
    }
}
