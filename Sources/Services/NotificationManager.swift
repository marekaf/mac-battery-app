import Foundation
import UserNotifications

class NotificationManager: NSObject, UNUserNotificationCenterDelegate {
    private var notifiedDeviceIDs: Set<String> = []

    override init() {
        super.init()
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        center.requestAuthorization(options: [.alert, .sound]) { _, error in
            if let error = error {
                NSLog("Notification authorization error: %@", error.localizedDescription)
            }
        }
    }

    func checkAndNotify(devices: [BluetoothDevice], threshold: Int) {
        for device in devices {
            if device.batteryLevel <= threshold {
                if !notifiedDeviceIDs.contains(device.id) {
                    notifiedDeviceIDs.insert(device.id)
                    sendNotification(for: device)
                }
            } else {
                notifiedDeviceIDs.remove(device.id)
            }
        }
    }

    private func sendNotification(for device: BluetoothDevice) {
        let content = UNMutableNotificationContent()
        content.title = "Low Battery: \(device.name)"
        var body = "\(device.name) is at \(device.batteryLevel)%."
        if let compText = device.componentBatteryText {
            body += " \(compText)"
        }
        content.body = body
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "battery-low-\(device.id)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                NSLog("Failed to send notification: %@", error.localizedDescription)
            }
        }
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }
}
