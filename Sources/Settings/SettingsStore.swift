import Foundation

class SettingsStore {
    private let hiddenKey = "hiddenDeviceIDs"
    private let thresholdKey = "lowBatteryThreshold"

    private(set) var hiddenDeviceIDs: Set<String> {
        didSet {
            UserDefaults.standard.set(Array(hiddenDeviceIDs), forKey: hiddenKey)
        }
    }

    private(set) var lowBatteryThreshold: Int {
        didSet {
            UserDefaults.standard.set(lowBatteryThreshold, forKey: thresholdKey)
        }
    }

    init() {
        let stored = UserDefaults.standard.stringArray(forKey: hiddenKey) ?? []
        hiddenDeviceIDs = Set(stored)
        let savedThreshold = UserDefaults.standard.integer(forKey: thresholdKey)
        lowBatteryThreshold = savedThreshold > 0 ? savedThreshold : 10
    }

    func setLowBatteryThreshold(_ value: Int) {
        lowBatteryThreshold = value
    }

    func isHidden(_ id: String) -> Bool {
        hiddenDeviceIDs.contains(id)
    }

    func toggleVisibility(_ id: String) {
        if hiddenDeviceIDs.contains(id) {
            hiddenDeviceIDs.remove(id)
        } else {
            hiddenDeviceIDs.insert(id)
        }
    }
}
