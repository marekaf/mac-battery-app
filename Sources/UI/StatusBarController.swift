import AppKit
import ServiceManagement

class StatusBarController {
    private var statusItems: [String: NSStatusItem] = [:]
    private var anchorItem: NSStatusItem?
    private var singleItem: NSStatusItem?
    var settingsStore: SettingsStore?
    var allDevices: [BluetoothDevice] = []

    func update(devices: [BluetoothDevice]) {
        allDevices = devices
        guard let store = settingsStore else { return }

        let visibleDevices = devices.filter { !store.isHidden($0.id) }

        if visibleDevices.isEmpty && !devices.isEmpty {
            removeAllSeparateItems()
            removeSingleItem()
            showAnchorItem(allDevices: devices)
            return
        }

        removeAnchorItem()

        if store.isSingleMode {
            removeAllSeparateItems()
            updateSingleMode(visibleDevices: visibleDevices, allDevices: devices)
        } else {
            removeSingleItem()
            updateSeparateMode(visibleDevices: visibleDevices, allDevices: devices)
        }
    }

    private func updateSeparateMode(visibleDevices: [BluetoothDevice], allDevices: [BluetoothDevice]) {
        let visibleIDs = Set(visibleDevices.map { $0.id })
        let existingIDs = Set(statusItems.keys)

        for id in existingIDs.subtracting(visibleIDs) {
            if let item = statusItems.removeValue(forKey: id) {
                NSStatusBar.system.removeStatusItem(item)
            }
        }

        for device in visibleDevices {
            let item = statusItems[device.id] ?? createStatusItem()
            statusItems[device.id] = item
            configureStatusItemAppearance(item, for: device)
            item.menu = buildSeparateModeMenu(allDevices: allDevices, infoDevice: device)
        }
    }

    private func updateSingleMode(visibleDevices: [BluetoothDevice], allDevices: [BluetoothDevice]) {
        guard let lowestDevice = visibleDevices.min(by: { $0.batteryLevel < $1.batteryLevel }) else {
            removeSingleItem()
            return
        }

        if singleItem == nil {
            singleItem = createStatusItem()
        }
        guard let item = singleItem else { return }

        configureStatusItemAppearance(item, for: lowestDevice)
        item.menu = buildSingleModeMenu(visibleDevices: visibleDevices, allDevices: allDevices)
    }

    private func createStatusItem() -> NSStatusItem {
        NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    }

    private func showAnchorItem(allDevices: [BluetoothDevice]) {
        if anchorItem == nil {
            anchorItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        }
        guard let item = anchorItem, let button = item.button else { return }

        if let img = NSImage(systemSymbolName: "battery.100percent", accessibilityDescription: "BatteryBar") {
            let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .medium)
            button.image = img.withSymbolConfiguration(config) ?? img
        }
        button.toolTip = "BatteryBar — all devices hidden"

