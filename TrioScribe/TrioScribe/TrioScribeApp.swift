import SwiftUI

@main
struct TrioScribeApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(model)
                .frame(minWidth: 1_120, minHeight: 700)
        }
        .defaultSize(width: 1_360, height: 820)
        .windowStyle(.hiddenTitleBar)
    }
}

