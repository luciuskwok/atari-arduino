//
//  SerialPort.m
//  AtariArduino
//
//  Created by Lucius Kwok on 12/14/18.
//  Copyright © 2018 Lucius Kwok. All rights reserved.
//

#import "SerialPort.h"
#import <termios.h>
#import <sys/param.h>
#import <sys/filio.h>
#import <sys/ioctl.h>

@implementation SerialPort

- (instancetype) init {
	if (self = [super init]) {
		_isOpen = NO;
		_fileDescriptor = 0;
		_bitrate = 19200;
	}
	return self;
}

- (BOOL) open:(NSString *)devicePath {
	// Example path: /dev/cu.usbmodem1461
	int err;
	
	if (_isOpen) {
		return YES;
	}
	
	const char *cPath = [devicePath cStringUsingEncoding:NSASCIIStringEncoding];
	if (cPath == nil) {
		NSLog(@"[LK] Invalid device path.");
		return NO;
	}
	
	int fd = open(cPath, O_RDWR | O_NOCTTY | O_EXLOCK | O_NONBLOCK);
	if (fd == -1) {
		NSLog(@"[LK] Error opening serial device: %s (%d)", strerror(errno), errno);
		return NO;
	}
	_fileDescriptor = fd;
	_isOpen = YES;
	
	// Clear the O_NONBLOCK so that I/O will block and wait for more data.
	err = fcntl(_fileDescriptor, F_SETFL, 0);
	if (err == -1) {
		NSLog(@"[LK] Error clearing O_NONBLOCK: %s (%d)", strerror(errno), errno);
	}
	
	// Set port options.
	struct termios options;
	tcgetattr(_fileDescriptor, &options);
	cfmakeraw(&options); // Set to "raw" mode
	options.c_cc[VMIN] = 1; // Minimum number of characters for noncanonical read: 1 char
	options.c_cc[VTIME] = 2; // Timeout in deciseconds for noncanonical read: 0.2s
	options.c_cflag = CS8 | CREAD | HUPCL | CLOCAL; // Set flags: 8-bit data, receiver, hangup on close, ignore modem status lines. Clear flags:  No parity, 1 stop bit, no flow control.
	
	cfsetspeed(&options, _bitrate);
	
	err = tcsetattr(_fileDescriptor, TCSANOW, &options);
	if (err == -1) {
		NSLog(@"[LK] Error setting termios options: %s (%d)", strerror(errno), errno);
	}
	
	// Add handler for receiving bytes from the port
	dispatch_source_t rxSource = dispatch_source_create(DISPATCH_SOURCE_TYPE_READ, self.fileDescriptor, 0, dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0));
	SerialPort __weak *weakSelf = self;
	dispatch_source_set_event_handler (rxSource, ^{
		if (weakSelf != nil && weakSelf.isOpen) {
			NSMutableData *buffer = [NSMutableData dataWithLength:1024];
			long bytesRead = read(fd, buffer.mutableBytes, buffer.length);
			if (bytesRead > 0) {
				buffer.length = bytesRead;
				dispatch_async(dispatch_get_main_queue(), ^{
					if (weakSelf.didReceiveData) {
						weakSelf.didReceiveData(buffer);
					}
				});
			}
		}
	});
	// Close port if recieving is reset
	dispatch_source_set_cancel_handler(rxSource, ^{
		[weakSelf close];
	});
	dispatch_resume(rxSource);
	self.receiveSource = rxSource;
	
	return YES;
}

- (BOOL) sendData:(NSData *)data {
	if (_isOpen == NO) {
		return NO;
	}
	NSUInteger index = 0;
	while (index < data.length) {
		long writeCount = write(_fileDescriptor, data.bytes + index, data.length - index);
		if (writeCount < 0) {
			NSLog(@"[LK] Error writing to serial port: %ld", writeCount);
			return NO;
		}
		index += writeCount;
	}
	return YES;
}

- (void) close {
	int err = close(_fileDescriptor);
	if (err != 0) {
		NSLog(@"[LK] Error closing serial port: %d", err);
	}
	_isOpen = NO;
	_fileDescriptor = 0;
}

@end
