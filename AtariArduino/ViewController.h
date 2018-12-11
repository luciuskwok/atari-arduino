//
//  ViewController.h
//  AtariArduino
//
//  Created by Lucius Kwok on 12/10/18.
//  Copyright © 2018 Lucius Kwok. All rights reserved.
//

#import <Cocoa/Cocoa.h>

@interface ViewController : NSViewController
<NSTableViewDelegate, NSTableViewDataSource>

@property (weak, nonatomic) IBOutlet NSTableView *directoryTableView;
@property (weak, nonatomic) IBOutlet NSTextField *statusLabel;

@property (strong, nonatomic) NSArray<NSDictionary *> *directory;

@end

