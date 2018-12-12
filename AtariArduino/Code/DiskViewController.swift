//
//  DiskViewController.swift
//  AtariArduino
//
//  Created by Lucius Kwok on 12/12/18.
//  Copyright © 2018 Lucius Kwok. All rights reserved.
//

import Cocoa

class DiskViewController: NSViewController, NSTableViewDelegate, NSTableViewDataSource {
	
	@IBOutlet weak var directoryTableView:NSTableView?
	@IBOutlet weak var statusLabel:NSTextField?
	var directory = [DirectoryEntry]()
	
	// MARK: -
	
	override func viewDidLoad() {
		 super.viewDidLoad()
		directoryTableView?.delegate = self
		directoryTableView?.dataSource = self
	}
	
	override func viewWillAppear() {
		super.viewWillAppear()
		reloadDirectory()
	}
	
	// MARK: - Document
	
	func diskImage() -> AtariDiskImage? {
		if let window = view.window {
			if let disk = NSDocumentController.shared.document(for: window) as? AtariDiskImage {
				return disk
			}
		}
		return nil
	}
	
	func reloadDirectory() {
		if let disk = diskImage() {
			directory = disk.directory()
			
		}
	}
	
	
	@IBAction func toggleItemLock(_ sender:Any?) {
		
	}

	
}
