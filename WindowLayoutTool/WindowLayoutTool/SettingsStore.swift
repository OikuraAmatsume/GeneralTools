import Foundation

@MainActor
final class SettingsStore {
    static let shared = SettingsStore()

    private enum Key {
        static let monitoringEnabled = "monitoringEnabled"
        static let layoutsEnabled = "layoutsEnabled"
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: [
            Key.monitoringEnabled: true,
            Key.layoutsEnabled: true
        ])
    }

    var monitoringEnabled: Bool {
        get { defaults.bool(forKey: Key.monitoringEnabled) }
        set { defaults.set(newValue, forKey: Key.monitoringEnabled) }
    }

    var layoutsEnabled: Bool {
        get { defaults.bool(forKey: Key.layoutsEnabled) }
        set { defaults.set(newValue, forKey: Key.layoutsEnabled) }
    }
}
