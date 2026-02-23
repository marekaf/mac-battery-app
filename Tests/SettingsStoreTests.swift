import Foundation

func testSettingsStore() {
    suite("SettingsStore")

    let store = SettingsStore()

    // setDisplayMode - valid modes
    for mode in ["separate", "single", "compact", "stacked"] {
        store.setDisplayMode(mode)
        assertEq(store.displayMode, mode, "setDisplayMode(\(mode))")
    }

    // setDisplayMode - invalid falls back to "separate"
    store.setDisplayMode("bogus")
    assertEq(store.displayMode, "separate", "invalid mode falls back")
    store.setDisplayMode("")
    assertEq(store.displayMode, "separate", "empty mode falls back")

    // isStackedMode / isSingleMode / isCompactMode
    store.setDisplayMode("stacked")
    assertTrue(store.isStackedMode, "isStackedMode when stacked")
    assertFalse(store.isSingleMode, "isSingleMode when stacked")
    assertFalse(store.isCompactMode, "isCompactMode when stacked")

    store.setDisplayMode("single")
    assertTrue(store.isSingleMode, "isSingleMode when single")
    assertFalse(store.isStackedMode, "isStackedMode when single")
    assertFalse(store.isCompactMode, "isCompactMode when single")

    store.setDisplayMode("compact")
    assertTrue(store.isCompactMode, "isCompactMode when compact")
    assertTrue(store.isSingleMode, "isSingleMode when compact (compact implies single)")

    store.setDisplayMode("separate")
    assertFalse(store.isSingleMode, "isSingleMode when separate")
    assertFalse(store.isCompactMode, "isCompactMode when separate")
    assertFalse(store.isStackedMode, "isStackedMode when separate")

    // setLowBatteryThreshold clamping
    store.setLowBatteryThreshold(10)
    assertEq(store.lowBatteryThreshold, 10, "threshold normal")
    store.setLowBatteryThreshold(1)
    assertEq(store.lowBatteryThreshold, 5, "threshold clamped low")
    store.setLowBatteryThreshold(50)
    assertEq(store.lowBatteryThreshold, 25, "threshold clamped high")
    store.setLowBatteryThreshold(5)
    assertEq(store.lowBatteryThreshold, 5, "threshold at lower bound")
    store.setLowBatteryThreshold(25)
    assertEq(store.lowBatteryThreshold, 25, "threshold at upper bound")

    // setRefreshInterval clamping
    store.setRefreshInterval(30)
    assertEq(store.refreshInterval, 30, "interval normal")
    store.setRefreshInterval(1)
    assertEq(store.refreshInterval, 10, "interval clamped low")
    store.setRefreshInterval(999)
    assertEq(store.refreshInterval, 120, "interval clamped high")
    store.setRefreshInterval(10)
    assertEq(store.refreshInterval, 10, "interval at lower bound")
    store.setRefreshInterval(120)
    assertEq(store.refreshInterval, 120, "interval at upper bound")

    // toggleVisibility / isHidden round-trip
    let testID = "test-device-\(UUID().uuidString)"
    assertFalse(store.isHidden(testID), "not hidden initially")
    store.toggleVisibility(testID)
    assertTrue(store.isHidden(testID), "hidden after toggle")
    store.toggleVisibility(testID)
    assertFalse(store.isHidden(testID), "unhidden after second toggle")

    // moveDevice - direction bounds
    store.setDeviceOrder(["a", "b", "c"])
    store.moveDevice("a", direction: -1) // can't move first up
    assertEq(store.deviceOrder, ["a", "b", "c"], "moveDevice first up no-op")
    store.moveDevice("c", direction: 1) // can't move last down
    assertEq(store.deviceOrder, ["a", "b", "c"], "moveDevice last down no-op")
    store.moveDevice("b", direction: -1) // swap b with a
    assertEq(store.deviceOrder, ["b", "a", "c"], "moveDevice b up")
    store.moveDevice("a", direction: 1) // swap a with c
    assertEq(store.deviceOrder, ["b", "c", "a"], "moveDevice a down")
    store.moveDevice("unknown", direction: 1) // non-existent device
    assertEq(store.deviceOrder, ["b", "c", "a"], "moveDevice unknown no-op")
}
