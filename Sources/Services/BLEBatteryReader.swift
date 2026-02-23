import Foundation
import CoreBluetooth

let batteryServiceUUID = CBUUID(string: "180F")
let batteryLevelCharUUID = CBUUID(string: "2A19")

class BLEBatteryReader: NSObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    private var centralManager: CBCentralManager!
    private var discoveredPeripherals: [CBPeripheral] = []
    private var peripheralBatteryLevels: [UUID: Int] = [:]
    private var peripheralNames: [UUID: String] = [:]
    private var pendingRemovals: [UUID: DispatchWorkItem] = [:]
    private let removalGracePeriod: TimeInterval = 15
    var onDevicesUpdated: (([BluetoothDevice]) -> Void)?

    override init() {
        super.init()
        centralManager = CBCentralManager(delegate: self, queue: nil)
    }

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if central.state == .poweredOn {
            scanForConnectedPeripherals()
        }
    }

    func scanForConnectedPeripherals() {
        guard centralManager.state == .poweredOn else { return }
        let connected = centralManager.retrieveConnectedPeripherals(withServices: [batteryServiceUUID])
        for peripheral in connected {
            pendingRemovals[peripheral.identifier]?.cancel()
            pendingRemovals.removeValue(forKey: peripheral.identifier)
            if !discoveredPeripherals.contains(where: { $0.identifier == peripheral.identifier }) {
                discoveredPeripherals.append(peripheral)
                peripheral.delegate = self
                peripheralNames[peripheral.identifier] = sanitizeDeviceName(peripheral.name ?? "BLE Device")
                centralManager.connect(peripheral, options: nil)
            }
        }
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        pendingRemovals[peripheral.identifier]?.cancel()
        pendingRemovals.removeValue(forKey: peripheral.identifier)
        peripheral.discoverServices([batteryServiceUUID])
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        discoveredPeripherals.removeAll { $0.identifier == peripheral.identifier }

        let work = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            self.pendingRemovals.removeValue(forKey: peripheral.identifier)
            self.peripheralBatteryLevels.removeValue(forKey: peripheral.identifier)
            self.peripheralNames.removeValue(forKey: peripheral.identifier)
            self.notifyDevicesUpdated()
        }
        pendingRemovals[peripheral.identifier]?.cancel()
        pendingRemovals[peripheral.identifier] = work
        DispatchQueue.main.asyncAfter(deadline: .now() + removalGracePeriod, execute: work)

        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            self?.scanForConnectedPeripherals()
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard let services = peripheral.services else { return }
        for service in services where service.uuid == batteryServiceUUID {
            peripheral.discoverCharacteristics([batteryLevelCharUUID], for: service)
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard let chars = service.characteristics else { return }
        for char in chars where char.uuid == batteryLevelCharUUID {
            peripheral.readValue(for: char)
            peripheral.setNotifyValue(true, for: char)
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard characteristic.uuid == batteryLevelCharUUID,
              let data = characteristic.value,
              !data.isEmpty else { return }
        let level = max(0, min(100, Int(data[0])))
        peripheralBatteryLevels[peripheral.identifier] = level
        if let name = peripheral.name, !name.isEmpty {
            peripheralNames[peripheral.identifier] = sanitizeDeviceName(name)
        }
        notifyDevicesUpdated()
    }

    private func notifyDevicesUpdated() {
        let devices = peripheralBatteryLevels.compactMap { (id, level) -> BluetoothDevice? in
            let name = peripheralNames[id] ?? "BLE Device"
            return BluetoothDevice(
                id: "ble-\(id.uuidString)",
                name: name,
                batteryLevel: level,
                deviceType: detectDeviceType(from: name)
            )
        }
        onDevicesUpdated?(devices)
    }

    func currentDevices() -> [BluetoothDevice] {
        peripheralBatteryLevels.compactMap { (id, level) -> BluetoothDevice? in
            let name = peripheralNames[id] ?? "BLE Device"
            return BluetoothDevice(
                id: "ble-\(id.uuidString)",
                name: name,
                batteryLevel: level,
                deviceType: detectDeviceType(from: name)
            )
        }
    }
}
