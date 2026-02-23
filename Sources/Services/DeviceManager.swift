import Foundation

class DeviceManager {
    private var timer: Timer?
    private let bleReader = BLEBatteryReader()
    private var nameMap: [String: BluetoothDeviceInfo] = [:]
    private(set) var devices: [BluetoothDevice] = []
    var onDevicesChanged: (([BluetoothDevice]) -> Void)?
    private var refreshInterval: TimeInterval

    private var bleDevices: [BluetoothDevice] = []

    deinit {
        timer?.invalidate()
        bleReader.onDevicesUpdated = nil
    }

    init(refreshInterval: Int = 30) {
        self.refreshInterval = TimeInterval(refreshInterval)
        nameMap = buildBluetoothNameMap()

        bleReader.onDevicesUpdated = { [weak self] devices in
            guard let self = self else { return }
            self.bleDevices = devices
            self.mergeAndNotify()
        }

        refresh()
        startTimer()
    }

    func updateRefreshInterval(_ seconds: Int) {
        refreshInterval = TimeInterval(seconds)
        timer?.invalidate()
        startTimer()
    }

    private func startTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: refreshInterval, repeats: true) { [weak self] _ in
            self?.refresh()
        }
    }

    func refresh() {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let map = buildBluetoothNameMap()
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.nameMap = map
                self.bleReader.scanForConnectedPeripherals()
                self.mergeAndNotify()
            }
        }
    }

    private func mergeAndNotify() {
        let iokitDevices = readIOKitBatteryDevices(nameMap: nameMap)

        var merged: [BluetoothDevice] = iokitDevices
        let iokitIDs = Set(iokitDevices.map { $0.id })

        for bleDevice in bleDevices {
            if !iokitIDs.contains(bleDevice.id) {
                merged.append(bleDevice)
            }
        }

        let knownIDs = Set(merged.map { $0.id })
        let knownNames = Set(merged.map { $0.name })
        for (address, info) in nameMap {
            guard !knownIDs.contains(address) else { continue }
            guard !knownNames.contains(info.name) else { continue }
            let hasAnyBattery = info.batteryLevel != nil || info.leftBattery != nil
                || info.rightBattery != nil || info.caseBattery != nil
            guard hasAnyBattery else { continue }

            let battery: Int
            if let level = info.batteryLevel {
                battery = level
            } else {
                let levels = [info.leftBattery, info.rightBattery, info.caseBattery].compactMap { $0 }
                battery = levels.isEmpty ? 0 : levels.reduce(0, +) / levels.count
            }

            let name = sanitizeDeviceName(info.name)
            merged.append(BluetoothDevice(
                id: address, name: name, batteryLevel: battery,
                deviceType: detectDeviceType(from: name),
                leftBattery: info.leftBattery, rightBattery: info.rightBattery, caseBattery: info.caseBattery
            ))
        }

        merged.sort { $0.name < $1.name }

        if merged != devices {
            devices = merged
            onDevicesChanged?(devices)
        }
    }
}
