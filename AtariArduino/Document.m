//
//  Document.m
//  AtariArduino
//
//  Created by Lucius Kwok on 12/10/18.
//  Copyright © 2018 Lucius Kwok. All rights reserved.
//

#import "Document.h"

@interface Document ()

@end

@implementation Document

- (instancetype)init {
	self = [super init];
	if (self) {
		// Add your subclass-specific initialization here.
	}
	return self;
}

+ (BOOL)autosavesInPlace {
	return YES;
}


- (void)makeWindowControllers {
	// Override to return the Storyboard file name of the document.
	[self addWindowController:[[NSStoryboard storyboardWithName:@"Main" bundle:nil] instantiateControllerWithIdentifier:@"Document Window Controller"]];
}


- (NSData *)dataOfType:(NSString *)typeName error:(NSError **)outError {
	// Insert code here to write your document to data of the specified type. If outError != NULL, ensure that you create and set an appropriate error if you return nil.
	// Alternatively, you could remove this method and override -fileWrapperOfType:error:, -writeToURL:ofType:error:, or -writeToURL:ofType:forSaveOperation:originalContentsURL:error: instead.
	[NSException raise:@"UnimplementedMethod" format:@"%@ is unimplemented", NSStringFromSelector(_cmd)];
	return nil;
}


- (BOOL)readFromData:(NSData *)data ofType:(NSString *)typeName error:(NSError **)outError {
	// Insert code here to read your document from the given data of the specified type. If outError != NULL, ensure that you create and set an appropriate error if you return NO.
	// Alternatively, you could remove this method and override -readFromFileWrapper:ofType:error: or -readFromURL:ofType:error: instead.
	// If you do, you should also override -isEntireFileLoaded to return NO if the contents are lazily loaded.
	
	// Ensure file size is at least as large as the header
	NSUInteger fileSize = data.length;
	if (fileSize <= 16) {
		[self setErrorCode:NSFileReadCorruptFileError error:outError];
		return NO;
	}

	// Parse 16-byte header
	UInt16 magic, diskSizeParagraphs, aSectorSize;
	[data getBytes:&magic range:NSMakeRange(0, 2)];
	[data getBytes:&diskSizeParagraphs range:NSMakeRange(2, 2)];
	[data getBytes:&aSectorSize range:NSMakeRange(4, 2)];
	
	// Magic word in file header
	if (magic != 0x0296) {
		[self setErrorCode:NSFileReadCorruptFileError error:outError];
		return NO;
	}
	
	// Ensure file size is at least as large as diskSize in header
	NSUInteger diskSize = (NSUInteger)diskSizeParagraphs * 16;
	if (diskSize + 16 > fileSize) {
		[self setErrorCode:NSFileReadCorruptFileError error:outError];
		return NO;
	}
	
	// Sector size
	_sectorSize = aSectorSize;
	
	// Boot sectors
	self.bootSectorData = [data subdataWithRange:NSMakeRange(16, 384)];
	
	// Main sectors
	self.mainSectorData = [data subdataWithRange:NSMakeRange(16+384, diskSize-384)];
	
	return YES;
}

- (void)setErrorCode:(NSInteger)code error:(NSError**)outError {
	if (outError) {
		*outError = [NSError errorWithDomain:NSCocoaErrorDomain code:code userInfo:nil];
	}
}


@end
