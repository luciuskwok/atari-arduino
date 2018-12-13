//
//  DiskViewController.swift
//  AtariArduino
//
//  Created by Lucius Kwok on 12/12/18.
//  Copyright © 2018 Lucius Kwok. All rights reserved.
//

import Cocoa

class DiskViewController: NSViewController, NSTableViewDelegate, NSTableViewDataSource, NSMenuItemValidation {
	
	@IBOutlet weak var directoryTableView:NSTableView?
	@IBOutlet weak var statusLabel:NSTextField?
	var directory = [DirectoryEntry]()
	
	// MARK: -
	
	override func viewDidLoad() {
		 super.viewDidLoad()
		directoryTableView?.delegate = self
		directoryTableView?.dataSource = self
		
		let nc = NotificationCenter.default
		nc.addObserver(forName: .NSUndoManagerDidUndoChange, object: nil, queue: nil) { _ in
			self.reloadDirectory()
		}
		nc.addObserver(forName: .NSUndoManagerDidRedoChange, object: nil, queue: nil) { _ in
			self.reloadDirectory()
		}
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
			// Reload table
			directory = disk.directory()
			directoryTableView?.reloadData()
			
			// Update status label
			let diskSize = disk.size() / 1024
			let freeSectors = disk.freeSectorCount()
			switch disk.dosCode() {
			case 0:
				statusLabel?.stringValue = String(format:"Unformatted %d KB disk", diskSize)
			case 2:
				statusLabel?.stringValue = String(format:"%d sectors free, %d KB disk", freeSectors, diskSize)
			default:
				statusLabel?.stringValue = String(format:"Unsupported %d KB disk", diskSize)
			}
		}
	}
	
	// MARK: - Table
	
	func numberOfRows(in tableView: NSTableView) -> Int {
		return directory.count
	}
	
	func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
		let entry = directory[row]
		var text:String = ""
		
		switch tableColumn!.identifier.rawValue {
		case "flags":
			if entry.isLocked() {
				text = "🔒"
			}
		case "filename":
			text = entry.filenameWithExtension()
		case "size":
			text = String(format:"%u", entry.length)
		default:
			break;
		}
		
		if let cellView = tableView.makeView(withIdentifier: tableColumn!.identifier, owner: nil) as? NSTableCellView {
			cellView.textField?.stringValue = text
			return cellView
		}
		return nil
	}
	
	// MARK: - IBActions
	
	@IBAction func didRenameItem(_ sender:Any?) {
		if let field = sender as? NSTextField, let disk = diskImage() {
			let row = directoryTableView!.selectedRow
			if row != NSNotFound {
				var entry = directory[row]
				entry.setFilenameWithExtension(field.stringValue)
				// Setting the filename will also apply constraints to the filename.ext, so make sure that those constraints didn't result in an empty filename
				if entry.filename.count > 0 {
					disk.undoManager?.setActionName(NSLocalizedString("Rename", comment:""))
					directory[row] = entry
					disk.updateDirectory(entry: entry, at: entry.index)
				}
				// Reload here because the text field might need to be reset to actual value after editing.
				reloadDirectory()
			}
		}
	}
	
	@IBAction func toggleItemLock(_ sender:Any?) {
		let selectedRows = directoryTableView!.selectedRowIndexes
		if selectedRows.count > 0, let disk = diskImage() {
			let firstSelectedRow = directoryTableView!.selectedRowIndexes.first!
			let newLockState = !directory[firstSelectedRow].isLocked()
			if (newLockState) {
				disk.undoManager?.setActionName(NSLocalizedString("Lock", comment:""))
			} else {
				disk.undoManager?.setActionName(NSLocalizedString("Unlock", comment:""))
			}
			for row in directoryTableView!.selectedRowIndexes {
				var entry = directory[row]
				entry.setLocked(newLockState)
				directory[row] = entry
				disk.updateDirectory(entry: entry, at: entry.index)
			}
			reloadDirectory()
		}
	}

	@IBAction func renameItem(_ sender:Any?) {
		let row = directoryTableView!.selectedRow
		if row != NSNotFound {
			directoryTableView?.editColumn(1, row: row, with: nil, select: true)
		}
	}
	
	func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
		var enableItem = false
		let selection = directoryTableView!.selectedRowIndexes
		
		switch menuItem.action {
		case #selector(toggleItemLock(_:)): // Lock/Unlock
			if let row = selection.first {
				let entry = directory[row]
				if entry.isLocked() {
					menuItem.title = NSLocalizedString("Unlock", comment:"")
				} else {
					menuItem.title = NSLocalizedString("Lock", comment:"")
				}
				enableItem = true
			}
			
		case #selector(renameItem(_:)): // Rename
			enableItem = (selection.count == 1)
			
		default:
			break
		}
		return enableItem
	}
	
	
}
