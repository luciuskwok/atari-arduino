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
		[self reloadDirectory];
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

- (void)reloadDirectory {
	self.directory = self.document.directory;
	[self.directoryTableView reloadData];
	//self.preferredContentSize = NSMakeSize(292, (3 + self.directory.count) * 17);
	
	NSUInteger diskSize = [self.document diskImageSize] / 1024;
	NSUInteger freeSectors = [self.document freeSectorCount];
	if (freeSectors == 0) {
		self.statusLabel.stringValue = [NSString stringWithFormat:@"Unformatted %u KB disk", (unsigned int)diskSize];
	} else {
		self.statusLabel.stringValue = [NSString stringWithFormat:@"%u sectors free, %u KB disk", (unsigned int)freeSectors, (unsigned int)diskSize];
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
		unsigned short length = [entry[@"length"] unsignedShortValue];
		text = [NSString stringWithFormat:@"%u", length];
	}
	
	NSTableCellView *cellView = [tableView makeViewWithIdentifier:tableColumn.identifier owner:nil];
	cellView.textField.stringValue = text;
	return cellView;
}

- (BOOL)isFirstSelectedItemLocked {
	NSIndexSet *selection = [self.directoryTableView selectedRowIndexes];
	if (selection.count > 0) {
		NSUInteger firstSelectedRow = selection.firstIndex;
		NSDictionary *entry = self.directory[firstSelectedRow];
		return (([entry[@"flags"] unsignedCharValue] & 0x20) != 0);
	}
	return NO;
}

- (IBAction)toggleItemLock:(id)sender {
	// If first selected item is locked, then unlock all selected items.
	// If first selected item is unlocked, then lock all selected items.
	
	BOOL newLockState = ![self isFirstSelectedItemLocked];
	NSIndexSet *selection = [self.directoryTableView selectedRowIndexes];
	NSUInteger directoryIndex = 0;
	for (NSDictionary *entry in self.directory) {
		if ([selection containsIndex:directoryIndex]) {
			NSUInteger onDiskIndex = [entry[@"index"] unsignedIntegerValue];
			[self.document setLocked:newLockState atIndex:onDiskIndex];
		}
		++directoryIndex;
	}
	
	[self reloadDirectory];
}

- (IBAction)renameItem:(id)sender {
	NSLog(@"[LK] Rename item.");
	[self reloadDirectory];
}

- (BOOL)validateMenuItem:(NSMenuItem *)menuItem {
	BOOL enableItem = NO;
	NSIndexSet *selection = [self.directoryTableView selectedRowIndexes];

	if ([menuItem action] == @selector(toggleItemLock:)) {
		enableItem = (selection.count >= 1);
		if ([self isFirstSelectedItemLocked]) {
			[menuItem setTitle:NSLocalizedString(@"Unlock", @"")];
		} else {
			[menuItem setTitle:NSLocalizedString(@"Lock", @"")];
		}
		
	} else if ([menuItem action] == @selector(renameItem:)) {
		enableItem = (selection.count == 1);
		
	} else if ([menuItem action] == @selector(delete:)) {
		enableItem = (selection.count >= 1);
		
	} else {
		enableItem = [super validateMenuItem:menuItem];
	}
	return enableItem;
}

@end
