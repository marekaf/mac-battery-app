import Foundation

func testSystemProfiler() {
    suite("SystemProfiler")

    // parseBatteryLevel
    assertEq(parseBatteryLevel(from: "Battery Level: 75%", prefix: "Battery Level:"), 75, "normal level")
    assertEq(parseBatteryLevel(from: "Battery Level: 0%", prefix: "Battery Level:"), 0, "zero")
    assertEq(parseBatteryLevel(from: "Battery Level: 100%", prefix: "Battery Level:"), 100, "100%")
    assertEq(parseBatteryLevel(from: "Battery Level: 150%", prefix: "Battery Level:"), 100, "clamp >100")
    assertEq(parseBatteryLevel(from: "Battery Level: -5%", prefix: "Battery Level:"), 0, "clamp <0")
    assertNil(parseBatteryLevel(from: "Battery Level: abc", prefix: "Battery Level:"), "non-numeric")
    assertNil(parseBatteryLevel(from: "Battery Level: ", prefix: "Battery Level:"), "empty value")
    assertEq(parseBatteryLevel(from: "Left Battery Level: 85%", prefix: "Left Battery Level:"), 85, "left battery")

    // parseBluetoothOutput - single device
    let singleDevice = """
        Bluetooth:
          Connected:
            Magic Keyboard:
              Address: AA:BB:CC:DD:EE:FF
              Battery Level: 75%
              Minor Type: Keyboard
    """
    let single = parseBluetoothOutput(text: singleDevice)
    assertEq(single.count, 1, "single device count")
    let kb = single["aa-bb-cc-dd-ee-ff"]
    assertNotNil(kb, "keyboard found by address")
    assertEq(kb?.name, "Magic Keyboard", "keyboard name")
    assertEq(kb?.batteryLevel, 75, "keyboard battery")
    assertEq(kb?.minorType, "Keyboard", "keyboard minor type")

    // parseBluetoothOutput - multiple devices
    let multiDevice = """
        Bluetooth:
          Connected:
            Magic Keyboard:
              Address: 11:22:33:44:55:66
              Battery Level: 80%
            Magic Mouse:
              Address: AA:BB:CC:DD:EE:FF
              Battery Level: 65%
    """
    let multi = parseBluetoothOutput(text: multiDevice)
    assertEq(multi.count, 2, "multi device count")
    assertNotNil(multi["11-22-33-44-55-66"], "first device found")
    assertNotNil(multi["aa-bb-cc-dd-ee-ff"], "second device found")
    assertEq(multi["11-22-33-44-55-66"]?.name, "Magic Keyboard", "first name")
    assertEq(multi["aa-bb-cc-dd-ee-ff"]?.name, "Magic Mouse", "second name")

    // parseBluetoothOutput - component batteries (AirPods)
    let airpods = """
        Bluetooth:
          Connected:
            AirPods Pro:
              Address: 11:22:33:44:55:66
              Left Battery Level: 90%
              Right Battery Level: 85%
              Case Battery Level: 70%
    """
    let pods = parseBluetoothOutput(text: airpods)
    let podInfo = pods["11-22-33-44-55-66"]
    assertNotNil(podInfo, "airpods found")
    assertEq(podInfo?.leftBattery, 90, "left battery")
    assertEq(podInfo?.rightBattery, 85, "right battery")
    assertEq(podInfo?.caseBattery, 70, "case battery")
    assertNil(podInfo?.batteryLevel, "no main battery for airpods")

    // parseBluetoothOutput - duplicate address merging
    let dupeAddr = """
        Bluetooth:
          Connected:
            AirPods Pro:
              Address: 11:22:33:44:55:66
              Battery Level: 80%
          Not Connected:
            AirPods Pro:
              Address: 11:22:33:44:55:66
              Left Battery Level: 90%
    """
    let merged = parseBluetoothOutput(text: dupeAddr)
    assertEq(merged.count, 1, "merged into one entry")
    let mergedDevice = merged["11-22-33-44-55-66"]
    assertEq(mergedDevice?.batteryLevel, 80, "kept first battery level")
    assertEq(mergedDevice?.leftBattery, 90, "merged left battery")

    // parseBluetoothOutput - 10-space indentation (real macOS output)
    let tenSpace = """
      Bluetooth:
          Connected:
              AirPods Pro:
                  Address: 11:22:33:44:55:66
                  Left Battery Level: 90%
                  Right Battery Level: 85%
                  Case Battery Level: 70%
    """
    let tenResult = parseBluetoothOutput(text: tenSpace)
    assertEq(tenResult.count, 1, "10-space indent device count")
    assertNotNil(tenResult["11-22-33-44-55-66"], "10-space indent device found")

    // parseBluetoothOutput - empty input
    let empty = parseBluetoothOutput(text: "")
    assertEq(empty.count, 0, "empty input")

    // parseBluetoothOutput - no devices section
    let noDevices = parseBluetoothOutput(text: "Bluetooth:\n  Something else\n")
    assertEq(noDevices.count, 0, "no devices")

    // parseBluetoothOutput - device without address is skipped
    let noAddr = """
        Bluetooth:
          Connected:
            Magic Keyboard:
              Battery Level: 75%
    """
    let skipped = parseBluetoothOutput(text: noAddr)
    assertEq(skipped.count, 0, "device without address skipped")

    // parseBluetoothOutput - address normalization (lowercase, colons to dashes)
    let upperAddr = """
        Bluetooth:
          Connected:
            Magic Mouse:
              Address: AB:CD:EF:01:23:45
              Battery Level: 50%
    """
    let normalized = parseBluetoothOutput(text: upperAddr)
    assertNotNil(normalized["ab-cd-ef-01-23-45"], "address normalized")
    assertNil(normalized["AB:CD:EF:01:23:45"], "original format not present")
}
