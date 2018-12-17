//
//  ArduinoDevice.swift
//  AtariArduino
//
//  Created by Lucius Kwok on 12/15/18.
//  Copyright © 2018 Lucius Kwok. All rights reserved.
//

import Foundation
import IOKit
import IOKit.serial

class ArduinoDevice {
	// Update the device name as needed.
	let devicePrefix = "cu.usbmodem" // Example:  "/dev/cu.usbmodem1461"
	
	static var shared = ArduinoDevice()
	var serialPort:SerialPort?
	var mountedDisks = [AtariDiskImage?]()

	var inputBuffer = Data()
	var inputRemaining = 0
	var previousReceivedTimestamp = Date()
	let inputTimeout = 1.0 // seconds
	
	// Notification
	static let mountDidChangeNotification = NSNotification.Name("ArduinoDevice.MountDidChange")
	static let diskDidChangeNotification = NSNotification.Name("ArduinoDevice.DiskDidChange")

	// Enum
	enum CommandCode: UInt8 {
		case formatSingle = 0x21 // !: format disk for single density (720 sectors, 128 bytes per sector)
		case formatEnhanced = 0x22 // ": format disk for 1050 enhanced density (1040 sectors, 128 bytes per sector)
		case readConfiguration = 0x4E // N: 12 data bytes from drive
		case writeConfiguration = 0x4F // O: 12 data bytes to drive
		case put = 0x50 // P: put a sector
		case read = 0x52 // R: read a sector
		case driveStatus = 0x53 // S: 4 data bytes
		case write = 0x57 // W: same as "put" but with verification
		case debugInfo = 1
		case none = 0
	}
	enum ReplyCode: UInt8 {
		case acknowledge = 0x41 // A
		case complete = 0x43 // C
		case error = 0x45 // E
		case negative = 0x4E // N
	}
	
	// MARK: -

	private init() {
		serialPort = SerialPort()
		serialPort!.bitrate = 19200
		serialPort!.didReceiveData = { data in
			self.receive(data:data)
		}
		
		// Add 8 empty drives
		for _ in 0..<8 {
			mountedDisks.append(nil)
		}
	}
	
	func open() {
		if let port = serialPort {
			if port.isOpen {
				port.close()
			} else {
				if let deviceName = SerialPort.device(withPrefix: devicePrefix) {
					port.open(deviceName)
					inputRemaining = 0
				} else {
					NSLog("[LK] Arduino serial device not found.")
				}
			}
		}
	}
	
	var isOpen:Bool {
		guard let port = serialPort else {
			return false
		}
		return port.isOpen
	}
	
	func close() {
		if let port = serialPort, port.isOpen {
			port.close()
		}
	}
	
	func send(data:Data) {
		if let port = serialPort, port.isOpen {
			let count = UInt8(data.count)
			let checksum = crc8(data)

			var outputData = data
			outputData.insert(count, at: 0)
			outputData.append(checksum)
			port.send(outputData)
		}
	}
	
	func send(reply:ReplyCode) {
		if let port = serialPort, port.isOpen {
			port.send(Data([reply.rawValue]))
		}
	}
	
	func receive(data:Data) {
		// When receiving data, initially look for a single byte that indicates the length of the data in the frame to be received. If there has been a gap of inputTimeout since that last received data, clear the inputBuffer and look for a new frame.
		if previousReceivedTimestamp.timeIntervalSinceNow < -inputTimeout {
			NSLog("[LK] Serial timed out.")
			inputRemaining = 0
		}
		
		// Update timestamp
		previousReceivedTimestamp = Date()
		
		for c in data {
			receiveByte(c)
		}
	}
	
	func receiveByte(_ c:UInt8) {
		if inputRemaining <= 0 {
			inputBuffer = Data() // Clear buffer
			inputRemaining = Int(c) + 1 // Add 1 for checksum
		} else {
			inputBuffer.append(c)
			inputRemaining -= 1
		}
		
		// Verify and process the completed frame that was received.
		if inputRemaining <= 0 {
			let frameData = inputBuffer.subdata(in: 0 ..< inputBuffer.count - 1)
			let checksum = crc8(frameData)
			if checksum == inputBuffer.last! {
				process(frameData: frameData)
			} else {
				NSLog("[LK] Invalid checksum")
				printHexdump(data: inputBuffer)
			}
			inputRemaining = 0
		}
	}
	
	func printHexdump(data:Data) {
		var s = String()
		for c in data {
			s += String(format:"%02X ", c)
		}
		print(s)
	}
	
