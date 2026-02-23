import Foundation

class SettingsStore {
    private let hiddenKey = "hiddenDeviceIDs"
    private let thresholdKey = "lowBatteryThreshold"
    private let refreshIntervalKey = "refreshInterval"
    private let showPercentageKey = "showPercentage"
    private let displayModeKey = "displayMode"
    private let customNamesKey = "customDeviceNames"
    private let deviceOrderKey = "deviceOrder"
    private let customIconsKey = "customDeviceIcons"

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

    private(set) var displayMode: String {
        didSet {
            UserDefaults.standard.set(displayMode, forKey: displayModeKey)
        }
    }

    private(set) var customDeviceNames: [String: String] {
        didSet {
            UserDefaults.standard.set(customDeviceNames, forKey: customNamesKey)
        }
    }

    private(set) var deviceOrder: [String] {
        didSet {
            UserDefaults.standard.set(deviceOrder, forKey: deviceOrderKey)
        }
    }

    private(set) var customDeviceIcons: [String: String] {
        didSet {
            UserDefaults.standard.set(customDeviceIcons, forKey: customIconsKey)
        }
    }

    var isSingleMode: Bool {
        displayMode == "single" || displayMode == "compact"
    }

    var isCompactMode: Bool {
        displayMode == "compact"
    }

    var isStackedMode: Bool {
        displayMode == "stacked"
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
        displayMode = UserDefaults.standard.string(forKey: displayModeKey) ?? "separate"
        customDeviceNames = (UserDefaults.standard.dictionary(forKey: customNamesKey) as? [String: String]) ?? [:]
        deviceOrder = UserDefaults.standard.stringArray(forKey: deviceOrderKey) ?? []
        customDeviceIcons = (UserDefaults.standard.dictionary(forKey: customIconsKey) as? [String: String]) ?? [:]
    }

    func setLowBatteryThreshold(_ value: Int) {
        lowBatteryThreshold = min(max(value, 5), 25)
    }

    func setRefreshInterval(_ value: Int) {
        refreshInterval = min(max(value, 10), 120)
    }

    func setShowPercentage(_ value: Bool) {
        showPercentage = value
    }

    private static let validDisplayModes: Set<String> = ["separate", "single", "compact", "stacked"]

    func setDisplayMode(_ value: String) {
        displayMode = Self.validDisplayModes.contains(value) ? value : "separate"
    }

    func setCustomName(_ name: String?, for deviceID: String) {
        if let name = name, !name.isEmpty {
            customDeviceNames[deviceID] = name
        } else {
            customDeviceNames.removeValue(forKey: deviceID)
        }
    }

    func displayName(for device: BluetoothDevice) -> String {
        customDeviceNames[device.id] ?? device.name
    }

    func setCustomIcon(_ icon: String?, for deviceID: String) {
        if let icon = icon, !icon.isEmpty {
            customDeviceIcons[deviceID] = icon
        } else {
            customDeviceIcons.removeValue(forKey: deviceID)
        }
    }

    func iconName(for device: BluetoothDevice) -> String {
        customDeviceIcons[device.id] ?? device.deviceType.sfSymbolName
    }

    func setDeviceOrder(_ order: [String]) {
        deviceOrder = order
    }

    func moveDevice(_ deviceID: String, direction: Int) {
        guard let index = deviceOrder.firstIndex(of: deviceID) else { return }
        let newIndex = index + direction
        guard newIndex >= 0 && newIndex < deviceOrder.count else { return }
        deviceOrder.swapAt(index, newIndex)
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
