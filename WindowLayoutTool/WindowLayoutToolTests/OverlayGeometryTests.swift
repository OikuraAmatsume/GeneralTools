import XCTest
@testable import WindowLayoutTool

final class OverlayGeometryTests: XCTestCase {
    func testEveryBuiltInRegionCanBeHitIndependently() {
        let layouts = LayoutDefinition.builtIn
        let bounds = CGRect(origin: .zero, size: OverlayGeometry.panelSize(layoutCount: layouts.count))
        let hitRegions = OverlayGeometry.hitRegions(in: bounds, layouts: layouts)

        XCTAssertEqual(hitRegions.count, layouts.reduce(0) { $0 + $1.regions.count })
        for hit in hitRegions {
            XCTAssertEqual(
                OverlayGeometry.selection(at: CGPoint(x: hit.frame.midX, y: hit.frame.midY), in: bounds, layouts: layouts),
                hit.selection
            )
        }
    }

    func testPointOutsidePanelContentHasNoSelection() {
        let layouts = LayoutDefinition.builtIn
        let bounds = CGRect(origin: .zero, size: OverlayGeometry.panelSize(layoutCount: layouts.count))
        XCTAssertNil(OverlayGeometry.selection(at: CGPoint(x: 1, y: 1), in: bounds, layouts: layouts))
    }

    func testPanelIsCenteredAtOneThirdOfVisibleHeight() {
        let visibleFrame = CGRect(x: 0, y: 25, width: 1440, height: 875)
        let size = OverlayGeometry.panelSize(layoutCount: LayoutDefinition.builtIn.count)
        let origin = OverlayGeometry.panelOrigin(size: size, in: visibleFrame)

        XCTAssertEqual(origin.x + size.width / 2, visibleFrame.midX, accuracy: 0.001)
        XCTAssertEqual(
            origin.y + size.height / 2,
            visibleFrame.minY + visibleFrame.height / 3,
            accuracy: 0.001
        )
    }

    func testPanelPositionSupportsNegativeDisplayCoordinates() {
        let visibleFrame = CGRect(x: -1920, y: -180, width: 1920, height: 1050)
        let size = OverlayGeometry.panelSize(layoutCount: LayoutDefinition.builtIn.count)
        let origin = OverlayGeometry.panelOrigin(size: size, in: visibleFrame)

        XCTAssertEqual(origin.x + size.width / 2, visibleFrame.midX, accuracy: 0.001)
        XCTAssertEqual(
            origin.y + size.height / 2,
            visibleFrame.minY + visibleFrame.height / 3,
            accuracy: 0.001
        )
        XCTAssertGreaterThanOrEqual(origin.y, visibleFrame.minY)
    }

    func testPanelSizeIsLargeEnoughForReadablePreviews() {
        let size = OverlayGeometry.panelSize(layoutCount: LayoutDefinition.builtIn.count)
        XCTAssertGreaterThanOrEqual(size.width, 560)
        XCTAssertGreaterThanOrEqual(size.height, 120)
    }
}
