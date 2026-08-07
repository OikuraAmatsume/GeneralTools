import XCTest
@testable import RegionRecorder

final class CaptureGeometryTests: XCTestCase {
    func testAppKitRectConvertsToDisplayLocalTopLeftCoordinates() {
        let screen = CGRect(x: -1920, y: 0, width: 1920, height: 1080)
        let capture = CGRect(x: -1800, y: 100, width: 800, height: 450)

        XCTAssertEqual(
            CaptureGeometry.sourceRect(captureFrame: capture, in: screen),
            CGRect(x: 120, y: 530, width: 800, height: 450)
        )
    }

    func testRetinaPixelSizeUsesBackingScaleAndOutputScale() {
        let full = CaptureGeometry.outputPixelSize(
            captureSize: CGSize(width: 800, height: 450),
            backingScaleFactor: 2,
            outputScale: 1
        )
        let half = CaptureGeometry.outputPixelSize(
            captureSize: CGSize(width: 800, height: 450),
            backingScaleFactor: 2,
            outputScale: 0.5
        )

        XCTAssertEqual(full, CGSize(width: 1600, height: 900))
        XCTAssertEqual(half, CGSize(width: 800, height: 450))
    }

    func testEncoderDimensionsAreAlwaysEven() {
        let size = CaptureGeometry.outputPixelSize(
            captureSize: CGSize(width: 333, height: 201),
            backingScaleFactor: 1.5,
            outputScale: 0.75
        )

        XCTAssertEqual(Int(size.width) % 2, 0)
        XCTAssertEqual(Int(size.height) % 2, 0)
        XCTAssertGreaterThan(size.width, 0)
        XCTAssertGreaterThan(size.height, 0)
    }

    func testClampingKeepsRegionInsideVisibleDisplayFrame() {
        let bounds = CGRect(x: 100, y: -900, width: 1440, height: 900)
        let proposed = CGRect(x: 1500, y: -1000, width: 400, height: 100)
        let result = CaptureGeometry.clamped(proposed, to: bounds)

        XCTAssertTrue(bounds.contains(result))
        XCTAssertGreaterThanOrEqual(result.width, CaptureGeometry.minimumCaptureSize.width)
        XCTAssertGreaterThanOrEqual(result.height, CaptureGeometry.minimumCaptureSize.height)
    }

    func testDefaultOutputUsesDesktopRegionRecorderFolderAndAvoidsCollisions() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("RegionRecorderOutputTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let first = try OutputDestination.makeURL(
            for: .mp4,
            now: date,
            desktopDirectory: root
        )
        XCTAssertEqual(first.deletingLastPathComponent().lastPathComponent, "RegionRecorder")
        XCTAssertEqual(first.pathExtension, "mp4")

        XCTAssertTrue(FileManager.default.createFile(atPath: first.path, contents: Data()))
        let second = try OutputDestination.makeURL(
            for: .mp4,
            now: date,
            desktopDirectory: root
        )
        XCTAssertNotEqual(first, second)
        XCTAssertTrue(second.deletingPathExtension().lastPathComponent.hasSuffix("-2"))
    }
}
