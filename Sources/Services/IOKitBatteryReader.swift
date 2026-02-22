import Foundation
import IOKit

let kIOMainPortCompat: mach_port_t = {
    if #available(macOS 12.0, *) {
        return kIOMainPortDefault
    } else {
        return 0 // kIOMasterPortDefault
    }
}()

func readIOKitBatteryDevices(nameMap: [String: BluetoothDeviceInfo]) -> [BluetoothDevice] {
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
        let info = nameMap[address]

        if name.isEmpty {
            if let mappedName = info?.name, !mappedName.isEmpty {
                name = sanitizeDeviceName(mappedName)
            } else if let wakeReason = props["WakeReason"] as? String {
                name = parseDeviceTypeFromWakeReason(wakeReason)
            } else {
                name = "Bluetooth Device"
            }
        }

        let deviceType = detectDeviceType(from: name)
        devices.append(BluetoothDevice(
            id: address, name: name, batteryLevel: battery, deviceType: deviceType,
            leftBattery: info?.leftBattery, rightBattery: info?.rightBattery, caseBattery: info?.caseBattery
        ))
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
