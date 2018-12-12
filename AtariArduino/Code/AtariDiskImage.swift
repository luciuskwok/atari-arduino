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
	
	// MARK: - I/O

	func sector(number:Int) -> Data? {
		if number == 0 || mainSectorSize == 0 || number > sectors.count {
			return nil
		}
		return sectors[number - 1]
	}
	
	func writeSector(number:Int, data:Data) -> Bool {
		if number == 0 || mainSectorSize == 0 || number > sectors.count {
			return false
		}
		sectors[number - 1] = data
		return true
	}

	func directory() -> [DirectoryEntry] {
		// Make sure the disk image is large enough for Atari DOS directory structure.
		if mainSectorSize == 0 || sectors.count < 368 {
			return []
		}
		
		let dirSectorStart = 361
		var dir = [DirectoryEntry]()
		for dirSectorOffset in 0..<8 {
			if let sectorData = sector(number: dirSectorStart + dirSectorOffset) {
				for entryIndex in 0..<8 {
					// Add directory entries that are not unused or deleted
					let offset = entryIndex * 16
					let entryData = sectorData.subdata(in: offset..<offset+16)
					let flags = entryData[0]
					if (flags & 0x80) == 0 && (flags & 0x40) != 0 {
						var entry = DirectoryEntry()
						entry.index = entryIndex + 8 * dirSectorOffset
						entry.flags = flags
						entry.length = UInt16(entryData[1]) + 256 * UInt16(entryData[2])
						entry.start = UInt16(entryData[3]) + 256 * UInt16(entryData[4])
						entry.setFilenameAndExtension(data: entryData.subdata(in: 5..<16))
						dir.append(entry)
					} // end if (flags)
				} // end for (entryIndex)
			} // end if (sectorData)
		} // end for (dirSectorOffset)
		return dir
	}
	
	
}
