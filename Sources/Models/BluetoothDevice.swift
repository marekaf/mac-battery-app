import Foundation

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
    String(name.prefix(100)).filter { char in
        char.unicodeScalars.allSatisfy { !CharacterSet.controlCharacters.contains($0) }
    }
}

func detectDeviceType(from name: String) -> DeviceType {
    let lower = name.lowercased()
    if lower.contains("keyboard") { return .keyboard }
    if lower.contains("mouse") || lower.contains("mx master") || lower.contains("mx anywhere") { return .mouse }
    if lower.contains("trackpad") { return .trackpad }
    if lower.contains("airpods") || lower.contains("headphone") || lower.contains("beats") { return .headphones }
    return .unknown
}
