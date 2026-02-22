import Foundation

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
