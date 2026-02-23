import Foundation

func testBluetoothDevice() {
    suite("BluetoothDevice")

    // detectDeviceType
    assertEq(detectDeviceType(from: "Magic Keyboard"), DeviceType.keyboard, "keyboard")
    assertEq(detectDeviceType(from: "Logitech Keyboard K380"), DeviceType.keyboard, "keyboard mixed case")
    assertEq(detectDeviceType(from: "Magic Mouse"), DeviceType.mouse, "mouse")
    assertEq(detectDeviceType(from: "MX Master 3S"), DeviceType.mouse, "MX Master")
    assertEq(detectDeviceType(from: "MX Anywhere 3"), DeviceType.mouse, "MX Anywhere")
    assertEq(detectDeviceType(from: "Magic Trackpad"), DeviceType.trackpad, "trackpad")
    assertEq(detectDeviceType(from: "AirPods Pro"), DeviceType.headphones, "AirPods")
    assertEq(detectDeviceType(from: "Beats Studio Buds"), DeviceType.headphones, "Beats")
    assertEq(detectDeviceType(from: "Sony WH-1000XM5"), DeviceType.unknown, "unknown")
    assertEq(detectDeviceType(from: ""), DeviceType.unknown, "empty string")

    // sanitizeDeviceName - control characters stripped
    assertEq(sanitizeDeviceName("Normal Name"), "Normal Name", "normal name")
    assertEq(sanitizeDeviceName("Has\u{0000}Null"), "HasNull", "null char stripped")
    assertEq(sanitizeDeviceName("Tab\there"), "Tabhere", "tab stripped")
    assertEq(sanitizeDeviceName("New\nLine"), "NewLine", "newline stripped")

    // sanitizeDeviceName - length capped at 100
    let longName = String(repeating: "a", count: 150)
    assertEq(sanitizeDeviceName(longName).count, 100, "long name capped")
    assertEq(sanitizeDeviceName("short").count, 5, "short name unchanged")

    // componentBatteryText formatting
    let fullDevice = BluetoothDevice(id: "1", name: "AirPods", batteryLevel: 80, deviceType: .headphones,
                                     leftBattery: 90, rightBattery: 85, caseBattery: 70)
    assertEq(fullDevice.componentBatteryText, "L:90% R:85% C:70%", "L/R/C")

    let leftOnly = BluetoothDevice(id: "2", name: "AirPods", batteryLevel: 80, deviceType: .headphones,
                                   leftBattery: 90)
    assertEq(leftOnly.componentBatteryText, "L:90%", "L only")

    let leftRight = BluetoothDevice(id: "3", name: "AirPods", batteryLevel: 80, deviceType: .headphones,
                                    leftBattery: 90, rightBattery: 85)
    assertEq(leftRight.componentBatteryText, "L:90% R:85%", "L/R")

    let noComponents = BluetoothDevice(id: "4", name: "Mouse", batteryLevel: 80, deviceType: .mouse)
    assertNil(noComponents.componentBatteryText, "nil when no components")

    // hasComponentBatteries
    assertTrue(fullDevice.hasComponentBatteries, "has components")
    assertFalse(noComponents.hasComponentBatteries, "no components")
    assertTrue(leftOnly.hasComponentBatteries, "left only has components")

    let caseOnly = BluetoothDevice(id: "5", name: "AirPods", batteryLevel: 80, deviceType: .headphones,
                                   caseBattery: 50)
    assertTrue(caseOnly.hasComponentBatteries, "case only has components")
    assertEq(caseOnly.componentBatteryText, "C:50%", "case only text")

    // parseDeviceTypeFromWakeReason
    assertEq(parseDeviceTypeFromWakeReason("Keyboard"), "Keyboard", "wake keyboard")
    assertEq(parseDeviceTypeFromWakeReason("Mouse"), "Mouse", "wake mouse")
    assertEq(parseDeviceTypeFromWakeReason("Trackpad"), "Trackpad", "wake trackpad")
    assertEq(parseDeviceTypeFromWakeReason("something else"), "Bluetooth Device", "wake unknown")
    assertEq(parseDeviceTypeFromWakeReason("KEYBOARD"), "Keyboard", "wake keyboard uppercase")
}
