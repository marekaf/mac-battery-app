import AppKit
import IOKit
import CoreBluetooth
import Combine
import ServiceManagement

// MARK: - Data Model

enum DeviceType {
    case keyboard, mouse, trackpad, headphones, unknown

    var sfSymbolName: String {
        switch self {
        case .keyboard: return "keyboard"
        case .mouse: return "computermouse"
        case .trackpad: return "rectangle.and.hand.point.up.left"
        case .headphones: return "headphones"
        case .unknown: return "wave.3.right.circle"
        }
    }
}

struct BluetoothDevice: Identifiable, Equatable {
    let id: String
    let name: String
    let batteryLevel: Int
    let deviceType: DeviceType

    static func == (lhs: BluetoothDevice, rhs: BluetoothDevice) -> Bool {
        lhs.id == rhs.id && lhs.name == rhs.name && lhs.batteryLevel == rhs.batteryLevel
    }
}

func sanitizeDeviceName(_ name: String) -> String {
    String(name.prefix(100)).filter { !$0.isNewline && !$0.isControl }
}

func detectDeviceType(from name: String) -> DeviceType {
    let lower = name.lowercased()
    if lower.contains("keyboard") { return .keyboard }
    if lower.contains("mouse") || lower.contains("mx master") || lower.contains("mx anywhere") { return .mouse }
    if lower.contains("trackpad") { return .trackpad }
    if lower.contains("airpods") || lower.contains("headphone") || lower.contains("beats") { return .headphones }
    return .unknown
}

// MARK: - System Profiler Address-to-Name Map

func buildBluetoothNameMap() -> [String: String] {
    var map: [String: String] = [:]
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/sbin/system_profiler")
    process.arguments = ["SPBluetoothDataType"]
    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = FileHandle.nullDevice

    do {
        try process.run()
        process.waitUntilExit()
    } catch {
        NSLog("Failed to run system_profiler: %@", error.localizedDescription)
        return map
    }

    if process.terminationStatus != 0 {
        NSLog("system_profiler exited with status %d", process.terminationStatus)
        return map
    }

    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    guard let output = String(data: data, encoding: .utf8) else { return map }

    var currentDeviceName: String?
    for line in output.components(separatedBy: "\n") {
        let trimmed = line.trimmingCharacters(in: .whitespaces)

        if trimmed.hasSuffix(":") && !trimmed.hasPrefix("Address:") && !trimmed.hasPrefix("Bluetooth") &&
           !trimmed.hasPrefix("Connected:") && !trimmed.hasPrefix("Not Connected:") &&
           !trimmed.hasPrefix("Services:") && !trimmed.hasPrefix("Vendor ID:") &&
           !trimmed.hasPrefix("Product ID:") && !trimmed.hasPrefix("Firmware Version:") &&
           !trimmed.hasPrefix("Battery Level:") && !trimmed.hasPrefix("Paired:") &&
           !trimmed.hasPrefix("Favourite:") && !trimmed.hasPrefix("Major Type:") &&
           !trimmed.hasPrefix("Minor Type:") && !trimmed.hasPrefix("Transport:") {
            let name = String(trimmed.dropLast())
            if !name.isEmpty && name.count > 2 {
                currentDeviceName = name
            }
        }

        if trimmed.hasPrefix("Address:"), let deviceName = currentDeviceName {
            let address = trimmed.replacingOccurrences(of: "Address: ", with: "")
                .trimmingCharacters(in: .whitespaces)
                .lowercased()
                .replacingOccurrences(of: ":", with: "-")
            if !address.isEmpty {
                map[address] = deviceName
            }
        }
    }
    return map
}

// MARK: - IOKit Battery Reader

func readIOKitBatteryDevices(nameMap: [String: String]) -> [BluetoothDevice] {
    var devices: [BluetoothDevice] = []
    var seen = Set<String>()

    let matching = IOServiceMatching("AppleDeviceManagementHIDEventService")
    var iterator: io_iterator_t = 0
    let result = IOServiceGetMatchingServices(kIOMainPortCompat, matching, &iterator)
    guard result == KERN_SUCCESS else { return devices }
    defer { IOObjectRelease(iterator) }

    var service = IOIteratorNext(iterator)
    while service != 0 {
        defer {
            IOObjectRelease(service)
            service = IOIteratorNext(iterator)
        }

        guard let props = getServiceProperties(service) else { continue }

        let isBluetooth = props["BluetoothDevice"] as? Bool ?? false
        guard isBluetooth else { continue }

        guard let rawBattery = props["BatteryPercent"] as? Int else { continue }
        let battery = max(0, min(100, rawBattery))

        let rawAddress = props["DeviceAddress"] as? String ?? ""
        let address = rawAddress.lowercased()
        guard !address.isEmpty else { continue }

        if seen.contains(address) { continue }
        seen.insert(address)

        var name = sanitizeDeviceName(props["Product"] as? String ?? "")

        if name.isEmpty {
            if let mappedName = nameMap[address], !mappedName.isEmpty {
                name = sanitizeDeviceName(mappedName)
            } else if let wakeReason = props["WakeReason"] as? String {
                name = parseDeviceTypeFromWakeReason(wakeReason)
            } else {
                name = "Bluetooth Device"
            }
        }

        let deviceType = detectDeviceType(from: name)
        devices.append(BluetoothDevice(id: address, name: name, batteryLevel: battery, deviceType: deviceType))
    }

    return devices
}

