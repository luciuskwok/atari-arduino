//
//  ViewController.m
//  AtariArduino
//
//  Created by Lucius Kwok on 12/10/18.
//  Copyright © 2018 Lucius Kwok. All rights reserved.
//

#import "ViewController.h"
#import "Document.h"

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
	
	self.directoryTableView.delegate = self;
	self.directoryTableView.dataSource = self;
}

- (void)viewWillAppear {
	[super viewWillAppear];

	if (self.document == nil) {
		NSLog(@"[LK] Document is nil.");
	} else {
		self.directory = self.document.directory;
		[self.directoryTableView reloadData];
		//self.preferredContentSize = NSMakeSize(292, (3 + self.directory.count) * 17);
		
		NSUInteger totalSectors = [self.document usableSectorCount];
		NSUInteger freeSectors = [self.document freeSectorCount];
		if (totalSectors == 0 && freeSectors == 0) {
			self.statusLabel.stringValue = @"Unformatted disk";
		} else {
			self.statusLabel.stringValue = [NSString stringWithFormat:@"%u of %u sectors free", (unsigned int)freeSectors, (unsigned int)totalSectors];
		}
	}
}

- (void)setRepresentedObject:(id)representedObject {
    [super setRepresentedObject:representedObject];

    // Update the view, if already loaded.
	NSLog(@"[LK] setRepresentedObject.");
}

- (Document *)document {
	Document *doc = (Document *)[[NSDocumentController sharedDocumentController] documentForWindow:self.view.window];
	if ([doc isKindOfClass:[Document class]]) {
		return doc;
	} else {
		return nil;
	}
}

#pragma mark -

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView {
	return self.directory.count;
}

- (NSView *) tableView:(NSTableView *)tableView viewForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row {

	NSDictionary *entry = self.directory[row];
	NSString *text;

	if ([tableColumn.identifier isEqualToString:@"flags"]) {
		UInt8 flags = [entry[@"flags"] unsignedCharValue];
		if (flags & 0x20) {
			text = @"🔒";
		} else {
			text = @" ";
		}
	} else if ([tableColumn.identifier isEqualToString:@"filename"]) {
		NSString *filename = entry[@"filename"];
		NSString *ext = entry[@"ext"];
		if (ext.length > 0) {
			text = [NSString stringWithFormat:@"%@.%@", entry[@"filename"], entry[@"ext"]];
		} else {
			text = filename;
		}
	} else if ([tableColumn.identifier isEqualToString:@"size"]) {
		short length = [entry[@"length"] unsignedShortValue];
		text = [NSString stringWithFormat:@"%d", length];
	}
	
	NSTableCellView *cellView = [tableView makeViewWithIdentifier:tableColumn.identifier owner:nil];
	cellView.textField.stringValue = text;
	return cellView;
}


@end
