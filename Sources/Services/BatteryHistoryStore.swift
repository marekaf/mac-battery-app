import Foundation

struct BatteryReading: Codable {
    let timestamp: Date
    let level: Int
}

class BatteryHistoryStore {
    private let historyKey = "batteryHistory"
    private var history: [String: [BatteryReading]] = [:]
    private let maxReadings = 288

    init() {
        load()
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
    }

    func readings(for deviceID: String) -> [BatteryReading] {
        history[deviceID] ?? []
    }

    func estimatedTimeRemaining(for deviceID: String) -> String? {
        let all = readings(for: deviceID)
        guard all.count >= 2 else { return nil }
        let shortCutoff = Date().addingTimeInterval(-3600)
        var recent = all.filter { $0.timestamp >= shortCutoff }
        if recent.count < 2 {
            let longCutoff = Date().addingTimeInterval(-86400)
            recent = all.filter { $0.timestamp >= longCutoff }
        }
        guard recent.count >= 2,
              let first = recent.first, let last = recent.last else { return "Collecting data..." }
        let timeDelta = last.timestamp.timeIntervalSince(first.timestamp)
        guard timeDelta > 120 else { return "Collecting data..." }
        let levelDrop = Double(first.level - last.level)
        guard levelDrop > 0 else { return "Battery stable" }
        let drainPerHour = levelDrop / (timeDelta / 3600.0)
        let hoursLeft = Double(last.level) / drainPerHour
        if hoursLeft < 1 {
            let mins = Int(hoursLeft * 60)
            return "~\(mins)m remaining"
        }
        let hours = Int(hoursLeft)
        let mins = Int((hoursLeft - Double(hours)) * 60)
        if mins == 0 {
            return "~\(hours)h remaining"
        }
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
}