func getServiceProperties(_ service: io_object_t) -> [String: Any]? {
    var propsRef: Unmanaged<CFMutableDictionary>?
    let kr = IORegistryEntryCreateCFProperties(service, &propsRef, kCFAllocatorDefault, 0)
    guard kr == KERN_SUCCESS, let cfDict = propsRef else { return nil }
    let dict = cfDict.takeRetainedValue() as NSDictionary
    return dict as? [String: Any]
}

func parseDeviceTypeFromWakeReason(_ reason: String) -> String {
    let lower = reason.lowercased()
    if lower.contains("keyboard") { return "Keyboard" }
    if lower.contains("mouse") { return "Mouse" }
    if lower.contains("trackpad") { return "Trackpad" }
    return "Bluetooth Device"
}

let kIOMainPortCompat: mach_port_t = {
    if #available(macOS 12.0, *) {
        return kIOMainPortDefault
    } else {
        return 0 // kIOMasterPortDefault
    }
}()

// MARK: - CoreBluetooth BLE Battery Reader

let batteryServiceUUID = CBUUID(string: "180F")
let batteryLevelCharUUID = CBUUID(string: "2A19")

class BLEBatteryReader: NSObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    private var centralManager: CBCentralManager!
    private var discoveredPeripherals: [CBPeripheral] = []
    private var peripheralBatteryLevels: [UUID: Int] = [:]
    private var peripheralNames: [UUID: String] = [:]
    var onDevicesUpdated: (([BluetoothDevice]) -> Void)?

    override init() {
        super.init()
        centralManager = CBCentralManager(delegate: self, queue: nil)
    }

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if central.state == .poweredOn {
            scanForConnectedPeripherals()
        }
    }

    func scanForConnectedPeripherals() {
        guard centralManager.state == .poweredOn else { return }
        let connected = centralManager.retrieveConnectedPeripherals(withServices: [batteryServiceUUID])
        for peripheral in connected {
            if !discoveredPeripherals.contains(where: { $0.identifier == peripheral.identifier }) {
                discoveredPeripherals.append(peripheral)
                peripheral.delegate = self
                peripheralNames[peripheral.identifier] = sanitizeDeviceName(peripheral.name ?? "BLE Device")
                centralManager.connect(peripheral, options: nil)
            }
        }
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        peripheral.discoverServices([batteryServiceUUID])
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        peripheralBatteryLevels.removeValue(forKey: peripheral.identifier)
        discoveredPeripherals.removeAll { $0.identifier == peripheral.identifier }
        notifyDevicesUpdated()
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
            self?.scanForConnectedPeripherals()
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard let services = peripheral.services else { return }
        for service in services where service.uuid == batteryServiceUUID {
            peripheral.discoverCharacteristics([batteryLevelCharUUID], for: service)
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard let chars = service.characteristics else { return }
        for char in chars where char.uuid == batteryLevelCharUUID {
            peripheral.readValue(for: char)
            peripheral.setNotifyValue(true, for: char)
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard characteristic.uuid == batteryLevelCharUUID,
              let data = characteristic.value,
              !data.isEmpty else { return }
        let level = max(0, min(100, Int(data[0])))
        peripheralBatteryLevels[peripheral.identifier] = level
        if let name = peripheral.name, !name.isEmpty {
            peripheralNames[peripheral.identifier] = sanitizeDeviceName(name)
        }
        notifyDevicesUpdated()
    }

    private func notifyDevicesUpdated() {
        let devices = peripheralBatteryLevels.compactMap { (id, level) -> BluetoothDevice? in
            let name = peripheralNames[id] ?? "BLE Device"
            return BluetoothDevice(
                id: "ble-\(id.uuidString)",
                name: name,
                batteryLevel: level,
                deviceType: detectDeviceType(from: name)
            )
        }
        onDevicesUpdated?(devices)
    }

    func currentDevices() -> [BluetoothDevice] {
        peripheralBatteryLevels.compactMap { (id, level) -> BluetoothDevice? in
            let name = peripheralNames[id] ?? "BLE Device"
            return BluetoothDevice(
                id: "ble-\(id.uuidString)",
                name: name,
                batteryLevel: level,
                deviceType: detectDeviceType(from: name)
            )
        }
    }
}

// MARK: - Device Manager

class DeviceManager {
    private var timer: Timer?
    private let bleReader = BLEBatteryReader()
    private var nameMap: [String: String] = [:]
    private(set) var devices: [BluetoothDevice] = []
    var onDevicesChanged: (([BluetoothDevice]) -> Void)?

    private var bleDevices: [BluetoothDevice] = []

    deinit {
        timer?.invalidate()
        bleReader.onDevicesUpdated = nil
    }

    init() {
        nameMap = buildBluetoothNameMap()

        bleReader.onDevicesUpdated = { [weak self] devices in
            guard let self = self else { return }
            self.bleDevices = devices
            self.mergeAndNotify()
        }

        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            self?.refresh()
        }
    }

    func refresh() {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let map = buildBluetoothNameMap()
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.nameMap = map
                self.bleReader.scanForConnectedPeripherals()
                self.mergeAndNotify()
            }
        }
    }

    private func mergeAndNotify() {
        let iokitDevices = readIOKitBatteryDevices(nameMap: nameMap)

        var merged: [BluetoothDevice] = iokitDevices
        let iokitIDs = Set(iokitDevices.map { $0.id })

        for bleDevice in bleDevices {
            if !iokitIDs.contains(bleDevice.id) {
                merged.append(bleDevice)
            }
        }

        merged.sort { $0.name < $1.name }

        if merged != devices {
            devices = merged
            onDevicesChanged?(devices)
        }
    }
}

