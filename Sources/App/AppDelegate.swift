import AppKit
import ServiceManagement

class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusBarController: StatusBarController!
    private var deviceManager: DeviceManager!
    private var settingsStore: SettingsStore!

    func applicationDidFinishLaunching(_ notification: Notification) {
        let store = SettingsStore()
        let controller = StatusBarController()
        controller.settingsStore = store
        settingsStore = store
        statusBarController = controller
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
