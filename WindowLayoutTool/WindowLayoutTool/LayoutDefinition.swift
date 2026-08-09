import Foundation
import CoreGraphics

struct NormalizedRect: Equatable, Hashable {
    let x: CGFloat
    let y: CGFloat
    let width: CGFloat
    let height: CGFloat

    var cgRect: CGRect { CGRect(x: x, y: y, width: width, height: height) }
}

struct LayoutRegion: Identifiable, Equatable, Hashable {
    let id: String
    let normalizedFrame: NormalizedRect
}

struct LayoutDefinition: Identifiable, Equatable {
    let id: String
    let name: String
    let regions: [LayoutRegion]

    static let builtIn: [LayoutDefinition] = [
        LayoutDefinition(
            id: "main-right-stack",
            name: "主窗 + 右侧",
            regions: [
                LayoutRegion(id: "main", normalizedFrame: .init(x: 0, y: 0, width: 0.65, height: 1)),
                LayoutRegion(id: "right-top", normalizedFrame: .init(x: 0.65, y: 0.5, width: 0.35, height: 0.5)),
                LayoutRegion(id: "right-bottom", normalizedFrame: .init(x: 0.65, y: 0, width: 0.35, height: 0.5))
            ]
        ),
        LayoutDefinition(
            id: "halves",
            name: "左右均分",
            regions: [
                LayoutRegion(id: "left", normalizedFrame: .init(x: 0, y: 0, width: 0.5, height: 1)),
                LayoutRegion(id: "right", normalizedFrame: .init(x: 0.5, y: 0, width: 0.5, height: 1))
            ]
        ),
        LayoutDefinition(
            id: "maximize",
            name: "最大化",
            regions: [
                LayoutRegion(id: "full", normalizedFrame: .init(x: 0, y: 0, width: 1, height: 1))
            ]
        ),
        LayoutDefinition(
            id: "large-left",
            name: "Large Left",
            regions: [
                LayoutRegion(id: "large-left", normalizedFrame: .init(x: 0, y: 0, width: 0.65, height: 1)),
                LayoutRegion(id: "small-right", normalizedFrame: .init(x: 0.65, y: 0, width: 0.35, height: 1))
            ]
        )
    ]
}

struct LayoutSelection: Equatable, Hashable {
    let layoutID: String
    let regionID: String
}