// MARK: - Settings Store

class SettingsStore {
    private let hiddenKey = "hiddenDeviceIDs"

    private(set) var hiddenDeviceIDs: Set<String> {
        didSet {
            UserDefaults.standard.set(Array(hiddenDeviceIDs), forKey: hiddenKey)
        }
    }

    init() {
        let stored = UserDefaults.standard.stringArray(forKey: hiddenKey) ?? []
        hiddenDeviceIDs = Set(stored)
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

// MARK: - Status Bar Controller

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

        if let symbolImage = NSImage(systemSymbolName: device.deviceType.sfSymbolName, accessibilityDescription: nil) {
            let config = NSImage.SymbolConfiguration(pointSize: 12, weight: .medium)
            let configured = symbolImage.withSymbolConfiguration(config) ?? symbolImage
            let attachment = NSTextAttachment()
            attachment.image = configured
            attributed.append(NSAttributedString(attachment: attachment))
        }

        let color: NSColor = device.batteryLevel <= 10 ? .systemRed : .headerTextColor
        let text = " \(device.batteryLevel)%"
        let textAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .regular),
            .foregroundColor: color,
            .baselineOffset: 1 as NSNumber
        ]
        attributed.append(NSAttributedString(string: text, attributes: textAttrs))

        if device.batteryLevel <= 10 {
            button.image?.isTemplate = false
            if let symbolImage = NSImage(systemSymbolName: device.deviceType.sfSymbolName, accessibilityDescription: nil) {
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

// MARK: - App Delegate

class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusBarController: StatusBarController!
    private var deviceManager: DeviceManager!
    private var settingsStore: SettingsStore!

    func applicationDidFinishLaunching(_ notification: Notification) {
        settingsStore = SettingsStore()
        statusBarController = StatusBarController()
        statusBarController.settingsStore = settingsStore
        deviceManager = DeviceManager()

        deviceManager.onDevicesChanged = { [weak self] devices in
            self?.statusBarController.update(devices: devices)
        }

        statusBarController.update(devices: deviceManager.devices)
    }

    @objc func refreshDevices() {
        deviceManager.refresh()
    }

    @objc func toggleDeviceVisibility(_ sender: NSMenuItem) {
        guard let deviceID = sender.representedObject as? String else { return }
        settingsStore.toggleVisibility(deviceID)
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.statusBarController.update(devices: self.statusBarController.allDevices)
        }
    }

    @objc func toggleLaunchAtLogin(_ sender: NSMenuItem) {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            NSLog("Failed to toggle launch at login: %@", error.localizedDescription)
        }
    }
}

// MARK: - Entry Point

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let delegate = AppDelegate()
app.delegate = delegate
app.run()
