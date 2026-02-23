import AppKit
import ServiceManagement

private let statusBarFontSize: CGFloat = 12
private let menuIconSize: CGFloat = 14
private let baselineOffset: CGFloat = 1
private class StackedStatusView: NSView {
    private var iconName: String = "battery.100percent"
    private var percentage: String = "100%"
    private var iconColor: NSColor = .headerTextColor
    private var textColor: NSColor = .headerTextColor
    private let font = NSFont.monospacedDigitSystemFont(ofSize: 9, weight: .medium)

    override var intrinsicContentSize: NSSize {
        let textSize = (percentage as NSString).size(withAttributes: [.font: font])
        let iconConfig = NSImage.SymbolConfiguration(pointSize: 9, weight: .medium)
        let iconWidth: CGFloat
        if let img = NSImage(systemSymbolName: iconName, accessibilityDescription: nil)?
            .withSymbolConfiguration(iconConfig) {
            iconWidth = img.size.width
        } else {
            iconWidth = 12
        }
        let width = max(textSize.width, iconWidth) + 4
        return NSSize(width: width, height: 22)
    }

    func update(icon: String, text: String, isLow: Bool) {
        iconName = icon
        percentage = text
        let color: NSColor = isLow ? .systemRed : .headerTextColor
        iconColor = color
        textColor = color
        invalidateIntrinsicContentSize()
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        let bounds = self.bounds
        let halfHeight = bounds.height / 2

        let iconConfig = NSImage.SymbolConfiguration(pointSize: 9, weight: .medium)
        if let symbolImage = NSImage(systemSymbolName: iconName, accessibilityDescription: nil) {
            var config = iconConfig
            config = config.applying(NSImage.SymbolConfiguration(paletteColors: [iconColor]))
            let configured = symbolImage.withSymbolConfiguration(config) ?? symbolImage
            let imgSize = configured.size
            let iconX = (bounds.width - imgSize.width) / 2
            let iconY = halfHeight + (halfHeight - imgSize.height) / 2
            configured.draw(in: NSRect(x: iconX, y: iconY, width: imgSize.width, height: imgSize.height))
        }

        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: textColor
        ]
        let textSize = (percentage as NSString).size(withAttributes: attrs)
        let textX = (bounds.width - textSize.width) / 2
        let textY = (halfHeight - textSize.height) / 2
        (percentage as NSString).draw(at: NSPoint(x: textX, y: textY), withAttributes: attrs)
    }

    override func mouseDown(with event: NSEvent) {
        super.mouseDown(with: event)
    }
}

class StatusBarController {
    private var statusItems: [String: NSStatusItem] = [:]
    private var anchorItem: NSStatusItem?
    private var singleItem: NSStatusItem?
    var settingsStore: SettingsStore?
    var batteryHistoryStore: BatteryHistoryStore?
    var allDevices: [BluetoothDevice] = []

    private func displayName(_ device: BluetoothDevice) -> String {
        settingsStore?.displayName(for: device) ?? device.name
    }

    private func deviceIcon(_ device: BluetoothDevice) -> String {
        settingsStore?.iconName(for: device) ?? device.deviceType.sfSymbolName
    }

    private func makeIconAttachment(symbolName: String, isLow: Bool, accessibilityDescription: String) -> NSTextAttachment? {
        guard let symbolImage = NSImage(systemSymbolName: symbolName, accessibilityDescription: accessibilityDescription) else { return nil }
        var config = NSImage.SymbolConfiguration(pointSize: statusBarFontSize, weight: .medium)
        if isLow {
            config = config.applying(NSImage.SymbolConfiguration(paletteColors: [.systemRed]))
        }
        let configured = symbolImage.withSymbolConfiguration(config) ?? symbolImage
        let attachment = NSTextAttachment()
        attachment.image = configured
        return attachment
    }

