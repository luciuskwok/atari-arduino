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
	
	init() {
		fileNumber = 0
		flags = 0
		length = 0
		start = 0
		filename = ""
	}
	
	init(atariData:Data, fileNumber index:Int) {
		self.fileNumber = index
		flags = atariData[0]
		length = UInt16(atariData[1]) + 256 * UInt16(atariData[2])
		start = UInt16(atariData[3]) + 256 * UInt16(atariData[4])
		
		// Filename
		filename = DirectoryEntry.filename(atariData: atariData.subdata(in: 5..<16))
	}
	
	static func filename(atariData data:Data) -> String {
		var name = String(data: data.subdata(in: 0..<8), encoding: .ascii)!.trimmingCharacters(in: CharacterSet(charactersIn: " \0"))
		let ext = String(data: data.subdata(in: 8..<11), encoding: .ascii)!.trimmingCharacters(in: CharacterSet(charactersIn: " \0"))
		if ext.count > 0 {
			name = name + "." + ext
		}
		return name
	}
	
	static func atariData(filename f:String) -> Data {
		if f.count == 0 {
			return Data()
		}
		
		let name:String, ext:String
		let components = f.uppercased().components(separatedBy: ".")
		name = components.first!
		if components.count < 2 {
			ext = ""
		} else {
			ext = components.last!
		}

		var outData = paddedData(string: name, length: 8)
		outData.append(paddedData(string: ext, length: 3))
		return outData
	}
	
	static func paddedData(string: String, length: Int) -> Data {
		var data = string.data(using: .ascii, allowLossyConversion: true)!
		if data.count > length {
			data.count = length
		}
		while data.count < length {
			data.append(0x20)
		}
		return data
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
	
	func atariData() -> Data {
		// Returns the directory entry as a 16-byte data block that can be written to an AtariDiskImage.
		var data = Data(count: 5)
		
		data[0] = flags
		data[1] = UInt8(length % 256)
		data[2] = UInt8(length / 256)
		data[3] = UInt8(start % 256)
		data[4] = UInt8(start / 256)
		data.append(DirectoryEntry.atariData(filename: filename))
		
		return data
	}
	
}
