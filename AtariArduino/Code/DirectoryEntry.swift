//
//  DirectoryEntry.swift
//  AtariArduino
//
//  Created by Lucius Kwok on 12/12/18.
//  Copyright © 2018 Lucius Kwok. All rights reserved.
//

import Foundation

struct DirectoryEntry {
	var index:Int
	var flags:UInt8
	var length:UInt16
	var start:UInt16
	var filename:String
	var fileExtension:String
	
	init() {
		index = 0
		flags = 0
		length = 0
		start = 0
		filename = ""
		fileExtension = ""
	}
	
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
	
	mutating func setFilenameAndExtension(data:Data) {
		if data.count == 11 {
			filename = string(directoryData: data.subdata(in: 0..<8))
			fileExtension = string(directoryData: data.subdata(in: 8..<11))
		} else {
			NSLog("[LK] Invalid filename.ext length")
		}
	}
	
	func string(directoryData:Data) -> String {
		var result = String()
		for c in directoryData {
			if c == 0 || c == 0x20 {
				break;
			}
			result.append(String(format:"%c", c))
		}
		return result
	}
	
}
