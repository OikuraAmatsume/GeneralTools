import Foundation

enum DragPhase: Equatable {
    case idle
    case potentialDrag
    case activeDrag
    case hoveringLayout(LayoutSelection)
    case commit
    case cancel
}

enum DragTransitionEvent: Equatable {
    case mouseDownOnWindow
    case windowMovementConfirmed
    case hover(LayoutSelection)
    case hoverCleared
    case mouseUpWithSelection
    case mouseUpWithoutSelection
    case escape
    case failure
    case reset
}

struct DragStateMachine {
    private(set) var phase: DragPhase = .idle

    @discardableResult
    mutating func transition(_ event: DragTransitionEvent) -> Bool {
        let next: DragPhase?
        switch (phase, event) {
        case (.idle, .mouseDownOnWindow):
            next = .potentialDrag
        case (.potentialDrag, .windowMovementConfirmed):
            next = .activeDrag
        case (.activeDrag, .hover(let selection)), (.hoveringLayout, .hover(let selection)):
            next = .hoveringLayout(selection)
        case (.hoveringLayout, .hoverCleared):
            next = .activeDrag
        case (.hoveringLayout, .mouseUpWithSelection):
            next = .commit
        case (.potentialDrag, .mouseUpWithoutSelection),
             (.activeDrag, .mouseUpWithoutSelection),
             (.hoveringLayout, .mouseUpWithoutSelection):
            next = .cancel
        case (.potentialDrag, .escape), (.activeDrag, .escape), (.hoveringLayout, .escape),
             (.potentialDrag, .failure), (.activeDrag, .failure), (.hoveringLayout, .failure):
            next = .cancel
        case (.commit, .reset), (.cancel, .reset):
            next = .idle
        default:
            next = nil
        }

        guard let next else { return false }
        phase = next
        return true
    }
}