        let menu = NSMenu()
        appendDeviceToggles(to: menu, allDevices: allDevices)
        menu.addItem(NSMenuItem.separator())
        appendSettingsMenuItems(to: menu)
        item.menu = menu
    }

    private func removeAnchorItem() {
        if let item = anchorItem {
            NSStatusBar.system.removeStatusItem(item)
            anchorItem = nil
        }
    }

    private func removeAllSeparateItems() {
        for (_, item) in statusItems {
            NSStatusBar.system.removeStatusItem(item)
        }
        statusItems.removeAll()
    }

    private func removeSingleItem() {
        if let item = singleItem {
            NSStatusBar.system.removeStatusItem(item)
            singleItem = nil
        }
    }

    private func configureStatusItemAppearance(_ item: NSStatusItem, for device: BluetoothDevice) {
        guard let button = item.button else { return }

        let threshold = settingsStore?.lowBatteryThreshold ?? 10
        let showPct = settingsStore?.showPercentage ?? true
        let isLow = device.batteryLevel <= threshold
        let color: NSColor = isLow ? .systemRed : .headerTextColor
        let text = showPct ? " \(device.batteryLevel)%" : ""
        let a11yDescription = "\(device.name) battery"

        let textAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .regular),
            .foregroundColor: color,
            .baselineOffset: 1 as NSNumber
        ]

        let attributed = NSMutableAttributedString()

        if isLow {
            button.image?.isTemplate = false
            if let symbolImage = NSImage(systemSymbolName: device.deviceType.sfSymbolName, accessibilityDescription: a11yDescription) {
                let config = NSImage.SymbolConfiguration(pointSize: 12, weight: .medium)
                    .applying(NSImage.SymbolConfiguration(paletteColors: [.systemRed]))
                let configured = symbolImage.withSymbolConfiguration(config) ?? symbolImage
                let attachment = NSTextAttachment()
                attachment.image = configured
                attributed.append(NSAttributedString(attachment: attachment))
            }
        } else {
            if let symbolImage = NSImage(systemSymbolName: device.deviceType.sfSymbolName, accessibilityDescription: a11yDescription) {
                let config = NSImage.SymbolConfiguration(pointSize: 12, weight: .medium)
                let configured = symbolImage.withSymbolConfiguration(config) ?? symbolImage
                let attachment = NSTextAttachment()
                attachment.image = configured
                attributed.append(NSAttributedString(attachment: attachment))
            }
        }

        if showPct {
            attributed.append(NSAttributedString(string: text, attributes: textAttrs))
        }

        button.attributedTitle = attributed
        button.toolTip = "\(device.name): \(device.batteryLevel)%"
    }

    private func buildSeparateModeMenu(allDevices: [BluetoothDevice], infoDevice: BluetoothDevice) -> NSMenu {
        let menu = NSMenu()

        let infoItem = NSMenuItem(title: "\(infoDevice.name) — \(infoDevice.batteryLevel)%", action: nil, keyEquivalent: "")
        infoItem.isEnabled = false
        menu.addItem(infoItem)
        menu.addItem(NSMenuItem.separator())

        appendDeviceToggles(to: menu, allDevices: allDevices)
        menu.addItem(NSMenuItem.separator())
        appendSettingsMenuItems(to: menu)

        return menu
    }

    private func buildSingleModeMenu(visibleDevices: [BluetoothDevice], allDevices: [BluetoothDevice]) -> NSMenu {
        let menu = NSMenu()

        let headerItem = NSMenuItem(title: "Devices", action: nil, keyEquivalent: "")
        headerItem.isEnabled = false
        menu.addItem(headerItem)

        let threshold = settingsStore?.lowBatteryThreshold ?? 10
        for device in visibleDevices.sorted(by: { $0.batteryLevel < $1.batteryLevel }) {
            let icon = device.deviceType.sfSymbolName
            let title = "\(device.name)   \(device.batteryLevel)%"
            let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            item.isEnabled = false
            if let symbolImage = NSImage(systemSymbolName: icon, accessibilityDescription: device.name) {
                let isLow = device.batteryLevel <= threshold
                var config = NSImage.SymbolConfiguration(pointSize: 14, weight: .medium)
                if isLow {
                    config = config.applying(NSImage.SymbolConfiguration(paletteColors: [.systemRed]))
                }
                item.image = symbolImage.withSymbolConfiguration(config) ?? symbolImage
            }
            menu.addItem(item)
        }

        menu.addItem(NSMenuItem.separator())
        appendDeviceToggles(to: menu, allDevices: allDevices)
        menu.addItem(NSMenuItem.separator())
        appendSettingsMenuItems(to: menu)

        return menu
    }

    private func appendDeviceToggles(to menu: NSMenu, allDevices: [BluetoothDevice]) {
        let headerItem = NSMenuItem(title: "Show Devices", action: nil, keyEquivalent: "")
        headerItem.isEnabled = false
        menu.addItem(headerItem)

        for device in allDevices {
            let title = "\(device.name)   \(device.batteryLevel)%"
            let toggleItem = NSMenuItem(title: title, action: #selector(AppDelegate.toggleDeviceVisibility(_:)), keyEquivalent: "")
            toggleItem.representedObject = device.id
            toggleItem.state = (settingsStore?.isHidden(device.id) == true) ? .off : .on
            menu.addItem(toggleItem)
        }
    }

    private func appendSettingsMenuItems(to menu: NSMenu) {
        let thresholdItem = NSMenuItem(title: "Low Battery Alert", action: nil, keyEquivalent: "")
        let thresholdMenu = NSMenu()
        let currentThreshold = settingsStore?.lowBatteryThreshold ?? 10
        for pct in [5, 10, 15, 20, 25] {
            let item = NSMenuItem(title: "\(pct)%", action: #selector(AppDelegate.setLowBatteryThreshold(_:)), keyEquivalent: "")
            item.tag = pct
            item.state = (pct == currentThreshold) ? .on : .off
            thresholdMenu.addItem(item)
        }
        thresholdItem.submenu = thresholdMenu
        menu.addItem(thresholdItem)

        let intervalItem = NSMenuItem(title: "Refresh Interval", action: nil, keyEquivalent: "")
        let intervalMenu = NSMenu()
        let currentInterval = settingsStore?.refreshInterval ?? 30
        for seconds in [10, 30, 60, 120] {
            let label = seconds < 60 ? "\(seconds)s" : "\(seconds / 60)m"
            let item = NSMenuItem(title: label, action: #selector(AppDelegate.setRefreshInterval(_:)), keyEquivalent: "")
            item.tag = seconds
            item.state = (seconds == currentInterval) ? .on : .off
            intervalMenu.addItem(item)
        }
        intervalItem.submenu = intervalMenu
        menu.addItem(intervalItem)

        let showPctItem = NSMenuItem(title: "Show Percentage", action: #selector(AppDelegate.toggleShowPercentage(_:)), keyEquivalent: "")
        showPctItem.state = (settingsStore?.showPercentage ?? true) ? .on : .off
        menu.addItem(showPctItem)

        let displayModeItem = NSMenuItem(title: "Display Mode", action: nil, keyEquivalent: "")
        let displayModeMenu = NSMenu()
        let currentMode = settingsStore?.displayMode ?? "separate"
        for (mode, label) in [("separate", "Separate Icons"), ("single", "Single Icon")] {
            let item = NSMenuItem(title: label, action: #selector(AppDelegate.setDisplayMode(_:)), keyEquivalent: "")
            item.representedObject = mode
            item.state = (mode == currentMode) ? .on : .off
            displayModeMenu.addItem(item)
        }
        displayModeItem.submenu = displayModeMenu
        menu.addItem(displayModeItem)

        menu.addItem(NSMenuItem.separator())

        let refreshItem = NSMenuItem(title: "Refresh", action: #selector(AppDelegate.refreshDevices), keyEquivalent: "r")
        menu.addItem(refreshItem)

        let loginItem = NSMenuItem(title: "Launch at Login", action: #selector(AppDelegate.toggleLaunchAtLogin(_:)), keyEquivalent: "")
        loginItem.state = (SMAppService.mainApp.status == .enabled) ? .on : .off
        menu.addItem(loginItem)

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: "Quit BatteryBar", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quitItem)
    }
}
