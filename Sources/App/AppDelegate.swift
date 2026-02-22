import AppKit
import ServiceManagement

class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusBarController: StatusBarController!
    private var deviceManager: DeviceManager!
    private var settingsStore: SettingsStore!
    private var notificationManager: NotificationManager!

    func applicationDidFinishLaunching(_ notification: Notification) {
        let store = SettingsStore()
        let controller = StatusBarController()
        controller.settingsStore = store
        settingsStore = store
        statusBarController = controller
        deviceManager = DeviceManager(refreshInterval: store.refreshInterval)
        notificationManager = NotificationManager()

        deviceManager.onDevicesChanged = { [weak self] devices in
            guard let self = self else { return }
            self.statusBarController.update(devices: devices)
            self.notificationManager.checkAndNotify(devices: devices, threshold: self.settingsStore.lowBatteryThreshold)
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

    @objc func toggleShowPercentage(_ sender: NSMenuItem) {
        settingsStore.setShowPercentage(!(settingsStore.showPercentage))
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
