//
//  Document.h
//  AtariArduino
//
//  Created by Lucius Kwok on 12/10/18.
//  Copyright © 2018 Lucius Kwok. All rights reserved.
//

#import <Cocoa/Cocoa.h>

@interface Document : NSDocument

@property (assign, nonatomic) NSUInteger bootSectorSize;
@property (assign, nonatomic) NSUInteger mainSectorSize;
@property (strong, nonatomic) NSMutableArray<NSData *> *sectors;


- (NSArray<NSDictionary*>*) directory;
- (BOOL) setFilename:(NSString *)filename atIndex:(NSUInteger)index;
- (BOOL) setLocked:(BOOL)locked atIndex:(NSUInteger)index;

- (NSUInteger) diskImageSize;
- (NSUInteger) freeSectorCount;

- (NSData *) dataInSector:(NSUInteger)sectorNumber;
- (BOOL) writeData:(NSData *)data inSector:(NSUInteger)sectorNumber;


@end

