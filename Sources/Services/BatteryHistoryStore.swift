import Foundation

struct BatteryReading: Codable {
    let timestamp: Date
    let level: Int
}

class BatteryHistoryStore {
    private let historyKey = "batteryHistory"
    private let ratesKey = "learnedDrainRates"
    var history: [String: [BatteryReading]] = [:]
    var learnedDrainRates: [String: Double] = [:]  // deviceID → hours per 1%
    let maxReadings = 2016

    init() {
        load()
        loadRates()
    }

    init(history: [String: [BatteryReading]], learnedDrainRates: [String: Double] = [:]) {
        self.history = history
        self.learnedDrainRates = learnedDrainRates
    }

    func record(deviceID: String, level: Int) {
        var readings = history[deviceID] ?? []
        let now = Date()
        if let last = readings.last,
           now.timeIntervalSince(last.timestamp) < 240 && last.level == level {
            return
        }
        readings.append(BatteryReading(timestamp: now, level: level))
        if readings.count > maxReadings {
            readings = Array(readings.suffix(maxReadings))
        }
        history[deviceID] = readings
        save()

        if let first = readings.first, let last = readings.last {
            let timeDelta = last.timestamp.timeIntervalSince(first.timestamp)
            let levelDrop = Double(first.level - last.level)
            if timeDelta > 120 && levelDrop > 0 {
                let hoursPerPercent = (timeDelta / 3600.0) / levelDrop
                learnedDrainRates[deviceID] = hoursPerPercent
                saveRates()
            }
        }
    }

    func readings(for deviceID: String) -> [BatteryReading] {
        history[deviceID] ?? []
    }

    func estimatedTimeRemaining(for deviceID: String) -> String? {
        let all = readings(for: deviceID)

        if let rate = learnedDrainRates[deviceID], let current = all.last {
            let hoursLeft = rate * Double(current.level)
            return formatTimeRemaining(hoursLeft)
        }

        guard all.count >= 2,
              let firstReading = all.first, let lastReading = all.last else { return nil }

        let totalTime = lastReading.timestamp.timeIntervalSince(firstReading.timestamp)
        guard totalTime > 120 else { return "Collecting data..." }

        let cutoffs: [TimeInterval?] = [-3600, -86400, nil]
        for cutoff in cutoffs {
            let subset: [BatteryReading]
            if let cutoff = cutoff {
                subset = all.filter { $0.timestamp >= Date().addingTimeInterval(cutoff) }
            } else {
                subset = all
            }
            guard subset.count >= 2,
                  let first = subset.first, let last = subset.last else { continue }
            let timeDelta = last.timestamp.timeIntervalSince(first.timestamp)
            guard timeDelta > 120 else { continue }
            let levelDrop = Double(first.level - last.level)
            guard levelDrop > 0 else { continue }
            let drainPerHour = levelDrop / (timeDelta / 3600.0)
            let hoursLeft = Double(last.level) / drainPerHour
            return formatTimeRemaining(hoursLeft)
        }

        return "Insufficient data"
    }

    func formatTimeRemaining(_ hoursLeft: Double) -> String {
        if hoursLeft >= 24 {
            let days = Int(hoursLeft / 24)
            let hours = Int(hoursLeft) % 24
            if hours == 0 { return "~\(days)d remaining" }
            return "~\(days)d \(hours)h remaining"
        }
        if hoursLeft < 1 {
            let mins = max(1, Int(hoursLeft * 60))
            return "~\(mins)m remaining"
        }
        let hours = Int(hoursLeft)
        let mins = Int((hoursLeft - Double(hours)) * 60)
        if mins == 0 { return "~\(hours)h remaining" }
        return "~\(hours)h \(mins)m remaining"
    }

    private func save() {
        if let data = try? JSONEncoder().encode(history) {
            UserDefaults.standard.set(data, forKey: historyKey)
        }
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: historyKey),
              let decoded = try? JSONDecoder().decode([String: [BatteryReading]].self, from: data) else { return }
        history = decoded
    }

    private func saveRates() {
        if let data = try? JSONEncoder().encode(learnedDrainRates) {
            UserDefaults.standard.set(data, forKey: ratesKey)
        }
    }

    private func loadRates() {
        guard let data = UserDefaults.standard.data(forKey: ratesKey),
              let decoded = try? JSONDecoder().decode([String: Double].self, from: data) else { return }
        learnedDrainRates = decoded
    }
}