    private func sortByUserOrder(_ devices: [BluetoothDevice]) -> [BluetoothDevice] {
        guard let store = settingsStore else { return devices }
        let order = store.deviceOrder
        if order.isEmpty { return devices }
        let orderMap = Dictionary(uniqueKeysWithValues: order.enumerated().map { ($1, $0) })
        return devices.sorted { a, b in
            let posA = orderMap[a.id] ?? Int.max
            let posB = orderMap[b.id] ?? Int.max
            if posA == posB { return a.name < b.name }
            return posA < posB
        }
    }

    func update(devices: [BluetoothDevice]) {
        guard let store = settingsStore else { return }

        let knownIDs = Set(store.deviceOrder)
        let newIDs = devices.map { $0.id }.filter { !knownIDs.contains($0) }
        if !newIDs.isEmpty {
            store.setDeviceOrder(store.deviceOrder + newIDs)
        }

        allDevices = sortByUserOrder(devices)
        let visibleDevices = allDevices.filter { !store.isHidden($0.id) }

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
        let stacked = settingsStore?.isStackedMode ?? false

        for id in existingIDs.subtracting(visibleIDs) {
            if let item = statusItems.removeValue(forKey: id) {
                NSStatusBar.system.removeStatusItem(item)
            }
        }

        for device in visibleDevices {
            let item = statusItems[device.id] ?? createStatusItem()
            statusItems[device.id] = item
            if stacked {
                configureStackedAppearance(item, for: device)
            } else {
                removeStackedView(from: item)
                configureStatusItemAppearance(item, for: device)
            }
            item.menu = buildSeparateModeMenu(allDevices: allDevices, infoDevice: device)
        }
    }

    private func updateSingleMode(visibleDevices: [BluetoothDevice], allDevices: [BluetoothDevice]) {
        guard !visibleDevices.isEmpty else {
            removeSingleItem()
            return
        }

        if singleItem == nil {
            singleItem = createStatusItem()
        }
        guard let item = singleItem, let button = item.button else { return }

        let threshold = settingsStore?.lowBatteryThreshold ?? 10
        let isCompact = settingsStore?.isCompactMode ?? false
        let attributed = NSMutableAttributedString()

        for (index, device) in visibleDevices.enumerated() {
            let isLow = device.batteryLevel <= threshold
            let color: NSColor = isLow ? .systemRed : .headerTextColor

            if !isCompact {
                let devName = displayName(device)
                if let attachment = makeIconAttachment(symbolName: deviceIcon(device), isLow: isLow, accessibilityDescription: devName) {
                    attributed.append(NSAttributedString(attachment: attachment))
                }
            }

            let textAttrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.monospacedDigitSystemFont(ofSize: statusBarFontSize, weight: .regular),
                .foregroundColor: color,
                .baselineOffset: baselineOffset as NSNumber
            ]
            let prefix = isCompact ? "" : " "
            attributed.append(NSAttributedString(string: "\(prefix)\(device.batteryLevel)%", attributes: textAttrs))

            if index < visibleDevices.count - 1 {
                attributed.append(NSAttributedString(string: isCompact ? " " : "  "))
            }
        }

        button.attributedTitle = attributed
        let tooltipLines = visibleDevices.map { [weak self] device in
            let name = self?.displayName(device) ?? device.name
            if let compText = device.componentBatteryText {
                return "\(name): \(compText)"
            }
            return "\(name): \(device.batteryLevel)%"
        }
        button.toolTip = tooltipLines.joined(separator: "\n")
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
            let config = NSImage.SymbolConfiguration(pointSize: menuIconSize, weight: .medium)
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

