//
//  SensorManager.swift
//  SensorTagLogger
//
//  Created by Andreas Girgensohn on 5/13/20.
//  Copyright © 2020 Andreas Girgensohn. All rights reserved.
//

import CoreBluetooth

class SensorManager: NSObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    weak var delegate: SensorManagerDelegate?
    static let deviceInfoUUID = CBUUID(string: "180A")
    static let systemIdUUID   = CBUUID(string: "2A23")
    static let batteryUUID    = CBUUID(string: "180F")
    static let humidityUUID   = CBUUID(string: "F000AA20-0451-4000-B000-000000000000")
    static let barometerUUID  = CBUUID(string: "F000AA40-0451-4000-B000-000000000000")
    static let luxometerUUID  = CBUUID(string: "F000AA70-0451-4000-B000-000000000000")
    static let movementUUID   = CBUUID(string: "F000AA80-0451-4000-B000-000000000000")
    let scanServiceIds: [CBUUID]? = [CBUUID(string: "AA80")]
    var sensorServiceIds: [CBUUID]!
    var centralManager: CBCentralManager!
    var rejectedUUIDs = Set<String>()
    var pendingPeripherals: [CBPeripheral] = []
    var sensorPeripherals: [CBPeripheral?] = [nil, nil]
    var batteryCharacteristic: [CBCharacteristic?] = [nil, nil]
    var lastBatteryCheck = [Date.distantPast, Date.distantPast]
    var sysIdValues = ["", ""]
    var uuidValues = ["", ""]
    var idsInitialized = false
    let uploadDataURL = URL(string: "https://www.webcollab.com/data")!
    var collectedData: [[String: Any]] = []

    override init() {
        super.init()
        sensorServiceIds = [SensorManager.humidityUUID, /* SensorManager.barometerUUID, SensorManager.luxometerUUID, */ SensorManager.movementUUID]
        // It looks like SensorTag doesn't support notifications for battery level or state.  The only characteristic listed
        // for that service is 2A19. Calling setNotify and writeValue on that characteristic doesn't produce any callbacks.
        // writeValue causes the error "Writing is not permitted"
        centralManager = CBCentralManager(delegate: self, queue: nil)
    }

    func updateConnections(sysIds: [String], uuids: [String]) {
        print("updateConnections", sysIds, uuids)
        sysIdValues = sysIds
        uuidValues = uuids
        idsInitialized = true
        rejectedUUIDs.removeAll()
        if centralManager.state == CBManagerState.poweredOn {
            centralManager.scanForPeripherals(withServices: scanServiceIds, options: nil)
        }
    }

    func checkPeripheral(peripheral: CBPeripheral, systemId: Data) {
        let uuid = peripheral.identifier.uuidString
        let sysId = hexString(data: systemId)
        print("checkPeripheral", sysId)
        if let idx = uuidValues.firstIndex(of: uuid) ??
            sysIdValues.firstIndex(of: sysId) ??
            sysIdValues.firstIndex(of: "") {
            // Find a slot matched by UUID or System ID, or an empty slot
            if sysIdValues[idx] != sysId || uuidValues[idx] != uuid {
                sysIdValues[idx] = sysId
                uuidValues[idx] = uuid
                print("paired", idx, sysId, uuid)
                delegate?.didPair(systemIds: sysIdValues, uuids: uuidValues)
            }
            if sensorPeripherals[1 - idx] != nil && centralManager.isScanning {
                // Both sensors discovered
                centralManager.stopScan()
            }
            print("connected", idx, sysId, uuid)
            sensorPeripherals[idx] = peripheral
            peripheral.discoverServices(sensorServiceIds + [SensorManager.batteryUUID])
        }
        else {
            print("disconnect")
            // No need to get the disconnect callback (or anything else)
            peripheral.delegate = nil
            centralManager.cancelPeripheralConnection(peripheral)
            rejectedUUIDs.insert(uuid)
        }
        if let idx = pendingPeripherals.firstIndex(of: peripheral) {
            pendingPeripherals.remove(at: idx)
        }
    }

    func getCharacteristicUUID(serviceUUID: CBUUID, offset: UInt8) -> CBUUID {
        var data = serviceUUID.data
        // This does not modify serviceUUID
        data[3] += offset
        return CBUUID(data: data)
    }

    func toArray<T>(data: Data, count: Int) -> [T] where T: BinaryInteger {
        var array = [T](repeating: 0, count: count)
        (data as NSData).getBytes(&array, length: count * MemoryLayout<T>.size)
        // print("toArray", array, count)
        return array
    }

    func getMovementData(data: Data) -> [Float] {
        let values: [Int16] = toArray(data: data, count: 9)
        let gx = Float(values[0]) / 65536 * 500
        let gy = Float(values[1]) / 65536 * 500
        let gz = Float(values[2]) / 65536 * 500
        // Configure with bits 8:9 (0=2G, 1=4G, 2=8G, 3=16G)
        let range: Float = 2
        let ax = Float(values[3]) / 32768 * range
        let ay = Float(values[4]) / 32768 * range
        let az = Float(values[5]) / 32768 * range
        let mx = Float(values[6])
        let my = Float(values[7])
        let mz = Float(values[8])
        return [gx, gy, gz, ax, ay, az, mx, my, mz]
    }

    func getBarometerData(data: Data) -> [Float] {
        var bytes = [UInt8](repeating: 0, count: 6)
        (data as NSData).getBytes(&bytes, length: 6)
        var values: [Float] = [0, 0]
        for i in 0..<2 {
            values[i] = Float(UInt32(bytes[3 * i]) | (UInt32(bytes[3 * i + 1]) << 8) | (UInt32(bytes[3 * i + 2]) << 16)) / 100
        }
        return values
    }

    func getHumidityData(data: Data) -> [Float] {
        let values: [UInt16] = toArray(data: data, count: 2)
        let val0: Int16 = numericCast(values[0])
        let temperature = Float(val0) / 65536 * 165 - 40
        let humidity = Float(values[1] & ~0x0003) / 65536 * 100
        return [temperature, humidity]
    }

    func getLuxometerData(data: Data) -> [Float] {
        let values: [UInt16] = toArray(data: data, count: 1)
        let m = values[0] & 0x0fff;
        var e = (values[0] & 0xf000) >> 12;
        e = e == 0 ? 1 : 2 << (e - 1)
        return [Float(m) * Float(e) * 0.01]
    }

    func getBatteryData(data: Data) -> [Float] {
        let values: [UInt8] = toArray(data: data, count: 1)
        return [Float(values[0])]
    }

    func saveData() {
        print("SensorManager.saveData", collectedData.count)
        if collectedData.isEmpty {
            return
        }
        let records = collectedData
        collectedData.removeAll()
        print("saveData")
        var req = URLRequest(url: uploadDataURL)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let data: [String: Any] = ["uuid": sysIdValues[0] + "-" + sysIdValues[1],
                                   "timezone": TimeZone.current.identifier,
                                   "data": records]
        req.httpBody = try? JSONSerialization.data(withJSONObject: data, options: [])
        let task = URLSession.shared.dataTask(with: req) { data, res, err in
            guard let data = data,
                let res = res as? HTTPURLResponse,
                err == nil else {
                    print("error", err ?? "unknown")
                    return
            }
            guard res.statusCode == 200 else {
                print("status code", res.statusCode, res)
                return
            }
            print("response", String(data: data, encoding: .utf8))
        }
        task.resume()
    }

    func collectData(index: Int, data: [String: Any]) {
        var data = data
        data["id"] = sysIdValues[index]
        data["time"] = Date().timeIntervalSince1970
        collectedData.append(data)
        print("collectData", data, collectedData.count)
        if collectedData.count > 20 {
            saveData()
        }
    }

    // CBCentralManagerDelegate

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        print("didUpdateState", central.state)
        if central.state == CBManagerState.poweredOn && idsInitialized {
            // print("CB poweredOn")
            central.scanForPeripherals(withServices: scanServiceIds, options: nil)
        }
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        print("didDiscover", peripheral.name ?? "no name", peripheral.identifier, advertisementData)
        if let uuids = advertisementData["kCBAdvDataServiceUUIDs"] as? [AnyObject] {
            print(uuids)
        }
        if let idx = uuidValues.firstIndex(where: { $0 == peripheral.identifier.uuidString }) {
            // UUID is paired
            print("is paired", idx, peripheral.identifier.uuidString)
            if let p = sensorPeripherals[idx],
                p.identifier != peripheral.identifier {
                print("cancelPeripheralConnection", idx, p)
                p.delegate = nil
                sensorPeripherals[idx] = nil
                centralManager.cancelPeripheralConnection(p)
            }
            sensorPeripherals[idx] = peripheral
            peripheral.delegate = self
            print("connect", peripheral)
            central.connect(peripheral, options: nil)
        }
        else if (sensorPeripherals[0] == nil || sensorPeripherals[1] == nil) &&
            !rejectedUUIDs.contains(peripheral.identifier.uuidString) &&
            uuidValues.contains("") && advertisementData["kCBAdvDataLocalName"] as? String == "CC2650 SensorTag" {
            // Less than 2 sensors are connected, the UUID of the discovered sensor wasn't rejected,
            // there is an unpaired slot left, and the name is that of a sensor.
            // print("discovered", peripheral.identifier.uuidString, uuidValues)
            // [CoreBluetooth] API MISUSE: Cancelling connection for unused peripheral <...>, Did you forget to keep a reference to it?
            // Multiple peripherals may be discovered before the first discovered peripheral is resolved.
            print("is pending", peripheral.identifier.uuidString)
            pendingPeripherals.append(peripheral)
            peripheral.delegate = self
            // print("connect", peripheral)
            central.connect(peripheral, options: nil)
        }
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        print("didConnect", peripheral)
        if sensorPeripherals.contains(peripheral) {
            print("discoverServices", sensorServiceIds + [SensorManager.batteryUUID])
            peripheral.discoverServices(sensorServiceIds + [SensorManager.batteryUUID])
        }
        else {
            print("discoverServices", [SensorManager.deviceInfoUUID])
            peripheral.discoverServices([SensorManager.deviceInfoUUID])
        }
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        print("didFailToConnect", peripheral, error)
    }

    func centralManager(_ central: CBCentralManager, connectionEventDidOccur event: CBConnectionEvent, for peripheral: CBPeripheral) {
        print("connectionEventDidOccur", peripheral, event)
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        if let err = error {
            print("didDisconnectPeripheral", peripheral, err)
        }
        print("disconnect", peripheral)
        if let idx = sensorPeripherals.firstIndex(of: peripheral) {
            print("disconnect", idx, peripheral)
            if central.isScanning {
                central.stopScan()
            }
            sensorPeripherals[idx] = nil
            central.scanForPeripherals(withServices: scanServiceIds, options: nil)
        }
    }

    // CBPeripheralDelegate

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        if let err = error {
            print("didDiscoverServices", peripheral, err)
        }
        if pendingPeripherals.contains(peripheral) {
            if let devInfo = peripheral.services!.first(where: { $0.uuid == SensorManager.deviceInfoUUID }) {
                peripheral.discoverCharacteristics([SensorManager.systemIdUUID], for: devInfo)
            }
        }
        else {
            for service in peripheral.services! {
                peripheral.discoverCharacteristics(nil, for: service)
            }
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        if let err = error {
            print("didDiscoverCharacteristicsFor", service, err)
        }
        if pendingPeripherals.contains(peripheral) {
            if service.uuid == SensorManager.deviceInfoUUID,
                let sysId = service.characteristics!.first(where: { $0.uuid == SensorManager.systemIdUUID }) {
                peripheral.readValue(for: sysId)
            }
        }
        else if let idx = sensorPeripherals.firstIndex(of: peripheral) {
            if service.uuid == SensorManager.batteryUUID {
                batteryCharacteristic[idx] = service.characteristics!.first
            }
            else if sensorServiceIds.contains(service.uuid) {
                let dataUUID = getCharacteristicUUID(serviceUUID: service.uuid, offset: 1)
                let confUUID = getCharacteristicUUID(serviceUUID: service.uuid, offset: 2)
                for characteristic in service.characteristics! {
                    if characteristic.uuid == dataUUID {
                        peripheral.setNotifyValue(true, for: characteristic)
                    }
                    else if characteristic.uuid == confUUID {
                        let isMovement = service.uuid == SensorManager.movementUUID
                        var enableValue = isMovement ? 0x7f : 1
                        let enableBytes = NSData(bytes: &enableValue, length: isMovement ? MemoryLayout<UInt16>.size : MemoryLayout<UInt8>.size)
                        peripheral.writeValue(enableBytes as Data, for: characteristic, type: CBCharacteristicWriteType.withResponse)
                    }
                    // For changing the period, offset is 4 for barometer (AA44), 3 for everything else
                    // print(service.uuid.uuidString, characteristic.uuid.uuidString)
                }
            }
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        if let err = error {
            print("didUpdateValueFor", characteristic, err)
        }
        if let val = characteristic.value {
            // print(characteristic.service.uuid, "-", characteristic.uuid, characteristic.uuid.uuidString, "=", val as NSData)
            if pendingPeripherals.contains(peripheral) && characteristic.uuid == SensorManager.systemIdUUID {
                checkPeripheral(peripheral: peripheral, systemId: val)
            }
            else if let idx = sensorPeripherals.firstIndex(of: peripheral) {
                var values: [Float]?
                var collected: [String: Any]?
                switch characteristic.service.uuid {
                case SensorManager.movementUUID:
                    values = getMovementData(data: val)
                    if let values = values {
                        collected = ["gyroscope": Array(values[..<3]),
                                     "acceleration": Array(values[3..<6]),
                                     "magnetism": Array(values[6...])]
                    }
                case SensorManager.barometerUUID:
                    values = getBarometerData(data: val)
                case SensorManager.humidityUUID:
                    values = getHumidityData(data: val)
                    if let values = values {
                        collected = ["temperature": values[0], "humitity": values[1]]
                    }
                case SensorManager.luxometerUUID:
                    values = getLuxometerData(data: val)
                case SensorManager.batteryUUID:
                    values = getBatteryData(data: val)
                    if let values = values {
                        collected = ["battery": values[0]]
                    }
                default:
                    break
                }
                if let collected = collected {
                    collectData(index: idx, data: collected)
                }
                if let values = values {
                    print("received", idx, characteristic.service.uuid, values)
                    delegate?.receivedValues(index: idx, serviceUUID: characteristic.service.uuid, values: values)
                }
                // Update the battery level once per minute
                let now = Date()
                if let batt = batteryCharacteristic[idx],
                    now.timeIntervalSince(lastBatteryCheck[idx]) > 60 {
                    lastBatteryCheck[idx] = now
                    peripheral.readValue(for: batt)
                }
            }
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        if let err = error {
            print("didWriteValueFor", characteristic, err)
        }
    }

    // Utilities

    func hexString(data: Data) -> String {
        let hexDigits = Array("0123456789ABCDEF".utf16)
        var chars: [unichar] = []
        chars.reserveCapacity(2 * data.count)
        for byte in data {
            chars.append(hexDigits[Int(byte / 16)])
            chars.append(hexDigits[Int(byte % 16)])
        }
        return String(utf16CodeUnits: chars, count: chars.count)
    }
}
