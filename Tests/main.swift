import Foundation

var totalPassed = 0
var totalFailed = 0
var currentSuite = ""

func suite(_ name: String) {
    currentSuite = name
    print("--- \(name) ---")
}

func assertEq<T: Equatable>(_ actual: T, _ expected: T, _ message: String = "", file: String = #file, line: Int = #line) {
    if actual == expected {
        totalPassed += 1
    } else {
        totalFailed += 1
        let label = message.isEmpty ? "" : " - \(message)"
        print("  FAIL [\(file):\(line)]\(label): expected \(expected), got \(actual)")
    }
}

func assertTrue(_ condition: Bool, _ message: String = "", file: String = #file, line: Int = #line) {
    if condition {
        totalPassed += 1
    } else {
        totalFailed += 1
        let label = message.isEmpty ? "" : " - \(message)"
        print("  FAIL [\(file):\(line)]\(label): expected true")
    }
}

func assertFalse(_ condition: Bool, _ message: String = "", file: String = #file, line: Int = #line) {
    if !condition {
        totalPassed += 1
    } else {
        totalFailed += 1
        let label = message.isEmpty ? "" : " - \(message)"
        print("  FAIL [\(file):\(line)]\(label): expected false")
    }
}

func assertNil<T>(_ value: T?, _ message: String = "", file: String = #file, line: Int = #line) {
    if value == nil {
        totalPassed += 1
    } else {
        totalFailed += 1
        let label = message.isEmpty ? "" : " - \(message)"
        print("  FAIL [\(file):\(line)]\(label): expected nil, got \(value!)")
    }
}

func assertNotNil<T>(_ value: T?, _ message: String = "", file: String = #file, line: Int = #line) {
    if value != nil {
        totalPassed += 1
    } else {
        totalFailed += 1
        let label = message.isEmpty ? "" : " - \(message)"
        print("  FAIL [\(file):\(line)]\(label): expected non-nil")
    }
}

testSettingsStore()
testBluetoothDevice()
testBatteryHistory()
testSystemProfiler()

print("\n=== Results: \(totalPassed) passed, \(totalFailed) failed ===")
exit(totalFailed > 0 ? 1 : 0)
