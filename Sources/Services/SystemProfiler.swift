import Foundation

struct BluetoothDeviceInfo {
    let name: String
    var batteryLevel: Int?
    var leftBattery: Int?
    var rightBattery: Int?
    var caseBattery: Int?
    var minorType: String?
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

    struct PendingDevice {
        var name: String
        var address: String?
        var batteryLevel: Int?
        var leftBattery: Int?
        var rightBattery: Int?
        var caseBattery: Int?
        var minorType: String?
    }

    var current: PendingDevice?

    func flushDevice(_ device: PendingDevice?, into map: inout [String: BluetoothDeviceInfo]) {
        guard let dev = device, let address = dev.address, !address.isEmpty else { return }
        let info = BluetoothDeviceInfo(
            name: dev.name,
            batteryLevel: dev.batteryLevel,
            leftBattery: dev.leftBattery,
            rightBattery: dev.rightBattery,
            caseBattery: dev.caseBattery,
            minorType: dev.minorType
        )
        if let existing = map[address] {
            map[address] = BluetoothDeviceInfo(
                name: existing.name,
                batteryLevel: existing.batteryLevel ?? info.batteryLevel,
                leftBattery: existing.leftBattery ?? info.leftBattery,
                rightBattery: existing.rightBattery ?? info.rightBattery,
                caseBattery: existing.caseBattery ?? info.caseBattery,
                minorType: existing.minorType ?? info.minorType
            )
        } else {
            map[address] = info
        }
    }

    for line in output.components(separatedBy: "\n") {
        let trimmed = line.trimmingCharacters(in: .whitespaces)

        let leadingSpaces = line.prefix(while: { $0 == " " }).count
        if trimmed.hasSuffix(":") && leadingSpaces == 8 {
            let name = String(trimmed.dropLast())
            if !name.isEmpty && name.count > 2 {
                flushDevice(current, into: &map)
                current = PendingDevice(name: name)
            }
        }

        if trimmed.hasPrefix("Address:") {
            let address = trimmed.replacingOccurrences(of: "Address: ", with: "")
                .trimmingCharacters(in: .whitespaces)
                .lowercased()
                .replacingOccurrences(of: ":", with: "-")
            current?.address = address
        }
        if trimmed.hasPrefix("Battery Level:") && !trimmed.hasPrefix("Left") && !trimmed.hasPrefix("Right") && !trimmed.hasPrefix("Case") {
            current?.batteryLevel = parseBatteryLevel(from: trimmed, prefix: "Battery Level:")
        }
        if trimmed.hasPrefix("Left Battery Level:") {
            current?.leftBattery = parseBatteryLevel(from: trimmed, prefix: "Left Battery Level:")
        }
        if trimmed.hasPrefix("Right Battery Level:") {
            current?.rightBattery = parseBatteryLevel(from: trimmed, prefix: "Right Battery Level:")
        }
        if trimmed.hasPrefix("Case Battery Level:") {
            current?.caseBattery = parseBatteryLevel(from: trimmed, prefix: "Case Battery Level:")
        }
        if trimmed.hasPrefix("Minor Type:") {
            current?.minorType = trimmed.replacingOccurrences(of: "Minor Type: ", with: "")
                .trimmingCharacters(in: .whitespaces)
        }
    }
    flushDevice(current, into: &map)
    return map
}

private func parseBatteryLevel(from line: String, prefix: String) -> Int? {
    let value = line.replacingOccurrences(of: prefix, with: "")
        .trimmingCharacters(in: .whitespaces)
        .replacingOccurrences(of: "%", with: "")
        .trimmingCharacters(in: .whitespaces)
    guard let level = Int(value) else { return nil }
    return max(0, min(100, level))
}
