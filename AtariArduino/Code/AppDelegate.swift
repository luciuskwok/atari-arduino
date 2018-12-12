//
//  AppDelegate.swift
//  AtariArduino
//
//  Created by Lucius Kwok on 12/12/18.
//  Copyright © 2018 Lucius Kwok. All rights reserved.
//

import Cocoa

class AppDelegate: NSObject, NSApplicationDelegate {
	
	func applicationDidFinishLaunching(_ notification: Notification) {
		// Insert code here to initialize your application
		NSLog("[LK] Application did finish launching.")
	}
	
	func applicationWillTerminate(_ notification: Notification) {
		// Insert code here to tear down your application
		NSLog("[LK] Application will terminate.")
	}

}
