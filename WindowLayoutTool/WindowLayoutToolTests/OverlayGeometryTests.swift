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
}
