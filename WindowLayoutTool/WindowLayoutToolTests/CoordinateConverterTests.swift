import XCTest
@testable import WindowLayoutTool

final class CoordinateConverterTests: XCTestCase {
    private let converter = ScreenCoordinateConverter(primaryScreenFrame: CGRect(x: 0, y: 0, width: 1728, height: 1117))

    func testPointRoundTripOnPrimaryDisplay() {
        let appKit = CGPoint(x: 900, y: 217)
        let ax = converter.appKitPointToAX(appKit)
        XCTAssertEqual(ax, CGPoint(x: 900, y: 900))
        XCTAssertEqual(converter.axPointToAppKit(ax), appKit)
    }

    func testNegativeCoordinateDisplayToLeft() {
        let appKit = CGPoint(x: -1200, y: 700)
        let ax = converter.appKitPointToAX(appKit)
        XCTAssertEqual(ax, CGPoint(x: -1200, y: 417))
        XCTAssertEqual(converter.axPointToAppKit(ax), appKit)
    }

    func testDisplayAbovePrimaryProducesNegativeAXY() {
        let appKit = CGPoint(x: 200, y: 1500)
        let ax = converter.appKitPointToAX(appKit)
        XCTAssertEqual(ax.y, -383)
        XCTAssertEqual(converter.axPointToAppKit(ax), appKit)
    }

    func testRectConvertsTopLeftOriginAndRoundTrips() {
        let appKit = CGRect(x: -900, y: 200, width: 600, height: 500)
        let ax = converter.appKitRectToAX(appKit)
        XCTAssertEqual(ax, CGRect(x: -900, y: 417, width: 600, height: 500))
        XCTAssertEqual(converter.axRectToAppKit(ax), appKit)
    }
}
