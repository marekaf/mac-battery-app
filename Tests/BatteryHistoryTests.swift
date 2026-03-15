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

    // currentDrainSegment: simple drain
    let simpleDrain = [
        BatteryReading(timestamp: now.addingTimeInterval(-300), level: 90),
        BatteryReading(timestamp: now.addingTimeInterval(-200), level: 88),
        BatteryReading(timestamp: now, level: 85),
    ]
    let seg1 = BatteryHistoryStore(history: [:]).currentDrainSegment(simpleDrain)
    assertEq(seg1.count, 3, "simple drain returns all readings")
    assertEq(seg1.first?.level, 90, "simple drain starts at 90")

    // currentDrainSegment: charge then drain
    let chargeThenDrain = [
        BatteryReading(timestamp: now.addingTimeInterval(-500), level: 60),
        BatteryReading(timestamp: now.addingTimeInterval(-400), level: 70),
        BatteryReading(timestamp: now.addingTimeInterval(-300), level: 95),
        BatteryReading(timestamp: now.addingTimeInterval(-200), level: 90),
        BatteryReading(timestamp: now, level: 85),
    ]
    let seg2 = BatteryHistoryStore(history: [:]).currentDrainSegment(chargeThenDrain)
    assertEq(seg2.count, 3, "charge+drain returns drain segment only")
    assertEq(seg2.first?.level, 95, "drain segment starts at peak after charge")

    // currentDrainSegment: empty and single
    let seg3 = BatteryHistoryStore(history: [:]).currentDrainSegment([])
    assertEq(seg3.count, 0, "empty returns empty")
    let seg4 = BatteryHistoryStore(history: [:]).currentDrainSegment([BatteryReading(timestamp: now, level: 50)])
    assertEq(seg4.count, 1, "single returns single")

    // estimatedTimeRemaining after charge cycle (the mouse bug)
    let chargeHistory = [
        BatteryReading(timestamp: now.addingTimeInterval(-7200), level: 60),
        BatteryReading(timestamp: now.addingTimeInterval(-3600), level: 95),
        BatteryReading(timestamp: now.addingTimeInterval(-1800), level: 90),
        BatteryReading(timestamp: now, level: 85),
    ]
    let chargeStore = BatteryHistoryStore(history: ["mouse": chargeHistory])
    let chargeEstimate = chargeStore.estimatedTimeRemaining(for: "mouse")
    assertNotNil(chargeEstimate, "estimate works after charge cycle")
    assert(chargeEstimate != "Insufficient data", "not insufficient data after charge cycle: \(chargeEstimate ?? "nil")")

    // record() learns drain rate after charge cycle
    let learnStore = BatteryHistoryStore(history: ["m1": [
        BatteryReading(timestamp: now.addingTimeInterval(-7200), level: 60),
        BatteryReading(timestamp: now.addingTimeInterval(-3600), level: 95),
        BatteryReading(timestamp: now.addingTimeInterval(-1800), level: 90),
    ]])
    learnStore.record(deviceID: "m1", level: 85)
    assertNotNil(learnStore.learnedDrainRates["m1"], "learns drain rate after charge cycle")
}
