//
//  TSStationery.h
//  TeXShop
//
//  Created by Richard Koch on 7/8/10.
//  Copyright 2010 University of Oregon. All rights reserved.
//

#import <Cocoa/Cocoa.h>

// File › New from Stationery. The panel lists the files in ~/Library/TeXShop/Stationery
// with the text of the .comment file of the same name, and opens a copy of the chosen
// one as a new untitled document.
@interface TSStationery : NSObject <NSTableViewDataSource, NSTableViewDelegate, NSWindowDelegate, NSTextFieldDelegate>

@property (readonly, nonatomic) NSPanel *stationeryWindow;
@property (readonly, nonatomic) NSTableView *tableView;
@property (readonly, nonatomic) NSButton *createButton;
@property (readonly, nonatomic) NSButton *showInFinderButton;
// + adds an empty stationery and edits its name; - moves the selected one to the Trash.
@property (readonly, nonatomic) NSButton *plusButton;
@property (readonly, nonatomic) NSButton *minusButton;
// File names, with their extension, and the description of each.
@property (readonly, nonatomic) NSArray<NSString *> *fullSourceData;
@property (readonly, nonatomic) NSArray<NSString *> *commentData;
// The folder listed; ~/Library/TeXShop/Stationery unless a test sets another.
@property (copy, nonatomic) NSString *folderPath;

- (IBAction)newFromStationery:(id)sender;
- (IBAction)okForStationeryPanel:(id)sender;
- (IBAction)cancelForStationeryPanel:(id)sender;
- (IBAction)showStationeryInFinder:(id)sender;
- (IBAction)addStationery:(id)sender;
- (IBAction)removeSelectedStationery:(id)sender;
// The actions menu at the bottom of the list, and the contextual menu of a row.
- (IBAction)editStationery:(id)sender;
- (IBAction)renameStationery:(id)sender;
- (IBAction)duplicateStationery:(id)sender;
- (IBAction)revealStationeryInFinder:(id)sender;
// Reads the folder again, keeping the selected file selected when it is still there.
- (void)reloadStationery;

@end
