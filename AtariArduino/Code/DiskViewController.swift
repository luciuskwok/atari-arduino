//
//  DiskViewController.swift
//  AtariArduino
//
//  Created by Lucius Kwok on 12/12/18.
//  Copyright © 2018 Lucius Kwok. All rights reserved.
//

import Cocoa

class DiskViewController: NSViewController, NSTableViewDelegate, NSTableViewDataSource, NSMenuItemValidation {
	// IBOutlets
	@IBOutlet weak var directoryTableView:NSTableView?
	@IBOutlet weak var statusLabel:NSTextField?
	
	// Variables
	var directory = [DirectoryEntry]()
	
	// Constants
	let acceptableDragTypes:[NSPasteboard.PasteboardType] = [.filePromise, .fileURL]
	
	// MARK: -
	
	override func viewDidLoad() {
		 super.viewDidLoad()
		
		if let tv = directoryTableView {
			tv.delegate = self
			tv.dataSource = self
			tv.doubleAction = #selector(renameItem(_:))
			tv.registerForDraggedTypes(acceptableDragTypes)
			tv.setDraggingSourceOperationMask(.copy, forLocal: false) // Allow copying out of app.
			tv.draggingDestinationFeedbackStyle = .none
		}
		
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
				statusLabel?.stringValue = String(format:"%d free sectors, %d KB disk", freeSectors, diskSize)
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
			text = entry.filename
		case "size":
			text = String(format:"%u", entry.length)
		default:
			break
		}
		
		if let cellView = tableView.makeView(withIdentifier: tableColumn!.identifier, owner: nil) as? NSTableCellView {
			cellView.textField?.stringValue = text
			return cellView
		}
		return nil
	}
	
	func tableView(_ tableView: NSTableView, writeRowsWith rowIndexes: IndexSet, to pboard: NSPasteboard) -> Bool {
		var fileExtensions = [String]()
		for _ in rowIndexes {
			fileExtensions.append("bin")
		}
		if fileExtensions.count > 0 {
			pboard.setPropertyList(fileExtensions, forType: .filePromise)
		}
		return fileExtensions.count > 0
	}
	
	func tableView(_ tableView: NSTableView, namesOfPromisedFilesDroppedAtDestination dropDestination: URL, forDraggedRowsWith rowIndexes: IndexSet) -> [String] {
		var filenames = [String]()
		if let disk = diskImage() {
			for row in rowIndexes {
				// Write files to disk
				let entry = directory[row]
				let path = dropDestination.appendingPathComponent(entry.filename)
				if let fileContents = disk.fileContents(startingSectorNumber: Int(entry.start), fileNumber: entry.fileNumber) {
					do {
						try fileContents.write(to: path)
						filenames.append(entry.filename)
					} catch {
						NSLog("[LK] Error writing file to disk.")
					}
				}
			}
		}
		return filenames
	}
	
	func tableView(_ tableView:NSTableView, validateDrop info:NSDraggingInfo, proposedRow row:Int, proposedDropOperation dropOperation: NSTableView.DropOperation) -> NSDragOperation {
		
		//NSLog("[LK] Validate drop.")
		
		// Hide the highlight of the row or space between rows.
		tableView.setDropRow(-1, dropOperation: dropOperation)
		
		// Only allow drops onto formatted DOS 2.x disks with free sectors
		var allowOperation = false
		if let disk = diskImage() {
			allowOperation = disk.isDos2FormatDisk() && disk.freeSectorCount() > 0
		}
		return allowOperation ? NSDragOperation.copy : []
	}
	
	func tableView(_ tableView: NSTableView, acceptDrop info: NSDraggingInfo, row: Int, dropOperation: NSTableView.DropOperation) -> Bool {
		
		let board = info.draggingPasteboard
		if let dropTypes = board.types {
			if dropTypes.contains(.fileURL) {
				if let fileURLs = board.readObjects(forClasses: [NSURL.self], options: nil) as? [URL] {
					//NSLog("[LK] Pasteboard returned files \(fileURLs)")
					return add(files:fileURLs)
				} else {
					NSLog("[LK] Pasteboard returned nil data for the fileURL type")
				}
			} else if dropTypes.contains(.filePromise) {
				NSLog("[LK] Dropped a file promise")
			} else {
				NSLog("[LK] Unknown items dropped")
			}
		}
		
		//NSLog("[LK] Accept drop.")
		return false
	}
	
	func add(files:[URL]) -> Bool {
		var success = false
		if let disk = diskImage() {
			for file in files {
				do {
					let fileData = try Data(contentsOf: file, options: [.alwaysMapped])
					
					// Check if file will fit
					let bytesAvailable = disk.bytesAvailable()
					if fileData.count > bytesAvailable {
						NSLog("[LK] Not enough sectors available.")
					} else {
						// Write file to disk image
						if disk.addFile(name:file.lastPathComponent, data: fileData) {
							success = true
						}
					}
				} catch {
					NSLog("[LK] Error reading file.")
				}
			}
		}
		return success
	}
	
	// MARK: - IBActions
	
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
				disk.updateDirectory(entry: entry, at: entry.fileNumber)
			}
			reloadDirectory()
		}
	}

	@IBAction func renameItem(_ sender:Any?) {
		let row = directoryTableView!.selectedRow
		if 0 <= row && row < directory.count {
			directoryTableView?.editColumn(1, row: row, with: nil, select: true)
		}
	}
	
	@IBAction func didRenameItem(_ sender:Any?) {
		if let field = sender as? NSTextField, let disk = diskImage() {
			let row = directoryTableView!.selectedRow
			if row != NSNotFound {
				var entry = directory[row]
				entry.filename = field.stringValue
				// Setting the filename will also apply constraints to the filename.ext, so make sure that those constraints didn't result in an empty filename
				if entry.filename.count > 0 {
					disk.undoManager?.setActionName(NSLocalizedString("Rename", comment:""))
					directory[row] = entry
					disk.updateDirectory(entry: entry, at: entry.fileNumber)
				}
				// Reload here because the text field might need to be reset to actual value after editing.
				reloadDirectory()
			}
		}
	}

	@IBAction func delete(_ sender:Any?) {
		let selectedRows = directoryTableView!.selectedRowIndexes
		if selectedRows.count > 0, let disk = diskImage() {
			for row in selectedRows {
				let entry = directory[row]
				if entry.isLocked() == false {
					disk.delete(fileNumber: entry.fileNumber)
				}
			}
			reloadDirectory()
		}
	}

	func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
		var enableItem = false
		let selection = directoryTableView!.selectedRowIndexes
		var firstItemLocked = true
		if let row = selection.first {
			firstItemLocked = directory[row].isLocked()
		}
		
		switch menuItem.action {
		case #selector(toggleItemLock(_:)): // Lock/Unlock
			if selection.count > 0 {
				if firstItemLocked {
					menuItem.title = NSLocalizedString("Unlock", comment:"")
				} else {
					menuItem.title = NSLocalizedString("Lock", comment:"")
				}
				enableItem = true
			}
			
		case #selector(renameItem(_:)): // Rename
			if selection.count == 1 {
				enableItem = !firstItemLocked
			}
			
		case #selector(delete(_:)): // Delete
			if selection.count > 0 {
				// Only allow delete if at least 1 item is unlocked
				for row in selection {
					if directory[row].isLocked() == false {
						enableItem = true
					}
				}
			}
			
		default:
			break
		}
		return enableItem
	}
	
	
}