	func process(frameData:Data) {
		let drive = frameData[1] - 0x31;
		if let command = CommandCode(rawValue: frameData[0]) {
			switch command {
			case .driveStatus:
				sendDriveStatus(drive: drive)
			case .read:
				let sector = Int(frameData[2]) + 256 * Int(frameData[3])
				sendSector(drive: drive, sector: sector, offset: frameData[4])
			case .write:
				receiveSector(data: frameData)
			case .debugInfo:
				if let string = String(data: frameData.subdata(in: 1 ..< frameData.count), encoding: .ascii) {
					NSLog("[ARD] " + string)
				}
			default:
				NSLog("[LK] Unsupported command.")
			}
		} else {
			NSLog("[LK] Unknown command.")
		}
	}
	
	func sendDriveStatus(drive:UInt8) {
		var status = Data(count: 4)
		if drive < 8, let disk = mountedDisks[Int(drive)] {
			// Enhanced density (Atari 1050) | Active/Standby
			status[0] = 0x18
		
			// Write protect (locked disk image)
			if disk.isLocked {
				status[0] |= 0x08
			}

			// status[1]: floppy disk controller chip status register value
			status[2] = 5 // timeout in seconds
			// status[3]: unused
		}
		
		send(data: status)
		NSLog("[LK] Sent drive \(drive) status.")
	}

	
	func sendSector(drive:UInt8, sector:Int, offset:UInt8) {
		// Send error if disk is not mounted in requested drive, the sector data does not exist, or the sector is not 128 bytes long.
		guard drive < 8, let disk = self.mountedDisks[Int(drive)], let sectorData = disk.sector(number: sector) else {
			send(reply:.error)
			return
		}
		
		// If offset is 0xFF, treat this as a query as to whether the sector is valid.
		if offset == 0xFF {
			send(reply:.acknowledge)
			return
		}
		
		// Send the sector chunk as 32 bytes, to keep under the Arduino's 64-byte serial buffer limit
		let chunkData = sectorData.subdata(in: Int(offset) ..< Int(offset) + 32)
		send(data: chunkData)
		//NSLog("Sent drive \(drive) sector \(sector) offset \(offset).")
	}
	
	
	func receiveSector(data:Data) {
		guard data.count == 132 else {
			NSLog("[LK] Received sector data frame is not 132 bytes long.")
			send(reply:.error)
			return
		}
		
		// Receive the sector in one 128-byte chunk because Arduino should have no problem sending more than 64 bytes at a time.
		let drive = Int(data[1]) - 0x31;
		let sector = Int(data[2]) + 256 * Int(data[3])
		
		// Write sector data
		let sectorData = data.subdata(in: 4 ..< data.count)
		if write(data:sectorData, drive:drive, sector:sector) == false {
			NSLog("[LK] Invalid parameters.")
			send(reply:.error)
			return
		}
		
		// Reply with Complete
		send(reply:.complete)
	}
	
	func write(data: Data, drive:Int, sector:Int) -> Bool {
		guard data.count == 128 else {
			NSLog("[LK] Sector data is not 128 bytes long.")
			return false
		}
		guard drive < 8, let disk = self.mountedDisks[drive] else {
			NSLog("[LK] Invalid drive \(drive).")
			return false
		}
		if disk.isLocked {
			NSLog("[LK] Disk \(drive) is locked.")
			return false
		}
		if sector > disk.sectors.count {
			NSLog("[LK] Sector \(sector) is beyond end of disk.")
			return false
		}
		
		disk.writeSector(number: sector, data: data)
		NotificationCenter.default.post(name: ArduinoDevice.diskDidChangeNotification, object: self)
		NSLog("[LK] Wrote disk \(drive), sector \(sector).")
		return true
	}

	func crc8(_ data:Data) -> UInt8 {
		var result = UInt16(0)
		for c in data {
			result += UInt16(c)
			result = (result % 256) + (result / 256)
		}
		return UInt8(result)
	}
	
	// MARK: -
	
	func mount(disk: AtariDiskImage, at index:Int) {
		// Check if disk is already mounted.
		if let existingIndex = mountedDisks.lastIndex(of: disk) {
			if existingIndex == index {
				// Do nothing if disk is already mounted at index.
				return
			} else {
				// Remove disk if it already mounted elsewhere
				mountedDisks[existingIndex] = nil
			}
		}
		// Add disk in new slot
		mountedDisks[index] = disk
		
		// Notify
		NotificationCenter.default.post(name: ArduinoDevice.mountDidChangeNotification, object: self)
	}
	
	func unmount(disk: AtariDiskImage) {
		if let existingIndex = mountedDisks.lastIndex(of: disk) {
			mountedDisks[existingIndex] = nil
			// Notify
			NotificationCenter.default.post(name: ArduinoDevice.mountDidChangeNotification, object: self)
		}
	}
	
}
