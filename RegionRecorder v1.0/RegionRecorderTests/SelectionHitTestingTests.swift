import AppKit
import XCTest
@testable import RegionRecorder

final class SelectionHitTestingTests: XCTestCase {
    @MainActor
    func testOutlineInteriorDoesNotHitWindow() {
        let view = SelectionOutlineView(frame: CGRect(x: 0, y: 0, width: 400, height: 240))
        XCTAssertNil(view.hitTest(CGPoint(x: 200, y: 120)))
    }

    @MainActor
    func testOutlineRimIsHitTestable() {
        let view = SelectionOutlineView(frame: CGRect(x: 0, y: 0, width: 400, height: 240))
        XCTAssertTrue(view.hitTest(CGPoint(x: 2, y: 120)) === view)
        XCTAssertTrue(view.hitTest(CGPoint(x: 398, y: 238)) === view)
    }
}
