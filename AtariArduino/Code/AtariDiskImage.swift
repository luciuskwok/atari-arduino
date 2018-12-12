//
//  AtariDiskImage.swift
//  AtariArduino
//
//  Created by Lucius Kwok on 12/12/18.
//  Copyright © 2018 Lucius Kwok. All rights reserved.
//

import AppKit

class AtariDiskImage: NSDocument {
	var bootSectorSize = 128
	var mainSectorSize = 128
	var sectors = [Data]()

	let directoryStartSectorNumber = 361

	// MARK: -
	
	override init() {
		var newSectors = [Data]()
		for _ in 0..<720 {
			newSectors.append(Data(count:128))
		}
		sectors = newSectors
	}
	
	override class var autosavesInPlace:Bool {
		return true
	}
	
	override func makeWindowControllers() {
		let wc = NSStoryboard(name: "Main", bundle: nil).instantiateController(withIdentifier: "Document Window Controller")
		addWindowController(wc as! NSWindowController)
	}
	
	// MARK: - Mac I/O
	
	override func data(ofType typeName: String) throws -> Data {
		// TODO
		return Data()
	}
	
	override func read(from data: Data, ofType typeName: String) throws {
		// Ensure file size is at least as large as header
		let fileSize = data.count
		if fileSize <= 16 {
			throw error(code:NSFileReadCorruptFileError)
		}
		
		// Magic word in file header
		let magic:UInt16 = UInt16(data[0]) + 256 * UInt16(data[1])
		if magic != 0x0296 {
			throw error(code:NSFileReadCorruptFileError)
		}
		
		// Ensure file size is at least as large as diskSize in header
		let diskSizeInParagraphs:UInt16 = UInt16(data[2]) + 256 * UInt16(data[3])
		let diskSize =  UInt(diskSizeInParagraphs) * 16
		if diskSize + 16 > fileSize {
			throw error(code:NSFileReadCorruptFileError)
		}

		// Sector size
		mainSectorSize = Int(data[4]) + 256 * Int(data[5])
		if mainSectorSize == 0 {
			throw error(code:NSFileReadCorruptFileError)
		}
		
		// Divide the disk image data up into sectors
		var sectorArray = [Data]()
		
		// Boot sectors are always 128 bytes
		var offset:Int
		for index in 0..<3 {
			offset = 16 + index * bootSectorSize
			let bootSectorData = data.subdata(in: offset..<offset+bootSectorSize)
			sectorArray.append(bootSectorData)
		}
		
		// Main sectors are usually 128 or 256 bytes
		offset = 16 + 3 * 128
		while offset + mainSectorSize <= data.count {
			let sectorData = data.subdata(in: offset..<offset+mainSectorSize)
			sectorArray.append(sectorData)
			offset += mainSectorSize
		}
		
		// Keep the sector data
		sectors = sectorArray
		NSLog("Read \(sectors.count) sectors")
	}
	
	func error(code:Int) -> NSError {
		return NSError(domain: NSCocoaErrorDomain, code: code, userInfo: nil)
	}
	
	// MARK: - Atari I/O

	func sector(number:Int) -> Data? {
		if number == 0 || number > sectors.count {
			NSLog("[LK] Invalid disk sector number")
			return nil
		}
		return sectors[number - 1]
	}
	
	func writeSector(number:Int, data:Data) {
		if number == 0 || number > sectors.count {
			NSLog("[LK] Invalid disk sector number")
		} else {
			sectors[number - 1] = data
		}
	}

	func directory() -> [DirectoryEntry] {
		// Make sure the disk image is large enough for Atari DOS directory structure.
		if isDos2FormatDisk() == false {
			return []
		}
		
		var dir = [DirectoryEntry]()
		for dirSectorOffset in 0..<8 {
			if let sectorData = sector(number: directoryStartSectorNumber + dirSectorOffset) {
				for entryIndex in 0..<8 {
					// Add directory entries that are not unused or deleted
					let offset = entryIndex * 16
					let entryData = sectorData.subdata(in: offset..<offset+16)
					let flags = entryData[0]
					if (flags & 0x80) == 0 && (flags & 0x40) != 0 {
						let entry = DirectoryEntry(atariData:entryData, index:entryIndex + 8 * dirSectorOffset)
						dir.append(entry)
					} // end if (flags)
				} // end for (entryIndex)
			} // end if (sectorData)
		} // end for (dirSectorOffset)
		return dir
	}
	
	func updateDirectory(entry:DirectoryEntry, at index:Int) {
		// Make sure the disk image is large enough for Atari DOS directory structure.
		if isDos2FormatDisk() == false {
			return
		}
		
		let sectorNumber = directoryStartSectorNumber + index / 8
		let byteOffset = index % 8 * 16
		if var sectorData = sector(number:sectorNumber) {
			sectorData.replaceSubrange(byteOffset..<byteOffset+16, with: entry.atariData())
			writeSector(number:sectorNumber, data:sectorData)
		}
	}

	// MARK: - Stats
	
	func isDos2FormatDisk() -> Bool {
		// Returns YES if the dosCode in the VTOC is 2, indicating a DOS 2.x-compatible disk.
		if mainSectorSize == 0 || sectors.count < directoryStartSectorNumber + 8 {
			return false
		}
		var dosCode:UInt8 = 0
		if let vtoc = sector(number:360) {
			dosCode = vtoc[0];
		}
		return dosCode == 2
	}
	
	func size() -> Int {
		var result = 0
		for sector in sectors {
			result += sector.count
		}
		return result
	}
	
	func freeSectorCount() -> Int {
		// This func only works with DOS 2.x format disks, and not with MyDos or other formats.
		if isDos2FormatDisk() == false {
			return 0
		}
		
		var count = 0
		// Get the free sector count from the VTOC at sector 360
		if let vtoc = sector(number:360) {
			count = Int(vtoc[3]) + 256 * Int(vtoc[4])
			
			// Special case for DOS 2.5 with 1050 double density disks: add the free sectors from VTOC2 at sector 1024.
			if sectors.count >= 1024 {
				if let vtoc2 = sector(number:1024) {
					count += Int(vtoc2[122]) + 256 * Int(vtoc2[123])
				}
			}
		}
		return count
	}

	
}
