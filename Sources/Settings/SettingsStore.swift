import Foundation

class SettingsStore {
    private let hiddenKey = "hiddenDeviceIDs"
    private let thresholdKey = "lowBatteryThreshold"
    private let refreshIntervalKey = "refreshInterval"
    private let showPercentageKey = "showPercentage"

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

    private(set) var refreshInterval: Int {
        didSet {
            UserDefaults.standard.set(refreshInterval, forKey: refreshIntervalKey)
        }
    }

    private(set) var showPercentage: Bool {
        didSet {
            UserDefaults.standard.set(showPercentage, forKey: showPercentageKey)
        }
    }

    init() {
        let stored = UserDefaults.standard.stringArray(forKey: hiddenKey) ?? []
        hiddenDeviceIDs = Set(stored)
        let savedThreshold = UserDefaults.standard.integer(forKey: thresholdKey)
        lowBatteryThreshold = savedThreshold > 0 ? savedThreshold : 10
        let savedInterval = UserDefaults.standard.integer(forKey: refreshIntervalKey)
        refreshInterval = savedInterval > 0 ? savedInterval : 30
        if UserDefaults.standard.object(forKey: showPercentageKey) != nil {
            showPercentage = UserDefaults.standard.bool(forKey: showPercentageKey)
        } else {
            showPercentage = true
        }
    }

    func setLowBatteryThreshold(_ value: Int) {
        lowBatteryThreshold = value
    }

    func setRefreshInterval(_ value: Int) {
        refreshInterval = value
    }

    func setShowPercentage(_ value: Bool) {
        showPercentage = value
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
