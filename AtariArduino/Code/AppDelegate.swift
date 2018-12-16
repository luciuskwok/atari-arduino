//
//  AppDelegate.swift
//  AtariArduino
//
//  Created by Lucius Kwok on 12/12/18.
//  Copyright © 2018 Lucius Kwok. All rights reserved.
//

import Cocoa

class AppDelegate: NSObject, NSApplicationDelegate, NSMenuItemValidation {
	
	func applicationDidFinishLaunching(_ notification: Notification) {
		// Insert code here to initialize your application
		NSLog("[LK] Application did finish launching.")
		ArduinoDevice.shared.open()
	}
	
	func applicationWillTerminate(_ notification: Notification) {
		// Insert code here to tear down your application
		NSLog("[LK] Application will terminate.")
		ArduinoDevice.shared.close()
	}
	
	// MARK: -
	
	func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
		var enableItem = false
		let arduino = ArduinoDevice.shared

		switch menuItem.action {
		case #selector(toggleSerialPort(_:)): // Open/Close Serial Port
			enableItem = true
			if arduino.isOpen {
				menuItem.title = NSLocalizedString("Close Serial Port", comment:"")
			} else {
				menuItem.title = NSLocalizedString("Open Serial Port", comment:"")
			}
			
		case #selector(sendTestData(_:)): // Send Test
			enableItem = arduino.isOpen
			
		default:
			break
		}
		return enableItem
	}

	@IBAction func toggleSerialPort(_ sender: Any?) {
		let arduino = ArduinoDevice.shared
		if arduino.isOpen {
			arduino.close()
		} else {
			arduino.open()
		}
	}

	@IBAction func sendTestData(_ sender: Any?) {
		let arduino = ArduinoDevice.shared
		if arduino.isOpen {
			let string = "T"
			arduino.send(data: string.data(using: .ascii)!)
		}
	}

}
