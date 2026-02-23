import AppKit
import ServiceManagement

class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusBarController: StatusBarController!
    private var deviceManager: DeviceManager!
    private var settingsStore: SettingsStore!
    private var notificationManager: NotificationManager!
    private var batteryHistoryStore: BatteryHistoryStore!

    func applicationDidFinishLaunching(_ notification: Notification) {
        let store = SettingsStore()
        let controller = StatusBarController()
        controller.settingsStore = store
        settingsStore = store
        statusBarController = controller
        deviceManager = DeviceManager(refreshInterval: store.refreshInterval)
        notificationManager = NotificationManager()
        batteryHistoryStore = BatteryHistoryStore()
        controller.batteryHistoryStore = batteryHistoryStore

        deviceManager.onDevicesChanged = { [weak self] devices in
            guard let self = self else { return }
            for device in devices {
                self.batteryHistoryStore.record(deviceID: device.id, level: device.batteryLevel)
            }
            self.statusBarController.update(devices: devices)
            self.notificationManager.checkAndNotify(
                devices: devices, threshold: self.settingsStore.lowBatteryThreshold,
                nameResolver: { self.settingsStore.displayName(for: $0) })
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

    @objc func setLowBatteryThreshold(_ sender: NSMenuItem) {
        settingsStore.setLowBatteryThreshold(sender.tag)
        statusBarController.update(devices: statusBarController.allDevices)
    }

    @objc func setRefreshInterval(_ sender: NSMenuItem) {
        settingsStore.setRefreshInterval(sender.tag)
        deviceManager.updateRefreshInterval(sender.tag)
        statusBarController.update(devices: statusBarController.allDevices)
    }

    @objc func setDisplayMode(_ sender: NSMenuItem) {
        guard let mode = sender.representedObject as? String else { return }
        settingsStore.setDisplayMode(mode)
        statusBarController.update(devices: statusBarController.allDevices)
    }

    @objc func moveDeviceUp(_ sender: NSMenuItem) {
        guard let deviceID = sender.representedObject as? String else { return }
        settingsStore.moveDevice(deviceID, direction: -1)
        statusBarController.update(devices: statusBarController.allDevices)
    }

    @objc func moveDeviceDown(_ sender: NSMenuItem) {
        guard let deviceID = sender.representedObject as? String else { return }
        settingsStore.moveDevice(deviceID, direction: 1)
        statusBarController.update(devices: statusBarController.allDevices)
    }

    @objc func renameDevice(_ sender: NSMenuItem) {
        guard let deviceID = sender.representedObject as? String else { return }
        let currentName = settingsStore.customDeviceNames[deviceID]
            ?? statusBarController.allDevices.first(where: { $0.id == deviceID })?.name ?? ""

        let alert = NSAlert()
        alert.messageText = "Rename Device"
        alert.informativeText = "Enter a new name (leave empty to reset):"
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")

        let input = NSTextField(frame: NSRect(x: 0, y: 0, width: 250, height: 24))
        input.stringValue = currentName
        alert.accessoryView = input
        alert.window.initialFirstResponder = input

        NSApp.activate(ignoringOtherApps: true)
        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            let newName = input.stringValue.trimmingCharacters(in: .whitespaces)
            settingsStore.setCustomName(newName.isEmpty ? nil : newName, for: deviceID)
            statusBarController.update(devices: statusBarController.allDevices)
        }
    }

    @objc func setDeviceIcon(_ sender: NSMenuItem) {
        guard let info = sender.representedObject as? [String] else { return }
        let deviceID = info[0]
        let icon: String? = info.count > 1 ? info[1] : nil
        settingsStore.setCustomIcon(icon, for: deviceID)
        statusBarController.update(devices: statusBarController.allDevices)
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
