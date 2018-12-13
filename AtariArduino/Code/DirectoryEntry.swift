//
//  DirectoryEntry.swift
//  AtariArduino
//
//  Created by Lucius Kwok on 12/12/18.
//  Copyright © 2018 Lucius Kwok. All rights reserved.
//

import Foundation

struct DirectoryEntry {
	var fileNumber:Int
	var flags:UInt8
	var length:UInt16
	var start:UInt16
	var filename:String
	var fileExtension:String
	
	init() {
		fileNumber = 0
		flags = 0
		length = 0
		start = 0
		filename = ""
		fileExtension = ""
	}
	
	init(atariData:Data, index:Int) {
		self.fileNumber = index
		flags = atariData[0]
		length = UInt16(atariData[1]) + 256 * UInt16(atariData[2])
		start = UInt16(atariData[3]) + 256 * UInt16(atariData[4])
		filename = DirectoryEntry.string(directoryData: atariData.subdata(in: 5..<13))
		fileExtension = DirectoryEntry.string(directoryData: atariData.subdata(in: 13..<16))
	}
	
	static func string(directoryData:Data) -> String {
		var result = String()
		for c in directoryData {
			if c == 0 || c == 0x20 {
				break
			}
			result.append(String(format:"%c", c))
		}
		return result
	}
	
	// MARK: -
	
	func isLocked() -> Bool {
		return (flags & 0x20) != 0
	}
	
	mutating func setLocked(_ lock:Bool) {
		if lock {
			flags = flags | 0x20
		} else {
			flags = flags & ~0x20
		}
	}
	
	func filenameWithExtension() -> String {
		if fileExtension.count > 0 {
			return String(format:"%@.%@", filename, fileExtension)
		} else {
			return filename
		}
	}
	
	mutating func setFilenameWithExtension(_ string:String) {
		let components = string.components(separatedBy: ".")
		if components.count < 2 {
			filename = string
			fileExtension = ""
		} else {
			filename = components.first!
			fileExtension = components.last!
		}
		
		// Apply filename constraints
		if filename.count > 8 {
			filename = String(filename.prefix(8))
		}
		if fileExtension.count > 3 {
			fileExtension = String(fileExtension.prefix(3))
		}
		filename = filename.uppercased()
		fileExtension = fileExtension.uppercased()
	}

	func atariData() -> Data {
		// Returns the directory entry as a 16-byte data block that can be written to an AtariDiskImage.
		var data = Data(count: 16)
		
		data[0] = flags
		data[1] = UInt8(length % 256)
		data[2] = UInt8(length / 256)
		data[3] = UInt8(start % 256)
		data[4] = UInt8(start / 256)
		
		// Filename
		let filenameAscii = asciiData(string:filename)
		for index in 0..<8 {
			var c = UInt8(0x20)
			if index < filenameAscii.count {
				c = filenameAscii[index]
			}
			data[5 + index] = c
		}

		// Extension
		let extAscii = asciiData(string:fileExtension)
		for index in 0..<3 {
			var c = UInt8(0x20)
			if index < extAscii.count {
				c = extAscii[index]
			}
			data[13 + index] = c
		}
		
		return data
	}
	
	func asciiData(string:String) -> Data {
		var data = Data()
		string.forEach { (c) in
			if let uniChar = c.unicodeScalars.first {
				if uniChar.isASCII {
					let a = UInt8(uniChar.value)
					if a != 0 {
						data.append(a)
					}
				}
			}
		}
		return data
	}
	
}
