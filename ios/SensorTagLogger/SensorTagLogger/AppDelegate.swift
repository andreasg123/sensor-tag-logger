//
//  AppDelegate.swift
//  SensorTagLogger
//
//  Created by Andreas Girgensohn on 5/13/20.
//  Copyright © 2020 Andreas Girgensohn. All rights reserved.
//

import UIKit

@UIApplicationMain
class AppDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?

    func applicationWillTerminate(_ application: UIApplication) {
        if let sensorViewController = window?.rootViewController as? SensorViewController {
            sensorViewController.saveData()
        }
        else if let navController = window?.rootViewController as? UINavigationController,
            let sensorViewController = navController.topViewController as? SensorViewController {
            sensorViewController.saveData()
        }
    }
}