    private func configureStackedAppearance(_ item: NSStatusItem, for device: BluetoothDevice) {
        guard let button = item.button else { return }

        let threshold = settingsStore?.lowBatteryThreshold ?? 10
        let isLow = device.batteryLevel <= threshold
        let devName = displayName(device)

        button.attributedTitle = NSAttributedString(string: "")
        button.image = nil

        let stackedView: StackedStatusView
        if let existing = button.subviews.first(where: { $0 is StackedStatusView }) as? StackedStatusView {
            stackedView = existing
        } else {
            stackedView = StackedStatusView()
            stackedView.translatesAutoresizingMaskIntoConstraints = false
            button.addSubview(stackedView)
            NSLayoutConstraint.activate([
                stackedView.centerYAnchor.constraint(equalTo: button.centerYAnchor),
                stackedView.leadingAnchor.constraint(equalTo: button.leadingAnchor),
                stackedView.trailingAnchor.constraint(equalTo: button.trailingAnchor),
                stackedView.heightAnchor.constraint(equalToConstant: 22),
            ])
        }

        stackedView.update(icon: deviceIcon(device), text: "\(device.batteryLevel)%", isLow: isLow)

        if let compText = device.componentBatteryText {
            button.toolTip = "\(devName): \(compText)"
        } else {
            button.toolTip = "\(devName): \(device.batteryLevel)%"
        }
    }

    private func removeStackedView(from item: NSStatusItem) {
        guard let button = item.button else { return }
        button.subviews.filter { $0 is StackedStatusView }.forEach { $0.removeFromSuperview() }
    }

