//
//  SerialPort.h
//  AtariArduino
//
//  Created by Lucius Kwok on 12/14/18.
//  Copyright © 2018 Lucius Kwok. All rights reserved.
//

#import <Foundation/Foundation.h>


NS_ASSUME_NONNULL_BEGIN

@interface SerialPort : NSObject

@property (assign, nonatomic) BOOL isOpen;
@property (assign, nonatomic) int fileDescriptor;
@property (assign, nonatomic) UInt32 bitrate;
@property (copy, nonatomic, nullable) void (^didReceiveData)(NSData*);

- (BOOL) open:(NSString *)devicePath;
- (BOOL) sendData:(NSData *)data;
- (void) close;

@end

NS_ASSUME_NONNULL_END
