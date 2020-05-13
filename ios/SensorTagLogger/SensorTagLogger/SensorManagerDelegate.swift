//
//  SensorManagerDelegate.swift
//  SensorTagLogger
//
//  Created by Andreas Girgensohn on 5/13/20.
//  Copyright © 2020 Andreas Girgensohn. All rights reserved.
//

import CoreBluetooth

protocol SensorManagerDelegate: AnyObject {
    func didPair(systemIds: [String], uuids: [String])

    func receivedValues(index: Int, serviceUUID: CBUUID, values: [Float])
}
