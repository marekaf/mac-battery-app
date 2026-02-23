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
