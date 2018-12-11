//
//  Document.h
//  AtariArduino
//
//  Created by Lucius Kwok on 12/10/18.
//  Copyright © 2018 Lucius Kwok. All rights reserved.
//

#import <Cocoa/Cocoa.h>

@interface Document : NSDocument

@property (assign, nonatomic) NSUInteger sectorSize;
@property (strong, nonatomic) NSData *bootSectorData;
@property (strong, nonatomic) NSData *mainSectorData;

- (NSArray<NSDictionary*>*)directory;

@end