    private func configureStatusItemAppearance(_ item: NSStatusItem, for device: BluetoothDevice) {
        guard let button = item.button else { return }

        let threshold = settingsStore?.lowBatteryThreshold ?? 10
        let isLow = device.batteryLevel <= threshold
        let color: NSColor = isLow ? .systemRed : .headerTextColor
        let devName = displayName(device)
        let a11yDescription = "\(devName) battery"

        let textAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: statusBarFontSize, weight: .regular),
            .foregroundColor: color,
            .baselineOffset: baselineOffset as NSNumber
        ]

        let attributed = NSMutableAttributedString()

        if isLow {
            button.image?.isTemplate = false
        }
        if let attachment = makeIconAttachment(symbolName: deviceIcon(device), isLow: isLow, accessibilityDescription: a11yDescription) {
            attributed.append(NSAttributedString(attachment: attachment))
        }

        attributed.append(NSAttributedString(string: " \(device.batteryLevel)%", attributes: textAttrs))

        button.attributedTitle = attributed
        if let compText = device.componentBatteryText {
            button.toolTip = "\(devName): \(compText)"
        } else {
            button.toolTip = "\(devName): \(device.batteryLevel)%"
        }
    }

    private func buildSeparateModeMenu(allDevices: [BluetoothDevice], infoDevice: BluetoothDevice) -> NSMenu {
        let menu = NSMenu()

        let infoName = displayName(infoDevice)
        let infoTitle: String
        if let compText = infoDevice.componentBatteryText {
            infoTitle = "\(infoName) — \(compText)"
        } else {
            infoTitle = "\(infoName) — \(infoDevice.batteryLevel)%"
        }
        let infoItem = NSMenuItem(title: infoTitle, action: nil, keyEquivalent: "")
        infoItem.isEnabled = false
        menu.addItem(infoItem)
        appendTimeEstimate(to: menu, deviceID: infoDevice.id)
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
            let devName = displayName(device)
            let icon = deviceIcon(device)
            let batteryDisplay = device.componentBatteryText ?? "\(device.batteryLevel)%"
            let title = "\(devName)   \(batteryDisplay)"
            let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            item.isEnabled = false
            if let symbolImage = NSImage(systemSymbolName: icon, accessibilityDescription: devName) {
                let isLow = device.batteryLevel <= threshold
                var config = NSImage.SymbolConfiguration(pointSize: menuIconSize, weight: .medium)
                if isLow {
                    config = config.applying(NSImage.SymbolConfiguration(paletteColors: [.systemRed]))
                }
                item.image = symbolImage.withSymbolConfiguration(config) ?? symbolImage
            }
            menu.addItem(item)
            appendTimeEstimate(to: menu, deviceID: device.id)
        }

        menu.addItem(NSMenuItem.separator())
        appendDeviceToggles(to: menu, allDevices: allDevices)
        menu.addItem(NSMenuItem.separator())
        appendSettingsMenuItems(to: menu)

        return menu
    }

    private func appendDeviceToggles(to menu: NSMenu, allDevices: [BluetoothDevice]) {
        let headerItem = NSMenuItem(title: "Devices", action: nil, keyEquivalent: "")
        headerItem.isEnabled = false
        menu.addItem(headerItem)

        for (index, device) in allDevices.enumerated() {
            let title = displayName(device)
            let deviceItem = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            deviceItem.state = (settingsStore?.isHidden(device.id) == true) ? .off : .on

            let subMenu = NSMenu()

            let toggleLabel = (settingsStore?.isHidden(device.id) == true) ? "Show" : "Hide"
            let toggleItem = NSMenuItem(title: toggleLabel, action: #selector(AppDelegate.toggleDeviceVisibility(_:)), keyEquivalent: "")
            toggleItem.representedObject = device.id
            subMenu.addItem(toggleItem)

            subMenu.addItem(NSMenuItem.separator())

            if index > 0 {
                let moveUp = NSMenuItem(title: "Move Up", action: #selector(AppDelegate.moveDeviceUp(_:)), keyEquivalent: "")
                moveUp.representedObject = device.id
                subMenu.addItem(moveUp)
            }
            if index < allDevices.count - 1 {
                let moveDown = NSMenuItem(title: "Move Down", action: #selector(AppDelegate.moveDeviceDown(_:)), keyEquivalent: "")
                moveDown.representedObject = device.id
                subMenu.addItem(moveDown)
            }

            subMenu.addItem(NSMenuItem.separator())

            let iconItem = NSMenuItem(title: "Icon", action: nil, keyEquivalent: "")
            let iconMenu = NSMenu()
            let currentIcon = settingsStore?.customDeviceIcons[device.id]
            let iconChoices: [(String, String?)] = [
                ("Auto", nil),
                ("Keyboard", "keyboard"),
                ("Mouse", "computermouse"),
                ("Trackpad", "rectangle.and.hand.point.up.left"),
                ("Headphones", "headphones"),
                ("Speaker", "speaker.wave.2.fill"),
                ("Controller", "gamecontroller.fill"),
                ("Watch", "applewatch"),
                ("Phone", "iphone"),
                ("Pencil", "pencil"),
                ("Generic", "wave.3.right.circle"),
            ]
            for (label, sfName) in iconChoices {
                let choice = NSMenuItem(title: label, action: #selector(AppDelegate.setDeviceIcon(_:)), keyEquivalent: "")
                if let sfName = sfName {
                    choice.representedObject = [device.id, sfName]
                    choice.state = (currentIcon == sfName) ? .on : .off
                    if let img = NSImage(systemSymbolName: sfName, accessibilityDescription: label) {
                        let cfg = NSImage.SymbolConfiguration(pointSize: menuIconSize, weight: .medium)
                        choice.image = img.withSymbolConfiguration(cfg) ?? img
                    }
                } else {
                    choice.representedObject = [device.id]
                    choice.state = (currentIcon == nil) ? .on : .off
                }
                iconMenu.addItem(choice)
            }
            iconItem.submenu = iconMenu
            subMenu.addItem(iconItem)

            subMenu.addItem(NSMenuItem.separator())

            let renameItem = NSMenuItem(title: "Rename...", action: #selector(AppDelegate.renameDevice(_:)), keyEquivalent: "")
            renameItem.representedObject = device.id
            subMenu.addItem(renameItem)

            deviceItem.submenu = subMenu
            menu.addItem(deviceItem)
        }
    }

    private func appendTimeEstimate(to menu: NSMenu, deviceID: String) {
        guard let estimate = batteryHistoryStore?.estimatedTimeRemaining(for: deviceID) else { return }
        let item = NSMenuItem(title: estimate, action: nil, keyEquivalent: "")
        item.isEnabled = false
        menu.addItem(item)
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

        let displayModeItem = NSMenuItem(title: "Display Mode", action: nil, keyEquivalent: "")
        let displayModeMenu = NSMenu()
        let currentMode = settingsStore?.displayMode ?? "separate"
        for (mode, label) in [("separate", "Separate Icons"), ("stacked", "Stacked"), ("single", "Combined Icon"), ("compact", "Percentages Only")] {
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
