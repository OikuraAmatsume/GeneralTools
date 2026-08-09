import XCTest
@testable import WindowLayoutTool

final class LayoutEngineTests: XCTestCase {
    func testNormalizedMappingIntoVisibleFrame() {
        let visible = CGRect(x: 0, y: 25, width: 1440, height: 875)
        let left = NormalizedRect(x: 0, y: 0, width: 0.5, height: 1)
        XCTAssertEqual(LayoutEngine.frame(for: left, in: visible), CGRect(x: 0, y: 25, width: 720, height: 875))
    }

    func testVisibleFrameWithLeftDock() {
        let visible = CGRect(x: 80, y: 0, width: 1360, height: 900)
        let largeLeft = NormalizedRect(x: 0, y: 0, width: 0.65, height: 1)
        XCTAssertEqual(
            LayoutEngine.frame(for: largeLeft, in: visible),
            CGRect(x: 80, y: 0, width: 884, height: 900)
        )
    }

    func testVisibleFrameWithRightDockAndNegativeDisplayOrigin() {
        let visible = CGRect(x: -1920, y: 0, width: 1840, height: 1080)
        let right = NormalizedRect(x: 0.65, y: 0, width: 0.35, height: 1)
        let result = LayoutEngine.frame(for: right, in: visible)
        XCTAssertEqual(result.origin.x, -724, accuracy: 0.001)
        XCTAssertEqual(result.width, 644, accuracy: 0.001)
        XCTAssertEqual(result.height, 1080, accuracy: 0.001)
    }

    func testBuiltInLayoutsExposeEveryPartition() {
        XCTAssertEqual(LayoutDefinition.builtIn.count, 4)
        XCTAssertEqual(LayoutDefinition.builtIn.map(\.regions.count), [3, 2, 1, 2])
        for layout in LayoutDefinition.builtIn {
            for region in layout.regions {
                XCTAssertGreaterThan(region.normalizedFrame.width, 0)
                XCTAssertGreaterThan(region.normalizedFrame.height, 0)
            }
        }
    }
}
