import Foundation

func testBatteryHistory() {
    suite("BatteryHistory")

    let store = BatteryHistoryStore(history: [:])

    // formatTimeRemaining
    assertEq(store.formatTimeRemaining(0.5), "~30m remaining", "30 min")
    assertEq(store.formatTimeRemaining(0.01), "~1m remaining", "sub-1m clamped to 1m")
    assertEq(store.formatTimeRemaining(2.5), "~2h 30m remaining", "2h30m")
    assertEq(store.formatTimeRemaining(1.0), "~1h remaining", "exact 1h")
    assertEq(store.formatTimeRemaining(3.0), "~3h remaining", "exact 3h")
    assertEq(store.formatTimeRemaining(25.0), "~1d 1h remaining", "25h = 1d 1h")
    assertEq(store.formatTimeRemaining(48.0), "~2d remaining", "exact 2d")
    assertEq(store.formatTimeRemaining(49.5), "~2d 1h remaining", "2d 1.5h")
    assertEq(store.formatTimeRemaining(24.0), "~1d remaining", "exact 1d")
    assertEq(store.formatTimeRemaining(72.0), "~3d remaining", "exact 3d")

    // record() dedup: skips duplicate level within 240s
    let dedupStore = BatteryHistoryStore(history: [:])
    dedupStore.record(deviceID: "d1", level: 80)
    assertEq(dedupStore.readings(for: "d1").count, 1, "first record")
    dedupStore.record(deviceID: "d1", level: 80) // same level, within 240s
    assertEq(dedupStore.readings(for: "d1").count, 1, "dedup same level")
    dedupStore.record(deviceID: "d1", level: 79) // different level
    assertEq(dedupStore.readings(for: "d1").count, 2, "different level recorded")

    // record() dedup: records after 240s even with same level
    let now = Date()
    let old = now.addingTimeInterval(-300)
    let oldReading = BatteryReading(timestamp: old, level: 50)
    let timedStore = BatteryHistoryStore(history: ["d2": [oldReading]])
    timedStore.record(deviceID: "d2", level: 50)
    assertEq(timedStore.readings(for: "d2").count, 2, "same level after 240s recorded")

    // estimatedTimeRemaining with learned drain rates
    let rateStore = BatteryHistoryStore(
        history: ["d3": [BatteryReading(timestamp: now, level: 50)]],
        learnedDrainRates: ["d3": 0.5] // 0.5 hours per 1%
    )
    let estimate = rateStore.estimatedTimeRemaining(for: "d3")
    assertNotNil(estimate, "has estimate with learned rate")
    assertEq(estimate, "~1d 1h remaining", "50% at 0.5h/% = 25h")

    // estimatedTimeRemaining returns nil with no data
    let emptyStore = BatteryHistoryStore(history: [:])
    assertNil(emptyStore.estimatedTimeRemaining(for: "nonexistent"), "nil for unknown device")

    // estimatedTimeRemaining with single reading (no rate)
    let singleStore = BatteryHistoryStore(history: ["d4": [BatteryReading(timestamp: now, level: 80)]])
    assertNil(singleStore.estimatedTimeRemaining(for: "d4"), "nil with single reading")
}
