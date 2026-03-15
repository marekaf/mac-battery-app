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

        let drainSegment = currentDrainSegment(readings)
        if let first = drainSegment.first, let last = drainSegment.last {
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

        let drain = currentDrainSegment(all)
        guard drain.count >= 2,
              let firstReading = drain.first, let lastReading = drain.last else { return nil }

        let totalTime = lastReading.timestamp.timeIntervalSince(firstReading.timestamp)
        guard totalTime > 120 else { return "Collecting data..." }

        let cutoffs: [TimeInterval?] = [-3600, -86400, nil]
        for cutoff in cutoffs {
            let subset: [BatteryReading]
            if let cutoff = cutoff {
                subset = drain.filter { $0.timestamp >= Date().addingTimeInterval(cutoff) }
            } else {
                subset = drain
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

    func currentDrainSegment(_ readings: [BatteryReading]) -> [BatteryReading] {
        guard readings.count >= 2 else { return readings }
        var peakIndex = 0
        for i in stride(from: readings.count - 1, through: 1, by: -1) {
            if readings[i].level > readings[i - 1].level {
                peakIndex = i
                break
            }
        }
        return Array(readings[peakIndex...])
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
