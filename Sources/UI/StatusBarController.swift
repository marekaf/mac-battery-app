import AppKit
import ServiceManagement

class StatusBarController {
    private var statusItems: [String: NSStatusItem] = [:]
    private var anchorItem: NSStatusItem?
    var settingsStore: SettingsStore?
    var allDevices: [BluetoothDevice] = []

    func update(devices: [BluetoothDevice]) {
        allDevices = devices
        guard let store = settingsStore else { return }

        let visibleDevices = devices.filter { !store.isHidden($0.id) }

        if visibleDevices.isEmpty && !devices.isEmpty {
            for (_, item) in statusItems {
                NSStatusBar.system.removeStatusItem(item)
            }
            statusItems.removeAll()
            showAnchorItem(allDevices: devices)
            return
        }

        removeAnchorItem()

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
            configureStatusItem(item, for: device, allDevices: devices)
        }
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

        item.menu = buildDeviceToggleMenu(allDevices: allDevices, infoDevice: nil)
    }

    private func removeAnchorItem() {
        if let item = anchorItem {
            NSStatusBar.system.removeStatusItem(item)
            anchorItem = nil
        }
    }

    private func configureStatusItem(_ item: NSStatusItem, for device: BluetoothDevice, allDevices: [BluetoothDevice]) {
        guard let button = item.button else { return }

        let attributed = NSMutableAttributedString()

        let a11yDescription = "\(device.name) battery"
        if let symbolImage = NSImage(systemSymbolName: device.deviceType.sfSymbolName, accessibilityDescription: a11yDescription) {
            let config = NSImage.SymbolConfiguration(pointSize: 12, weight: .medium)
            let configured = symbolImage.withSymbolConfiguration(config) ?? symbolImage
            let attachment = NSTextAttachment()
            attachment.image = configured
            attributed.append(NSAttributedString(attachment: attachment))
        }

        let threshold = settingsStore?.lowBatteryThreshold ?? 10
        let color: NSColor = device.batteryLevel <= threshold ? .systemRed : .headerTextColor
        let text = " \(device.batteryLevel)%"
        let textAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .regular),
            .foregroundColor: color,
            .baselineOffset: 1 as NSNumber
        ]
        attributed.append(NSAttributedString(string: text, attributes: textAttrs))

        if device.batteryLevel <= threshold {
            button.image?.isTemplate = false
            if let symbolImage = NSImage(systemSymbolName: device.deviceType.sfSymbolName, accessibilityDescription: a11yDescription) {
                let config = NSImage.SymbolConfiguration(pointSize: 12, weight: .medium)
                    .applying(NSImage.SymbolConfiguration(paletteColors: [.systemRed]))
                let configured = symbolImage.withSymbolConfiguration(config) ?? symbolImage
                let attachment = NSTextAttachment()
                attachment.image = configured
                let redAttributed = NSMutableAttributedString()
                redAttributed.append(NSAttributedString(attachment: attachment))
                redAttributed.append(NSAttributedString(string: text, attributes: textAttrs))
                button.attributedTitle = redAttributed
            } else {
                button.attributedTitle = attributed
            }
        } else {
            button.attributedTitle = attributed
        }

        button.toolTip = "\(device.name): \(device.batteryLevel)%"

        item.menu = buildDeviceToggleMenu(allDevices: allDevices, infoDevice: device)
    }

    private func buildDeviceToggleMenu(allDevices: [BluetoothDevice], infoDevice: BluetoothDevice?) -> NSMenu {
        let menu = NSMenu()

        if let device = infoDevice {
            let infoItem = NSMenuItem(title: "\(device.name) — \(device.batteryLevel)%", action: nil, keyEquivalent: "")
            infoItem.isEnabled = false
            menu.addItem(infoItem)
            menu.addItem(NSMenuItem.separator())
        }

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

        menu.addItem(NSMenuItem.separator())

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

        menu.addItem(NSMenuItem.separator())

        let refreshItem = NSMenuItem(title: "Refresh", action: #selector(AppDelegate.refreshDevices), keyEquivalent: "r")
        menu.addItem(refreshItem)

        let loginItem = NSMenuItem(title: "Launch at Login", action: #selector(AppDelegate.toggleLaunchAtLogin(_:)), keyEquivalent: "")
        loginItem.state = (SMAppService.mainApp.status == .enabled) ? .on : .off
        menu.addItem(loginItem)

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: "Quit BatteryBar", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quitItem)

        return menu
    }
}
