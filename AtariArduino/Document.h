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
@property (assign, nonatomic) NSData *bootSectorData;
@property (assign, nonatomic) NSData *mainSectorData;


@end

