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
	static var shared = ArduinoDevice()
	var serialPort:SerialPort?
	var mountedDisks = [AtariDiskImage?]()

	var inputBuffer = Data()
	var inputRemaining = 0
	var inputBufferClosure: ((_ buffer:Data) -> Void)?
	
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
				port.open("/dev/cu.usbmodem1461")
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
			port.send(data)
		}
	}
	
	func send(reply: ReplyCode) {
		send(byte: reply.rawValue)
	}
	
	func send(byte: UInt8) {
		if let port = serialPort, port.isOpen {
			port.send(Data(bytes: [byte]))
		}
	}
	
	func receive(data:Data) {
		// When inputRemaining is zero, we're waiting for a command. Otherwise, store received data in buffer.
		if inputRemaining > 0 {
			let count = min(data.count, inputRemaining)
			inputBuffer.append(data.subdata(in: 0..<count))
			inputRemaining -= count
			if inputRemaining == 0, let closure = inputBufferClosure {
				closure(inputBuffer)
			}
		} else {
			// Parse Command frame
			if data.count == 5 {
				// Validate checksum
				let checksum = crc8(data.subdata(in: 0..<4))
				if checksum != data[4] {
					NSLog("[LK] Invalid checksum.")
					return
				}
				
				// Validate device ID
				let deviceID = data[0]
				if deviceID < 0x31 || deviceID > 0x38 {
					NSLog("[LK] Invalid device ID.")
					return
				}
				let drive = Int(deviceID - 0x31)
				let sector = Int(data[2]) + Int(data[3]) * 256
				
				// Delay until 1 ms has passed
				DispatchQueue.main.asyncAfter(deadline: .now() + 0.001) {
					if let command = CommandCode(rawValue: data[1]) {
						switch command {
						case .read: // 'R'
							print("Read sector \(sector)")
							self.sendSector(drive: drive, sector: sector)
						case .driveStatus: // 'S'
							print("Status sector \(sector)")
							self.sendDriveStatus(drive: drive, sector: sector)
						case .write: // 'W'
							print("Write sector \(sector)")
							self.receiveSector(drive: drive, sector: sector)
						case .put: // 'P'
							print("Put sector \(sector)")
							self.receiveSector(drive: drive, sector: sector)
						default:
							print("Other command")
							self.send(reply: .error)
						}
					} else {
						print("Unknown command \(data[1]), sector \(sector)")
						self.send(reply: .error)
					}
				} // end DispatchQueue.main.async()
			}
		}
	}
	
	func sendSector(drive:Int, sector:Int) {
		if let disk = mountedDisks[drive], let sectorData = disk.sector(number: sector) {
			send(reply: .complete)
			send(data: sectorData)
			send(byte: crc8(sectorData)) // checksum
			NSLog("Sent sector")
		} else {
			NSLog("[LK] Invalid drive or sector number")
			send(reply: .error)
		}
	}
	
	func sendDriveStatus(drive:Int, sector:Int) {
		guard let disk = mountedDisks[drive] else {
			send(reply: .error)
			return;
		}
		
		var status = Data(count: 4)
		
		// Write protect (locked disk image)
		if disk.isLocked {
			status[0] |= 0x08
		}
		// Enhanced density (Atari 1050)
		if disk.sectors.count >= 1040 {
			status[0] |= 0x80
		}
		// Active/standby
		status[0] |= 0x10
		
		// status[1]: floppy disk controller chip status register value
		
		// status[2]: timeout in seconds
		status[2] = 5
		
		// Send 'C', 4-byte data frame, followed by checksum
		send(reply: .complete)
		send(data: status)
		send(byte: crc8(status)) // checksum
	}
	
	func receiveSector(drive:Int, sector:Int) {
		if let disk = mountedDisks[drive], sector <= disk.sectors.count && disk.isLocked == false {
			// Set up to receive sector data, which might be broken up into several chunks
			inputBuffer = Data()
			inputRemaining = 129 // 128 bytes + checksum byte
			inputBufferClosure = { buffer in
				self.write(data: buffer, drive:drive, sector:sector)
			}
		} else {
			NSLog("[LK] Invalid drive or sector number")
			send(reply: .error)
		}
	}
	
	func write(data: Data, drive:Int, sector:Int) {
		if verifyFrame(data) == false {
			NSLog("[LK] Invalid checksum")
			send(reply: .error)
			return
		}
		let sectorData = data.subdata(in: 0..<data.count - 1)
		if sectorData.count != 128 {
			NSLog("[LK] Sector data is not 128 bytes long")
			send(reply: .error)
			return
		}
		
		// Delay at least 850 microseconds before sending acknowledge.
		DispatchQueue.main.asyncAfter(deadline: .now() + 0.00085) {
			if let disk = self.mountedDisks[drive], sector <= disk.sectors.count && disk.isLocked == false {
				self.send(reply: .acknowledge)
				disk.writeSector(number: sector, data: sectorData)
				NotificationCenter.default.post(name: ArduinoDevice.diskDidChangeNotification, object: self)
				// Delay at least 250 microseconds before sending complete.
				DispatchQueue.main.asyncAfter(deadline: .now() + 0.00025) {
					self.send(reply: .complete)
				}
			} else {
				NSLog("[LK] Invalid drive or sector number")
				self.send(reply: .error)
			}
		}
	}

	func verifyFrame(_ data:Data) -> Bool {
		if data.count < 2 {
			NSLog("[LK] Data frame too short")
			return false
		}
		let checksum = crc8(data.subdata(in: 0..<data.count - 1))
		return checksum == data.last!
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
