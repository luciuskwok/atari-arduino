//
//  AtariDiskImage.swift
//  AtariArduino
//
//  Created by Lucius Kwok on 12/12/18.
//  Copyright © 2018 Lucius Kwok. All rights reserved.
//

import AppKit

class AtariDiskImage: NSDocument {
	// Variables
	var mainSectorSize = 128
	var sectors = [Data]()
	
	// Constants
	let bootSectorSize = 128
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
		var outData = Data(capacity: 1040 * 128)
		
		// == Header ==
		// Magic word 0x0296
		outData.append(0x96)
		outData.append(0x02)
		
		// Disk size divided by 16
		let diskSizeInParagraphs = size() / 16
		outData.append(UInt8(diskSizeInParagraphs % 256))
		outData.append(UInt8(diskSizeInParagraphs / 256))
		
		// Sector size
		outData.append(UInt8(mainSectorSize % 256))
		outData.append(UInt8(mainSectorSize / 256))
		
		// Pad out header to 16 bytes
		outData.count = 16
		
		// == Sector Data ==
		for sectorData in sectors {
			outData.append(sectorData)
		}

		//throw NSError(domain: NSCocoaErrorDomain, code: NSFileWriteUnknownError, userInfo: nil)
		return outData
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
			let originalData = sectors[number - 1]
			undoManager?.registerUndo(withTarget: self, handler: { $0.writeSector(number:number, data:originalData) })
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
						let entry = DirectoryEntry(atariData:entryData, fileNumber:entryIndex + 8 * dirSectorOffset)
						dir.append(entry)
					} // end if (flags)
				} // end for (entryIndex)
			} // end if (sectorData)
		} // end for (dirSectorOffset)
		return dir
	}
	
	func directoryEntry(at index:Int) -> Data? {
		var entryData: Data?
		if let sectorData = sector(number:directoryStartSectorNumber + index / 8) {
			let byteOffset = index % 8 * 16
			entryData = sectorData.subdata(in: byteOffset..<byteOffset+16)
		}
		return entryData
	}
	
	func writeDirectory(entry:DirectoryEntry, at index:Int) {
		// Make sure the disk image is large enough for Atari DOS directory structure.
		if isDos2FormatDisk() == false {
			return
		}
		
		let sectorNumber = directoryStartSectorNumber + index / 8
		let byteOffset = index % 8 * 16
		if let originalSectorData = sector(number:sectorNumber) {
			var modifiedSectorData = originalSectorData
			modifiedSectorData.replaceSubrange(byteOffset..<byteOffset+16, with: entry.atariData())
			writeSector(number:sectorNumber, data:modifiedSectorData)
		}
	}
	
	func tailInfo(sectorData:Data) -> (fileNumber:Int, nextSector:Int, length:Int) {
		let end = sectorData.count - 1
		let fileNo = Int(sectorData[end - 2] & 0xFC) / 4
		let next = Int(sectorData[end - 1]) + 256 * Int(sectorData[end - 2] & 0x03)
		let len = Int(sectorData[end])
		return (fileNo, next, len)
	}
	
	func fileContents(startingSectorNumber: Int, fileNumber: Int) -> Data? {
		if isDos2FormatDisk() == false {
			return nil
		}

		var fileData = Data()
		var sectorNumber = startingSectorNumber
		while sectorNumber != 0 {
			if let sectorData = sector(number:sectorNumber) {
				let (validation, next, length) = tailInfo(sectorData: sectorData)
				if validation == fileNumber {
					fileData.append(sectorData.subdata(in: 0..<length))
					sectorNumber = next
				} else {
					NSLog("[LK] File number mismatch.")
					return nil
				}
			} else {
				NSLog("[LK] Invalid sector number.")
				return nil
			}
		}
		return fileData
	}
	
	func delete(fileNumber:Int) {
		if isDos2FormatDisk() == false {
			return
		}
		
		if let entryData = directoryEntry(at: fileNumber) {
			// Validate flags
			let flags = entryData[0]
			if flags != 0x42 && flags != 0x03 {
				NSLog("[LK] File is not valid.")
				return
			}

			// Walk through file to determine which sectors to free
			var entry = DirectoryEntry(atariData: entryData, fileNumber: fileNumber)
			var sectorNumber = Int(entry.start)
			var sectorsToFree = IndexSet()
			while sectorNumber != 0 {
				
				if let sectorData = sector(number:sectorNumber) {
					let (validation, next, _) = tailInfo(sectorData: sectorData)
					if (fileNumber != validation) {
						NSLog("[LK] File number mismatch.")
						return
					} else {
						sectorsToFree.insert(sectorNumber)
						sectorNumber = next
					}
				} else {
					NSLog("[LK] Invalid sector number.")
					return
				}
			}

			// Update the VTOC and directory only after making sure every sector matches the file to be deleted
			if sectorsToFree.count > 0 {
				// Mark directory entry as deleted
				entry.flags = 0x80
				writeDirectory(entry: entry, at: fileNumber)
				
				// Write updated VTOC
				var freeSectors = freeSectorsFromVTOC()
				for n in sectorsToFree {
					freeSectors.insert(n)
				}
				writeVTOC(freeSectors: freeSectors)
			}

			NSLog("[LK] Freed \(sectorsToFree.count) sectors.")
		}
	}
	
	func addFile(name:String, contents data:Data) -> Bool {
		if isDos2FormatDisk() == false  {
			return false;
		}
		
		NSLog("[LK] Adding file \(name), length \(data.count)")
		
		// Find an available file number
		let fileNumber = availableFileNumber()
		if fileNumber == -1 {
			NSLog("[LK] Directory full")
			return false
		}
		let shiftedFileNumber = UInt8(fileNumber) << 2
		
		// Convert the name into a 8.3 filename that is unique
		var filenameData = DirectoryEntry.atariData(filename: name)
		var extIndex = 1
		while findFile(named: filenameData) != -1 {
			let extData = DirectoryEntry.paddedData(string: String(format:"%03d", extIndex), length: 3)
			filenameData.replaceSubrange(8..<11, with: extData)
			extIndex += 1
		}
		
		// Get the volume bitmap from the VTOC and check available space
		var freeSectorSet = freeSectorsFromVTOC()
		let maxSectorDataSize = mainSectorSize - 3
		let bytesAvailable = freeSectorSet.count * maxSectorDataSize
		if data.count > bytesAvailable {
			NSLog("[LK] Insufficient space available")
			return false
		}
		
		// Convert the freeSectorSet into a sorted array so that sectors are used in order
		var sortedFreeSectors = freeSectorSet.sorted()
		let startSectorNumber = sortedFreeSectors.first!
		
		// Write the file to sectors
		var dataIndex = 0
		var sectorsUsed = 0
		while dataIndex < data.count {
			// Calculate logical sector size (the number of bytes of data the belongs to the file) as the smaller of the remaining length of data and the maximum number of bytes of data per sector, typically 127 for single density.
			let logicalSize = min(data.count - dataIndex, maxSectorDataSize)
			let sectorNumber = sortedFreeSectors.first!
			
			// Set the next sector link if there is more data and there are any more free sectors left
			var nextSector = 0
			if sortedFreeSectors.count >= 2 && dataIndex + logicalSize < data.count {
				nextSector = sortedFreeSectors[1]
			}
			
			// Create a sector with data, file number, next sector link, and logical size
			var sectorData = data.subdata(in: dataIndex..<dataIndex+logicalSize)
			if sectorData.count < maxSectorDataSize {
				sectorData.count = maxSectorDataSize
			}
			
			// File number and next sector link share bits, so mash them together
			sectorData.append(shiftedFileNumber | UInt8(nextSector / 256))
			sectorData.append(UInt8(nextSector % 256))
			
			// Last byte is the logical size of the sector
			sectorData.append(UInt8(logicalSize))

			writeSector(number: sectorNumber, data: sectorData)
			
			// Remove sector from free sector set and array
			freeSectorSet.remove(sectorNumber)
			sortedFreeSectors.removeFirst()
			
			// Increment indexes
			dataIndex += logicalSize
			sectorsUsed += 1
		}
		
		// Update the VTOC bitmap
		writeVTOC(freeSectors: freeSectorSet)
		
		// Write the directory entry
		var entry = DirectoryEntry()
		entry.fileNumber = fileNumber
		entry.flags = 0x42
		entry.length = UInt16(sectorsUsed)
		entry.start = UInt16(startSectorNumber)
		entry.filename = DirectoryEntry.filename(atariData: filenameData)
		writeDirectory(entry: entry, at: fileNumber)
		
		return true
	}
	
	func availableFileNumber() -> Int {
		var fileNumber = 0
		for sectorIndex in 0..<8 {
			let sectorData = sector(number: directoryStartSectorNumber + sectorIndex)!
			for entry in 0..<8 {
				let flag = sectorData[entry * 16]
				if flag == 0x80 || flag == 0 {
					return fileNumber
				}
				fileNumber += 1
			}
		}
		return -1
	}
	
	func findFile(named name:Data) -> Int {
		var fileNumber = 0
		for sectorIndex in 0..<8 {
			let sectorData = sector(number: directoryStartSectorNumber + sectorIndex)!
			for entry in 0..<8 {
				let offset = entry * 16
				let entryData = sectorData.subdata(in: offset ..< offset + 16)
				let flags = entryData[0]
				if flags != 0 && flags != 0x80 {
					let entryFilename = entryData.subdata(in: 5 ..< 16)
					if name == entryFilename {
						return fileNumber
					}
				}
				fileNumber += 1
			}
		}
		return -1
	}
	

	// MARK: - Stats
	
	func dosCode() -> UInt8 {
		var dosCode:UInt8 = 0
		if mainSectorSize > 0 && sectors.count >= directoryStartSectorNumber + 8 {
			if let vtoc = sector(number:360) {
				dosCode = vtoc[0]
			}
		}
		return dosCode
	}
	
	func isDos2FormatDisk() -> Bool {
		// Returns YES if the dosCode in the VTOC is 2, indicating a DOS 2.x-compatible disk.
		return dosCode() == 2
	}
	
	func size() -> Int {
		var result = 0
		for sector in sectors {
			result += sector.count
		}
		return result
	}
	
	func bytesAvailable() -> Int {
		let freeSectors = freeSectorCount()
		return freeSectors * 125
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
	
	func freeSectorsFromVTOC() -> IndexSet {
		var freeSectors = IndexSet()
		if isDos2FormatDisk() {
			var sectorNumber = 0
			
			if let vtoc = sector(number:360) {
				for index in 10...99 {
					let byte = vtoc[index]
					for bit in 0..<8 {
						if (byte & (0x80 >> bit)) != 0 {
							freeSectors.insert(sectorNumber)
						}
						sectorNumber += 1
					}
				}
			}
			
			if sectors.count >= 1024 {
				if let vtoc2 = sector(number:1024) {
					for index in 84...121 {
						let byte = vtoc2[index]
						for bit in 0..<8 {
							if (byte & (0x80 >> bit)) != 0 {
								freeSectors.insert(sectorNumber)
							}
							sectorNumber += 1
						}
					}
				}
			}
		}
		
		return freeSectors;
	}
	
	func writeVTOC(freeSectors:IndexSet) {
		if isDos2FormatDisk() == false {
			NSLog("[LK] Cannot update a disk that not DOS 2.x")
			return
		}
		
		var lowerFreeSectorCount = 0
		var upperFreeSectorCount = 0
		for n in freeSectors {
			if n < 720 {
				lowerFreeSectorCount += 1
			} else {
				upperFreeSectorCount += 1
			}
		}
		
		// VTOC (DOS 2.0 and 2.5)
		var vtoc = sector(number: 360)!
		vtoc[3] = UInt8(lowerFreeSectorCount % 256)
		vtoc[4] = UInt8(lowerFreeSectorCount / 256)
		for index in 0..<90 { // Compress IndexSet into bitmap
			var byte = UInt8(0)
			for bit in 0..<8 {
				if freeSectors.contains(index * 8 + bit) {
					byte = byte | (0x80 >> bit)
				}
				vtoc[10 + index] = byte
			}
		}
		for index in 100...127 { // Zero out unused bytes
			vtoc[index] = 0
		}
		writeSector(number: 360, data: vtoc)

		// VTOC2 (DOS 2.5 on Enhanced Density)
		if sectors.count >= 1024 {
			var vtoc2 = sector(number: 1024)!
			vtoc2[122] = UInt8(upperFreeSectorCount % 256)
			vtoc2[123] = UInt8(upperFreeSectorCount / 256)
			for index in 0...121 {
				var byte = UInt8(0)
				for bit in 0..<8 {
					if freeSectors.contains(48 + index * 8 + bit) {
						byte = byte | (0x80 >> bit)
					}
					vtoc2[index] = byte
				}
			}
			for index in 124...127 { // Zero out unused bytes
				vtoc[index] = 0
			}
			writeSector(number: 1024, data: vtoc2)
		}
	}

	
}
