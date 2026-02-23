import Foundation

struct BluetoothDeviceInfo {
    let name: String
    var leftBattery: Int?
    var rightBattery: Int?
    var caseBattery: Int?
}

func buildBluetoothNameMap() -> [String: BluetoothDeviceInfo] {
    var map: [String: BluetoothDeviceInfo] = [:]
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
    var currentLeft: Int?
    var currentRight: Int?
    var currentCase: Int?

    for line in output.components(separatedBy: "\n") {
        let trimmed = line.trimmingCharacters(in: .whitespaces)

        if trimmed.hasSuffix(":") && !trimmed.hasPrefix("Address:") && !trimmed.hasPrefix("Bluetooth") &&
           !trimmed.hasPrefix("Connected:") && !trimmed.hasPrefix("Not Connected:") &&
           !trimmed.hasPrefix("Services:") && !trimmed.hasPrefix("Vendor ID:") &&
           !trimmed.hasPrefix("Product ID:") && !trimmed.hasPrefix("Firmware Version:") &&
           !trimmed.hasPrefix("Battery Level:") && !trimmed.hasPrefix("Paired:") &&
           !trimmed.hasPrefix("Favourite:") && !trimmed.hasPrefix("Major Type:") &&
           !trimmed.hasPrefix("Minor Type:") && !trimmed.hasPrefix("Transport:") &&
           !trimmed.hasPrefix("Left Battery Level:") && !trimmed.hasPrefix("Right Battery Level:") &&
           !trimmed.hasPrefix("Case Battery Level:") {
            let name = String(trimmed.dropLast())
            if !name.isEmpty && name.count > 2 {
                currentDeviceName = name
                currentLeft = nil
                currentRight = nil
                currentCase = nil
            }
        }

        if trimmed.hasPrefix("Left Battery Level:") {
            currentLeft = parseBatteryLevel(from: trimmed, prefix: "Left Battery Level:")
        }
        if trimmed.hasPrefix("Right Battery Level:") {
            currentRight = parseBatteryLevel(from: trimmed, prefix: "Right Battery Level:")
        }
        if trimmed.hasPrefix("Case Battery Level:") {
            currentCase = parseBatteryLevel(from: trimmed, prefix: "Case Battery Level:")
        }

        if trimmed.hasPrefix("Address:"), let deviceName = currentDeviceName {
            let address = trimmed.replacingOccurrences(of: "Address: ", with: "")
                .trimmingCharacters(in: .whitespaces)
                .lowercased()
                .replacingOccurrences(of: ":", with: "-")
            if !address.isEmpty {
                map[address] = BluetoothDeviceInfo(
                    name: deviceName,
                    leftBattery: currentLeft,
                    rightBattery: currentRight,
                    caseBattery: currentCase
                )
            }
        }
    }
    return map
}

private func parseBatteryLevel(from line: String, prefix: String) -> Int? {
    let value = line.replacingOccurrences(of: prefix, with: "")
        .trimmingCharacters(in: .whitespaces)
        .replacingOccurrences(of: "%", with: "")
    guard let level = Int(value) else { return nil }
    return max(0, min(100, level))
}
