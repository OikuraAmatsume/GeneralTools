import XCTest
@testable import WindowLayoutTool

final class DragStateMachineTests: XCTestCase {
    private let selection = LayoutSelection(layoutID: "halves", regionID: "left")

    func testSuccessfulStatePath() {
        var machine = DragStateMachine()
        XCTAssertTrue(machine.transition(.mouseDownOnWindow))
        XCTAssertEqual(machine.phase, .potentialDrag)
        XCTAssertTrue(machine.transition(.windowMovementConfirmed))
        XCTAssertEqual(machine.phase, .activeDrag)
        XCTAssertTrue(machine.transition(.hover(selection)))
        XCTAssertEqual(machine.phase, .hoveringLayout(selection))
        XCTAssertTrue(machine.transition(.mouseUpWithSelection))
        XCTAssertEqual(machine.phase, .commit)
        XCTAssertTrue(machine.transition(.reset))
        XCTAssertEqual(machine.phase, .idle)
    }

    func testOrdinaryClickCancelsWithoutActivation() {
        var machine = DragStateMachine()
        XCTAssertTrue(machine.transition(.mouseDownOnWindow))
        XCTAssertTrue(machine.transition(.mouseUpWithoutSelection))
        XCTAssertEqual(machine.phase, .cancel)
        XCTAssertTrue(machine.transition(.reset))
        XCTAssertEqual(machine.phase, .idle)
    }

    func testHoverCanClearAndEscapeRecovers() {
        var machine = DragStateMachine()
        _ = machine.transition(.mouseDownOnWindow)
        _ = machine.transition(.windowMovementConfirmed)
        _ = machine.transition(.hover(selection))
        XCTAssertTrue(machine.transition(.hoverCleared))
        XCTAssertEqual(machine.phase, .activeDrag)
        XCTAssertTrue(machine.transition(.escape))
        XCTAssertEqual(machine.phase, .cancel)
        XCTAssertTrue(machine.transition(.reset))
        XCTAssertEqual(machine.phase, .idle)
    }

    func testFailureFromPotentialAndActiveRecovers() {
        for activate in [false, true] {
            var machine = DragStateMachine()
            _ = machine.transition(.mouseDownOnWindow)
            if activate { _ = machine.transition(.windowMovementConfirmed) }
            XCTAssertTrue(machine.transition(.failure))
            XCTAssertEqual(machine.phase, .cancel)
            XCTAssertTrue(machine.transition(.reset))
            XCTAssertEqual(machine.phase, .idle)
        }
    }

    func testInvalidCommitFromActiveDragIsRejected() {
        var machine = DragStateMachine()
        _ = machine.transition(.mouseDownOnWindow)
        _ = machine.transition(.windowMovementConfirmed)
        XCTAssertFalse(machine.transition(.mouseUpWithSelection))
        XCTAssertEqual(machine.phase, .activeDrag)
    }
}
