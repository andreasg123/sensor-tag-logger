//
//  SensorViewController.swift
//  SensorTagLogger
//
//  Created by Andreas Girgensohn on 5/13/20.
//  Copyright © 2020 Andreas Girgensohn. All rights reserved.
//

import CoreBluetooth
import UIKit

class SensorViewController: UIViewController, UITableViewDataSource, SensorManagerDelegate {
    @IBOutlet weak var tableView: UITableView!
    var sensorMgr: SensorManager?
    let rowLabels = ["Gyroscope", "Accelerometer", "Magnetometer", "Humidity", "Barometer", "Luxometer", "Battery", "System ID"]
    var cellValues: [[String]]!
    let sysIdKeys = ["left_system_id", "right_system_id"]
    let uuidKeys = ["left_uuid", "right_uuid"]
    var sysIdValues = ["", ""]
    var uuidValues = ["", "",]
    var leftSystemId: String?
    var rightSystemId: String?
    var leftUuid: String?
    var rightUuid: String?

    @objc func defaultsChanged() {
        for i in 0..<sysIdKeys.count {
            sysIdValues[i] = (UserDefaults.standard.string(forKey: sysIdKeys[i]) ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .uppercased()
            uuidValues[i] = (UserDefaults.standard.string(forKey: uuidKeys[i]) ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .uppercased()
            if sysIdValues[i].isEmpty && !uuidValues[i].isEmpty {
                // Clear UUID if system ID is empty
                uuidValues[i] = ""
                UserDefaults.standard.set("", forKey: uuidKeys[i])
            }
            cellValues[7][i] = sysIdValues[i]
        }
        if let mgr = sensorMgr {
            mgr.updateConnections(sysIds: sysIdValues, uuids: uuidValues)
        }
    }

    // SensorManagerDelegate

    func didPair(systemIds: [String], uuids: [String]) {
        for i in 0..<systemIds.count {
            sysIdValues[i] = systemIds[i]
            uuidValues[i] = uuids[i]
            UserDefaults.standard.set(systemIds[i], forKey: sysIdKeys[i])
            UserDefaults.standard.set(uuids[i], forKey: uuidKeys[i])
            cellValues[7][i] = systemIds[i]
        }
    }

    func receivedValues(index: Int, serviceUUID: CBUUID, values: [Float]) {
        // print("receivedValues", index, serviceUUID, values)
        switch serviceUUID {
        case SensorManager.movementUUID:
            for i in 0..<3 {
                cellValues[i][index] = String(format: i == 0 ? "%.2f, %.2f, %.2f" : i == 1 ? "%.3f, %.3f, %.3f" : "%.0f, %.0f, %.0f",
                                              values[3 * i], values[3 * i + 1], values[3 * i + 2])
            }
        case SensorManager.humidityUUID:
            cellValues[3][index] = String(format: "%.2f, %.2f", values[0], values[1])
        case SensorManager.barometerUUID:
            cellValues[4][index] = String(format: "%.2f, %.0f", values[0], values[1])
        case SensorManager.luxometerUUID:
            cellValues[5][index] = String(format: "%.3f", values[0])
        case SensorManager.batteryUUID:
            cellValues[6][index] = String(format: "%.0f%%", values[0])
        default:
            break
        }
        tableView.reloadData()
    }

    func saveData() {
        print("SensorViewController.saveData")
        sensorMgr?.saveData()
    }

    // UIViewController

    override func viewDidLoad() {
        super.viewDidLoad()
        cellValues = [[String]](repeating: ["", ""], count: rowLabels.count)
        tableView.dataSource = self
        sensorMgr = SensorManager()
        sensorMgr?.delegate = self
        defaultsChanged()
    }

    // UITableViewDataSource

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return rowLabels.count;
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "sensorCell", for: indexPath) as! SensorTableViewCell
        cell.tagLabel.text = rowLabels[indexPath.row]
        cell.leftValueLabel.text = cellValues[indexPath.row][0]
        cell.rightValueLabel.text = cellValues[indexPath.row][1]
        return cell
    }
}
