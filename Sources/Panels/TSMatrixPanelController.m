/*
 * TeXShop - TeX editor for Mac OS
 * Copyright (C) 2000-2005 Richard Koch
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 51 Franklin St, Fifth Floor, Boston, MA  02110-1301  USA
 *
 * $Id: TSMatrixPanelController.m 254 2007-06-03 21:09:25Z fingolfin $
 *
 * Created by Jonas Zimmermann on Fri Nov 28 2003.
 *
 */

#import "TSMatrixPanelController.h"
#import "TSLibraryRepair.h"
#import "TSMatrixTableView.h"
#import "TSWindowManager.h"


#import "globals.h"
#define MatPboardType 	@"MatrixRowPboardType"
#define MATSIZE 10

@implementation TSMatrixPanelController


static id _sharedInstance = nil;

+ (id)sharedInstance
{
	if (_sharedInstance == nil)
		_sharedInstance = [[TSMatrixPanelController alloc] initWithWindowNibName:@"matrixpanel"];
	return _sharedInstance;
}

- (id)init
{
	if ((self = [super init])) {
		shown = NO;
	}
	return self;
}

- (void)dealloc
{
//	[myMatrix release];
//	[arrayMatrix release];
//	myMatrix = nil;
//	arrayMatrix = nil;
	[[NSNotificationCenter defaultCenter] removeObserver:self];

//	[super dealloc];
}

- (MatrixData *)theMatrix
{
	return self.myMatrix;
}

/*

- (NSArray*)draggedRows
{
	return draggedRows;
}
*/

-(void)awakeFromNib
{
	// MatrixSize = MATSIZE;
	MatrixSize = [SUD integerForKey:MatrixSizeKey];
	if (MatrixSize < 2)
		MatrixSize = 2;
	if (MatrixSize > 100)
		MatrixSize = 100;
	
	[hstep setMaxValue:MatrixSize];
	[vstep setMaxValue:MatrixSize];
	self.myMatrix=[[MatrixData alloc]init];
	NSInteger j;
	for (j = 0; j < MatrixSize; j++) {
		[self.myMatrix addRow];
	}
	
	while ([self.myMatrix colCount]<MatrixSize) {
		[self.myMatrix addCol];
		MatrixTableColumn *newcol;
		newcol = [[MatrixTableColumn alloc] initWithIdentifier:[[NSNumber numberWithInteger:[self.myMatrix colCount]-1] stringValue]];
		[[newcol headerCell] setStringValue:[[NSNumber numberWithInteger:[self.myMatrix colCount]] stringValue]];
		[newcol setMinWidth:40];
		[newcol setWidth:60];
		[matrixtable addTableColumn:newcol];
	}

	[self.myMatrix setActRows:3];
	[self.myMatrix setActCols:3];
	
	// The numbers of the rows, at the left of the table, look like the numbers of the columns in its header.
	[self addRowNumberColumn];

	[matrixtable setAutosaveTableColumns:TRUE];
	[self keepRowNumberColumnFirst];
	[matrixtable setVerticalMotionCanBeginDrag:NO];
	[matrixtable registerForDraggedTypes:[NSArray arrayWithObjects:MatPboardType, nil]];
	
	[matrixtable reloadData];
}

- (void)windowDidLoad
{
	NSPoint		aPoint;
	NSString		*matrixPath;
	NSDictionary	*matrixDictionary;


	matrixPath = [MatrixPanelPath stringByStandardizingPath];
	matrixPath = [matrixPath stringByAppendingPathComponent:@"matrixpanel_1"];
	matrixPath = [matrixPath stringByAppendingPathExtension:@"plist"];
	if (TSLibraryRepairFile(matrixPath, TSLibraryBundledPath(@"MatrixPanel/matrixpanel_1.plist"), TSLibraryShapeOfBundledCheck(nil)))
		matrixDictionary = [NSDictionary dictionaryWithContentsOfFile:matrixPath];
	else
		matrixDictionary = [NSDictionary dictionaryWithContentsOfFile:
			TSLibraryBundledPath(@"MatrixPanel/matrixpanel_1.plist") ?: @""];

	[super windowDidLoad];
	[self arrangeControls];

	[[NSNotificationCenter defaultCenter] addObserver: self selector:@selector(panelDidMove:)
												 name:NSWindowDidMoveNotification object:[self window]];
	[[NSNotificationCenter defaultCenter] addObserver: self selector:@selector(panelWillClose:)
												 name:NSWindowWillCloseNotification object:[self window]];


	// result = [[self window] setFrameAutosaveName:LatexPanelNameKey];
	aPoint.x = [[NSUserDefaults standardUserDefaults] floatForKey:MPanelOriginXKey];
	aPoint.y = [[NSUserDefaults standardUserDefaults] floatForKey:MPanelOriginYKey];
	[[self window] setFrameOrigin: aPoint];
	[[self window] setHidesOnDeactivate: YES];
	// [self window] is actually an NSPanel, so it responds to the message below
	[(NSPanel *)[self window] setBecomesKeyOnlyIfNeeded: NO];

	self.arrayMatrix = [[NSArray alloc] initWithArray:[matrixDictionary objectForKey:@"Matrix" ]];

	notifcenter = [NSNotificationCenter defaultCenter];
	[self scrollTableToTop];
}

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView
{
	return [self.myMatrix rowCount];
}

// Mandatory tableview data source method
- (id)tableView:(NSTableView *)tableView objectValueForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row
{
	NSString  *theValue, *colid;
	colid = [tableColumn identifier];
	NSParameterAssert(row >= 0 && row < [self.myMatrix rowCount]);
	if ([colid isEqualToString:TSMatrixRowNumberColumn]) {
		return [NSNumber numberWithInteger:row+1];
	} else {
		theValue = [self.myMatrix objectInRow:row inCol:[colid integerValue]];
		return theValue;
	}

}
- (void)tableViewColumnDidMove:(NSNotification *)aNotification
{
	[matrixtable reloadData];
	[matrixtable setNeedsDisplay];
}

- (void)tableView:(NSTableView *)tv setObjectValue:(id)objectValue forTableColumn:(NSTableColumn *)tc row:(NSInteger)row
{
	if ([[tc identifier] isEqualToString:TSMatrixRowNumberColumn])
		return;
	[self.myMatrix replaceObjectInRow:row inCol:[[tc identifier] integerValue] withObject:objectValue];
}

	// when a drag-and-drop operation comes through, and a filename is being dropped on the table,
	// we need to tell the table where to put the new filename (right at the end of the table).
	// This controls the visual feedback to the user on where their drop will go.
- (NSDragOperation)tableView:(NSTableView*)tv validateDrop:(id <NSDraggingInfo>)info proposedRow:(NSInteger)row proposedDropOperation:(NSTableViewDropOperation)op
{
	[tv setDropRow:row dropOperation:NSTableViewDropAbove];
	return [info draggingSourceOperationMask];
}

- (BOOL) tableView:(NSTableView*)tv writeRows:(NSArray*)rows toPasteboard:(NSPasteboard *)pboard
{
	NSInteger i;
	NSMutableArray *j = [NSMutableArray array];
	[pboard declareTypes:[NSArray arrayWithObject:MatPboardType] owner:self];
	
	for (i = 0; i < [rows count]; i++) {
		[j addObject:[self.myMatrix myRowAtIndex:[[rows objectAtIndex:i] integerValue]]];
	}
	[pboard setPropertyList:j forType:MatPboardType];
	self.draggedRows = j;
	
	return YES;
	
}


// This routine does the actual processing for a drag-and-drop operation on a tableview.
// As the tableview's data source, we get this call when it's time to update our backend data.
- (BOOL)tableView:(NSTableView*)tv acceptDrop:(id <NSDraggingInfo>)info row:(NSInteger)row dropOperation:(NSTableViewDropOperation)op
{
	// Get the drag-n-drop pasteboard
	NSPasteboard *myPasteboard=[info draggingPasteboard];
	// What type of data are we going to allow to be dragged?  The pasteboard
	// might contain different formats
	NSArray *typeArray=[NSArray arrayWithObjects:MatPboardType,nil];
	NSString *availableType;
	NSMutableArray *_draggedrows;
	NSMutableArray *matRow;
	NSMutableIndexSet* indset = [NSMutableIndexSet indexSet];
	NSInteger i;
	
	// find the best match of the types we'll accept and what's actually on the pasteboard
	availableType=[myPasteboard availableTypeFromArray:typeArray];
	// In the file format type that we're working with, get all data on the pasteboard
	_draggedrows=[[myPasteboard propertyListForType:availableType] mutableCopy];
	
	for (i = 0; i < [_draggedrows count]; i++) {
		// The pasteboard gives the row back unchangeable; the matrix changes its rows in place.
		matRow = [[_draggedrows objectAtIndex:i] mutableCopy];
		[_draggedrows replaceObjectAtIndex:i withObject:matRow];
		if (row > [[self.myMatrix rows] indexOfObjectIdenticalTo:[[(TSMatrixPanelController *)[[info draggingSource] dataSource] draggedRows] objectAtIndex:i]])
			row--;
		[[self.myMatrix rows] removeObjectIdenticalTo:[[(TSMatrixPanelController *)[[info draggingSource] dataSource] draggedRows] objectAtIndex:i]];
		
		[[self.myMatrix rows] insertObject:matRow atIndex:row+i];
	}
	for (i = 0; i < [_draggedrows count]; i++) {
		matRow = [_draggedrows objectAtIndex:i];
		[indset addIndex:[[self.myMatrix rows] indexOfObjectIdenticalTo:matRow]];
	}
	
	[matrixtable reloadData];
	[matrixtable selectRowIndexes:indset byExtendingSelection:NO];
	
	return YES;
}



- (IBAction)resizeMatrix:(id)sender
{
	NSInteger ival = [sender integerValue];
	if (ival > MatrixSize)
		ival = MatrixSize;
	else if (ival < 1)
		ival = 1;

	if ((sender == hstep) || (sender == htf)) {
		while ((ival != [self.myMatrix actCols]) && (ival <= MatrixSize) && (ival > 0)) {
			if (ival > [self.myMatrix actCols]) {
				[self.myMatrix setActCols:[self.myMatrix actCols]+1];
			} else {
				[self.myMatrix setActCols:[self.myMatrix actCols]-1];
				
			}
		}
		
		if (sender == hstep)
			[htf setIntegerValue:[self.myMatrix actCols]];
		else {
			[hstep setIntegerValue:[self.myMatrix actCols]];
			[htf setIntegerValue:[self.myMatrix actCols]];
		}
		
	} else if ((sender == vstep) || (sender == vtf)) {
		
		while ((ival != [self.myMatrix actRows]) && (ival <= MatrixSize) && (ival > 0)) {
			if (ival > [self.myMatrix actRows]) {
				[self.myMatrix setActRows:[self.myMatrix actRows]+1];
			} else {
				[self.myMatrix setActRows:[self.myMatrix actRows]-1];
			}
		}
		
		if (sender == vstep)
			[vtf setIntegerValue:[self.myMatrix actRows]];
		else {
			[vstep setIntegerValue:[self.myMatrix actRows]];
			[vtf setIntegerValue:[self.myMatrix actRows]];
		}
		
	}
	[matrixtable reloadData];
}

- (IBAction)insertMatrix:(id)sender
{
	NSMutableString *insertion = [NSMutableString stringWithCapacity:200];
	NSInteger i, j;
	NSInteger brstyleop = [[brselop selectedCell] tag];
	NSInteger brstylecl = [[brselcl selectedCell] tag];
	NSInteger environment = [[envsel selectedCell] tag];
	NSInteger tablenv = ([chbfig state] == NSOnState);
	NSInteger drawborder = ([borderbutton state] == NSOnState);
	NSInteger drawgrid = ([gridbutton state] == NSOnState);
	NSInteger hsize = [self.myMatrix actCols];
	NSInteger vsize = [self.myMatrix actRows];
	NSArray<NSTableColumn *> *matrixColumns = [(TSMatrixTableView *)matrixtable matrixColumns];

	if (environment == 0) {
		if ((brstyleop == 4) && (brstylecl == 4)) {
		} else {
			[insertion appendString:[self.arrayMatrix objectAtIndex:6]];
			if (brstyleop == 0) {
				[insertion appendString:[self.arrayMatrix objectAtIndex:8]];
			} else if (brstyleop == 1) {
				[insertion appendString:[self.arrayMatrix objectAtIndex:10]];
			} else if (brstyleop == 2) {
				[insertion appendString:[self.arrayMatrix objectAtIndex:12]];
			} else if (brstyleop == 3) {
				[insertion appendString:[self.arrayMatrix objectAtIndex:14]];
			} else if (brstyleop == 5) {
				[insertion appendString:[self.arrayMatrix objectAtIndex:15]];
				[insertion appendString:[brtfop stringValue]];
			} else if (brstyleop == 4) {
				[insertion appendString:[self.arrayMatrix objectAtIndex:15]];
			} else if (brstylecl == 6) {
				[insertion appendString:[self.arrayMatrix objectAtIndex:16]];
			}

		}
	}

	if (environment == 0) {
		[insertion appendString:[self.arrayMatrix objectAtIndex:0]];
	} else {
		if (tablenv) {
			[insertion appendString:[self.arrayMatrix objectAtIndex:20]];
		}
		[insertion appendString:[self.arrayMatrix objectAtIndex:17]];
	}

	if (drawborder)
		[insertion appendString:[self.arrayMatrix objectAtIndex:14]];

	for (i = 0; i < hsize; i++)  {
		[insertion appendString:[self.arrayMatrix objectAtIndex:1]];
		if ((drawgrid) && (i<hsize-1))
			[insertion appendString:[self.arrayMatrix objectAtIndex:14]];
	}
	if (drawborder)
		[insertion appendString:[self.arrayMatrix objectAtIndex:14]];

	[insertion appendString:[self.arrayMatrix objectAtIndex:2]];
	if (drawborder)
		[insertion appendString:[self.arrayMatrix objectAtIndex:19]];

	for (j = 0; j < vsize; j++) {
		for (i = 0; i < hsize; i++) {
			[insertion appendString:[self.myMatrix objectInRow:j inCol:[[[matrixColumns objectAtIndex:i] identifier] integerValue] ]];
			if (i < hsize-1)
				[insertion appendString:[self.arrayMatrix objectAtIndex:3]];
		}
		if (j < vsize-1) {
			[insertion appendString:[self.arrayMatrix objectAtIndex:4]];
			if (drawgrid)
				[insertion appendString:[self.arrayMatrix objectAtIndex:19]];
		}

	}
	if (drawborder) {
		[insertion appendString:[self.arrayMatrix objectAtIndex:4]];
		[insertion appendString:[self.arrayMatrix objectAtIndex:19]];
	}

	if (environment == 0) {
		[insertion appendString:[self.arrayMatrix objectAtIndex:5]];
	} else {
		[insertion appendString:[self.arrayMatrix objectAtIndex:18]];
		if (tablenv) {
			[insertion appendString:[self.arrayMatrix objectAtIndex:21]];
		}

	}

	if (environment == 0) {
		if ((brstyleop == 4) && (brstylecl == 4)) {
		} else {
			[insertion appendString:[self.arrayMatrix objectAtIndex:7]];
			if (brstylecl == 0) {
				[insertion appendString:[self.arrayMatrix objectAtIndex:9]];
			} else if (brstylecl == 1) {
				[insertion appendString:[self.arrayMatrix objectAtIndex:11]];
			} else if (brstylecl == 2) {
				[insertion appendString:[self.arrayMatrix objectAtIndex:13]];
			} else if (brstylecl == 3) {
				[insertion appendString:[self.arrayMatrix objectAtIndex:14]];
			} else if (brstylecl == 5) {
				[insertion appendString:[self.arrayMatrix objectAtIndex:15]];
				[insertion appendString:[brtfcl stringValue]];
			} else if (brstylecl == 4) {
				[insertion appendString:[self.arrayMatrix objectAtIndex:15]];
			} else if (brstylecl == 6) {
				[insertion appendString:[self.arrayMatrix objectAtIndex:16]];
			}
		}
	}

	[notifcenter postNotificationName:@"matrixpanel" object:insertion];
}

- (IBAction)envselChange:(id)sender
{
	if ([[sender selectedCell] tag] == 1) {
		[brselcl setEnabled:NO];
		[brselop setEnabled:NO];
		[brtfcl setEnabled:NO];
		[brtfop setEnabled:NO];
		[chbfig setEnabled:YES];
	} else {
		[brselcl setEnabled:YES];
		[brselop setEnabled:YES];
		[brtfcl setEnabled:YES];
		[brtfop setEnabled:YES];
		[chbfig setEnabled:NO];

	}
}

- (IBAction)brselChange:(id)sender
{
	if ([[sender selectedCell] tag] == 5) {
		if (sender == brselop) {
			[brtfop setEnabled:YES];
		} else {
			[brtfcl setEnabled:YES];
		}
	} else {
		if (sender == brselop) {
			[brtfop setEnabled:NO];
		} else {
			[brtfcl setEnabled:NO];
		}
	}
}

- (IBAction)resetMatrix:(id)sender
{
	NSInteger i, j, action;
	NSInteger mwdth, mhght;
	mwdth = [self.myMatrix colCount];
	mhght = [self.myMatrix rowCount];
	
	if (sender == matmod) {
		action = [[sender selectedCell] tag];
		if (action == 2) {
			for (i = 0; i < mhght; i++) {
				for (j = 0; j < mwdth; j++) {
					[self.myMatrix replaceObjectInRow:i inCol:j withObject:@"0"];
				}
			}
		} else if (action == 0) {
			for (i = 0; i < mhght; i++) {
				for (j = 0; j < mwdth; j++) {
					[self.myMatrix replaceObjectInRow:i inCol:j withObject:@" "];
				}
			}
		} else {
			for (i = 0; i < mhght; i++) {
				for (j = 0; j < mwdth; j++) {
					[self.myMatrix replaceObjectInRow:i inCol:j withObject:@"0"];
				}
			}
			for(i = 0; (i < mwdth) && (i < mhght); i++)
				[self.myMatrix replaceObjectInRow:i inCol:[[[[(TSMatrixTableView *)matrixtable matrixColumns] objectAtIndex:i] identifier] integerValue] withObject:@"1"];
			
		}
	}
	[matrixtable reloadData];
	
}



- (void)textWindowDidBecomeKey:(NSNotification *)note
{
	// if matrix panel is hidden, show it
	if (shown)
		[[self window] orderFront:self];
}

- (void)pdfWindowDidBecomeKey:(NSNotification *)note
{
	// if matrix panel is visible, hide it
	if (shown)
		[[self window] orderOut:self];
}

- (IBAction)showWindow:(id)sender
{
	shown = YES;
	[super showWindow:sender];
}

- (void)hideWindow:(id)sender
{
	shown = NO;
	[[self window] close];
}

- (void)panelWillClose:(NSNotification *)notification
{
        shown = NO;
        NSMenuItem *myItem = [[NSApp windowsMenu] itemWithTitle:NSLocalizedString(@"Close Matrix Panel", @"Close Matrix Panel")];
        [myItem  setTitle:NSLocalizedString(@"Matrix Panel...", @"Matrix Panel...")];
        [myItem setTag:0];
}

- (void)panelDidMove:(NSNotification *)notification
{
	NSRect	myFrame;
	CGFloat	x, y;

	myFrame = [[self window] frame];
	x = myFrame.origin.x;
	y = myFrame.origin.y;
	[[NSUserDefaults standardUserDefaults] setFloat:x forKey:MPanelOriginXKey];
	[[NSUserDefaults standardUserDefaults] setFloat:y forKey:MPanelOriginYKey];
	// [[self window] saveFrameUsingName:@"theLatexPanel"];
}


#pragma mark Layout

// The numbers of the rows: a column that cannot be edited, moved or resized, in the font and color of the
// numbers of the columns in the header.
- (void)addRowNumberColumn
{
	NSTableColumn *firstColumn = [[(TSMatrixTableView *)matrixtable matrixColumns] firstObject];
	NSTableHeaderCell *header = [firstColumn headerCell];
	NSFont *font = [header font] ?: [NSFont systemFontOfSize:[NSFont systemFontSize]];
	NSTextFieldCell *cell = [[NSTextFieldCell alloc] init];
	[cell setFont:font];
	[cell setTextColor:[header textColor] ?: [NSColor headerTextColor]];
	[cell setAlignment:NSTextAlignmentCenter];
	[cell setEditable:NO];
	[cell setSelectable:NO];
	NSTableColumn *numbers = [[NSTableColumn alloc] initWithIdentifier:TSMatrixRowNumberColumn];
	[numbers setDataCell:cell];
	[numbers setEditable:NO];
	[[numbers headerCell] setStringValue:@""];
	[numbers setResizingMask:NSTableColumnNoResizing];
	CGFloat width = ceil([@"100" sizeWithAttributes:@{NSFontAttributeName: font}].width) + 12;
	[numbers setMinWidth:width];
	[numbers setMaxWidth:width];
	[numbers setWidth:width];
	[matrixtable addTableColumn:numbers];
	[self keepRowNumberColumnFirst];
}

- (void)keepRowNumberColumnFirst
{
	NSInteger index = [matrixtable columnWithIdentifier:TSMatrixRowNumberColumn];
	if (index > 0)
		[matrixtable moveColumn:index toColumn:0];
}

// The row numbers stay at the left; the columns of the matrix can still be moved among themselves.
- (BOOL)tableView:(NSTableView *)tableView shouldReorderColumn:(NSInteger)columnIndex toColumn:(NSInteger)newColumnIndex
{
	NSInteger numbers = [tableView columnWithIdentifier:TSMatrixRowNumberColumn];
	return columnIndex != numbers && newColumnIndex != numbers;
}

// The first row starts below the header, where the scroll view's insets put the top of the table.
- (void)scrollTableToTop
{
	[[[self window] contentView] layoutSubtreeIfNeeded];
	NSClipView *clip = [(NSScrollView *)mtscrv contentView];
	[clip scrollToPoint:NSMakePoint(NSMinX([clip bounds]), -[clip contentInsets].top)];
	[mtscrv reflectScrolledClipView:clip];
}

static const CGFloat TSMatrixPanelMargin = 20;

static NSFont *TSMatrixPanelFont(void)
{
	return [NSFont systemFontOfSize:[NSFont systemFontSizeForControlSize:NSControlSizeRegular]];
}

// Matrices of radio buttons or push buttons in the regular size, every cell as large as the largest one, so
// that their columns line up.
static void TSFitMatrices(NSArray<NSMatrix *> *matrices, NSSize spacing)
{
	NSSize size = NSZeroSize;
	for (NSMatrix *matrix in matrices)
		for (NSCell *cell in [matrix cells]) {
			[cell setControlSize:NSControlSizeRegular];
			[cell setFont:TSMatrixPanelFont()];
			NSSize fit = [cell cellSize];
			size.width = MAX(size.width, ceil(fit.width));
			size.height = MAX(size.height, ceil(fit.height));
		}
	for (NSMatrix *matrix in matrices) {
		[matrix setCellSize:size];
		[matrix setIntercellSpacing:spacing];
		[matrix sizeToCells];
	}
}

static void TSPrepareControl(NSControl *control)
{
	[control setControlSize:NSControlSizeRegular];
	[control setFont:TSMatrixPanelFont()];
}

static void TSFixSize(NSView *view, NSSize size)
{
	[NSLayoutConstraint activateConstraints:@[[[view widthAnchor] constraintEqualToConstant:size.width],
											  [[view heightAnchor] constraintEqualToConstant:size.height]]];
}

// The controls in the regular size of macOS, laid out with the usual spacing whatever the language: the
// compiled panels of the localizations place them in small and mini sizes, some touching each other.
- (void)arrangeControls
{
	NSWindow *window = [self window];
	NSView *content = [window contentView];
	const CGFloat margin = TSMatrixPanelMargin;

	// The views without an outlet: the environment's box, the labels of the size, the line above the buttons
	// and the Insert button.
	NSBox *environmentBox = nil;
	for (NSView *view = [envsel superview]; view != nil && environmentBox == nil; view = [view superview])
		if ([view isKindOfClass:[NSBox class]])
			environmentBox = (NSBox *)view;
	NSMutableArray<NSTextField *> *labels = [NSMutableArray array];
	NSButton *insertButton = nil;
	for (NSView *view in [[content subviews] copy]) {
		if ([view isKindOfClass:[NSBox class]] && view != environmentBox)
			[view removeFromSuperview];
		else if ([view isKindOfClass:[NSTextField class]] && ![(NSTextField *)view isEditable])
			[labels addObject:(NSTextField *)view];
		else if ([view isKindOfClass:[NSButton class]] && [(NSButton *)view action] == @selector(insertMatrix:))
			insertButton = (NSButton *)view;
	}
	if (environmentBox == nil || [labels count] != 2 || insertButton == nil)
		return;
	// The label nearer the rows field names the rows.
	NSPoint rowsField = NSMakePoint(NSMidX([vtf frame]), NSMidY([vtf frame]));
	[labels sortUsingComparator:^NSComparisonResult(NSTextField *a, NSTextField *b) {
		CGFloat da = hypot(NSMidX([a frame]) - rowsField.x, NSMidY([a frame]) - rowsField.y);
		CGFloat db = hypot(NSMidX([b frame]) - rowsField.x, NSMidY([b frame]) - rowsField.y);
		return da < db ? NSOrderedAscending : da > db ? NSOrderedDescending : NSOrderedSame;
	}];
	NSTextField *rowsLabel = labels[0], *columnsLabel = labels[1];

	// The environment's choices lose their box; its title becomes a heading above them.
	NSTextField *heading = [NSTextField labelWithString:[environmentBox title]];
	[heading setFont:[NSFont boldSystemFontOfSize:[NSFont systemFontSize]]];
	[content addSubview:heading];
	[content addSubview:envsel];
	[content addSubview:chbfig];
	[environmentBox removeFromSuperview];

	TSFitMatrices(@[envsel], NSMakeSize(20, 0));
	TSFitMatrices(@[brselop, brselcl], NSMakeSize(12, 0));
	TSFitMatrices(@[matmod], NSMakeSize(12, 0));
	for (NSControl *control in @[chbfig, rowsLabel, columnsLabel, vtf, htf, vstep, hstep, brtfop, brtfcl, insertButton])
		TSPrepareControl(control);

	// The examples of a border and a grid: buttons that stay pressed, their pictures in the color of the text.
	for (NSButton *button in @[borderbutton, gridbutton]) {
		NSImage *image = [[button image] copy];
		[image setTemplate:YES];
		[button setButtonType:NSButtonTypePushOnPushOff];
		[button setBezelStyle:NSBezelStyleFlexiblePush];
		[button setImage:image];
		[button setImagePosition:NSImageOnly];
	}
	// Insert is the default button, as wide as the buttons beside it.
	[insertButton setKeyEquivalent:@"\r"];

	NSArray<NSView *> *arranged = @[heading, envsel, chbfig, mtscrv, rowsLabel, vtf, vstep, columnsLabel, htf, hstep,
									brselop, brtfop, brselcl, brtfcl, borderbutton, gridbutton, matmod, insertButton];
	for (NSView *view in arranged)
		[view setTranslatesAutoresizingMaskIntoConstraints:NO];
	for (NSMatrix *matrix in @[envsel, brselop, brselcl, matmod])
		TSFixSize(matrix, [matrix frame].size);
	NSSize picture = [[borderbutton image] size];
	for (NSButton *button in @[borderbutton, gridbutton])
		TSFixSize(button, NSMakeSize(ceil(picture.width) + 12, ceil(picture.height) + 8));
	for (NSTextField *field in @[vtf, htf, brtfop, brtfcl])
		[[[field widthAnchor] constraintEqualToConstant:48] setActive:YES];

	NSTableView *table = matrixtable;
	CGFloat row = [table rowHeight] + [table intercellSpacing].height;
	CGFloat header = NSHeight([[table headerView] frame]);
	NSLayoutConstraint *tableHeight = [[mtscrv heightAnchor] constraintGreaterThanOrEqualToConstant:ceil(header + 4 * row + 2)];

	NSLayoutGuide *delimiters = [NSLayoutGuide new];
	[content addLayoutGuide:delimiters];
	NSLayoutAnchor *leading = [content leadingAnchor], *trailing = [content trailingAnchor];
	[NSLayoutConstraint activateConstraints:@[
		[[heading topAnchor] constraintEqualToAnchor:[content topAnchor] constant:margin],
		[[heading leadingAnchor] constraintEqualToAnchor:leading constant:margin],
		[[heading trailingAnchor] constraintLessThanOrEqualToAnchor:trailing constant:-margin],

		[[envsel topAnchor] constraintEqualToAnchor:[heading bottomAnchor] constant:8],
		[[envsel leadingAnchor] constraintEqualToAnchor:leading constant:margin],
		[[chbfig centerYAnchor] constraintEqualToAnchor:[envsel centerYAnchor]],
		[[chbfig leadingAnchor] constraintEqualToAnchor:[envsel trailingAnchor] constant:20],
		[[chbfig trailingAnchor] constraintLessThanOrEqualToAnchor:trailing constant:-margin],

		[[mtscrv topAnchor] constraintGreaterThanOrEqualToAnchor:[envsel bottomAnchor] constant:16],
		[[mtscrv topAnchor] constraintGreaterThanOrEqualToAnchor:[chbfig bottomAnchor] constant:16],
		[[mtscrv leadingAnchor] constraintEqualToAnchor:leading constant:margin],
		[[mtscrv trailingAnchor] constraintEqualToAnchor:trailing constant:-margin],
		tableHeight,

		[[vtf topAnchor] constraintEqualToAnchor:[mtscrv bottomAnchor] constant:12],
		[[rowsLabel leadingAnchor] constraintEqualToAnchor:leading constant:margin],
		[[rowsLabel firstBaselineAnchor] constraintEqualToAnchor:[vtf firstBaselineAnchor]],
		[[vtf leadingAnchor] constraintEqualToAnchor:[rowsLabel trailingAnchor] constant:8],
		[[vstep leadingAnchor] constraintEqualToAnchor:[vtf trailingAnchor] constant:4],
		[[vstep centerYAnchor] constraintEqualToAnchor:[vtf centerYAnchor]],
		[[columnsLabel leadingAnchor] constraintEqualToAnchor:[vstep trailingAnchor] constant:20],
		[[columnsLabel firstBaselineAnchor] constraintEqualToAnchor:[vtf firstBaselineAnchor]],
		[[htf leadingAnchor] constraintEqualToAnchor:[columnsLabel trailingAnchor] constant:8],
		[[htf centerYAnchor] constraintEqualToAnchor:[vtf centerYAnchor]],
		[[hstep leadingAnchor] constraintEqualToAnchor:[htf trailingAnchor] constant:4],
		[[hstep centerYAnchor] constraintEqualToAnchor:[vtf centerYAnchor]],
		[[hstep trailingAnchor] constraintLessThanOrEqualToAnchor:trailing constant:-margin],

		// The delimiters on the left and right of the matrix, each followed by its own field.
		[[brselop topAnchor] constraintGreaterThanOrEqualToAnchor:[vtf bottomAnchor] constant:16],
		[[brselop topAnchor] constraintGreaterThanOrEqualToAnchor:[vstep bottomAnchor] constant:16],
		[[brselop leadingAnchor] constraintEqualToAnchor:leading constant:margin],
		[[brselcl topAnchor] constraintGreaterThanOrEqualToAnchor:[brselop bottomAnchor] constant:8],
		[[brtfcl topAnchor] constraintGreaterThanOrEqualToAnchor:[brtfop bottomAnchor] constant:8],
		[[brselcl leadingAnchor] constraintEqualToAnchor:leading constant:margin],
		[[brtfop leadingAnchor] constraintEqualToAnchor:[brselop trailingAnchor] constant:4],
		[[brtfop centerYAnchor] constraintEqualToAnchor:[brselop centerYAnchor]],
		[[brtfcl leadingAnchor] constraintEqualToAnchor:[brselcl trailingAnchor] constant:4],
		[[brtfcl centerYAnchor] constraintEqualToAnchor:[brselcl centerYAnchor]],
		[[delimiters topAnchor] constraintEqualToAnchor:[brtfop topAnchor]],
		[[delimiters bottomAnchor] constraintEqualToAnchor:[brtfcl bottomAnchor]],
		[[brtfop topAnchor] constraintGreaterThanOrEqualToAnchor:[vtf bottomAnchor] constant:16],

		// The border and grid buttons at the right, centered on the two rows of delimiters.
		[[gridbutton trailingAnchor] constraintEqualToAnchor:trailing constant:-margin],
		[[borderbutton trailingAnchor] constraintEqualToAnchor:[gridbutton leadingAnchor] constant:-8],
		[[borderbutton leadingAnchor] constraintGreaterThanOrEqualToAnchor:[brtfop trailingAnchor] constant:20],
		[[borderbutton leadingAnchor] constraintGreaterThanOrEqualToAnchor:[brtfcl trailingAnchor] constant:20],
		[[borderbutton centerYAnchor] constraintEqualToAnchor:[delimiters centerYAnchor]],
		[[gridbutton centerYAnchor] constraintEqualToAnchor:[delimiters centerYAnchor]],
		[[borderbutton topAnchor] constraintGreaterThanOrEqualToAnchor:[vtf bottomAnchor] constant:12],

		// Clear, Identity and Zero on the left, Insert on the right.
		[[matmod topAnchor] constraintGreaterThanOrEqualToAnchor:[brselcl bottomAnchor] constant:20],
		[[matmod topAnchor] constraintGreaterThanOrEqualToAnchor:[brtfcl bottomAnchor] constant:20],
		[[matmod topAnchor] constraintGreaterThanOrEqualToAnchor:[gridbutton bottomAnchor] constant:20],
		[[matmod leadingAnchor] constraintEqualToAnchor:leading constant:margin],
		[[matmod bottomAnchor] constraintEqualToAnchor:[content bottomAnchor] constant:-margin],
		[[insertButton centerYAnchor] constraintEqualToAnchor:[matmod centerYAnchor]],
		[[insertButton trailingAnchor] constraintEqualToAnchor:trailing constant:-margin],
		[[insertButton leadingAnchor] constraintGreaterThanOrEqualToAnchor:[matmod trailingAnchor] constant:20],
		[[insertButton widthAnchor] constraintGreaterThanOrEqualToConstant:[matmod cellSize].width],
	]];
	// The rows below the table keep their places; the table takes the rest of the height.
	for (NSLayoutConstraint *constraint in @[[[mtscrv topAnchor] constraintEqualToAnchor:[envsel bottomAnchor] constant:16],
											 [[brtfop topAnchor] constraintEqualToAnchor:[vtf bottomAnchor] constant:16],
											 [[brselcl topAnchor] constraintEqualToAnchor:[brselop bottomAnchor] constant:8],
											 [[matmod topAnchor] constraintEqualToAnchor:[brtfcl bottomAnchor] constant:20]]) {
		[constraint setPriority:NSLayoutPriorityDefaultHigh];
		[constraint setActive:YES];
	}

	// The smallest size shows four rows of the table; the panel opens with at least eight.
	NSSize smallest = [content fittingSize];
	NSSize size = [content frame].size;
	size.width = MAX(size.width, smallest.width);
	size.height = MAX(size.height, smallest.height + 4 * row);
	[window setContentMinSize:smallest];
	NSSize largest = [window contentRectForFrameRect:NSMakeRect(0, 0, [window maxSize].width, [window maxSize].height)].size;
	[window setContentMaxSize:NSMakeSize(MAX(largest.width, size.width), MAX(largest.height, size.height))];
	[window setContentSize:size];
	[content layoutSubtreeIfNeeded];
}

@end



@implementation MatrixData

-(id) init
{
	if ((self = [super init])) {
		self.rows = [[NSMutableArray alloc] init];
		activeRows = 0;
		activeCols = 0;
	}
	return self;
}

/*
- (void)dealloc
{
	[rows release];
	[super dealloc];
}
*/

/*

- (NSMutableArray*)rows
{
	return rows;
}
*/

- (NSInteger)actRows
{
	return activeRows;
}

-(void)setActRows:(NSInteger)num
{
	activeRows=num;
}

- (NSInteger)actCols
{
	return activeCols;
}

-(void)setActCols:(NSInteger)num
{
	activeCols = num;
}

-(id)myRowAtIndex:(NSUInteger)row
{
	return [self.rows objectAtIndex:row];  //retain];
}

-(NSInteger)rowCount
{
	return [self.rows count];
}

-(NSInteger)colCount
{
	if ([self rowCount]==0)
		return 0;
	return [[self myRowAtIndex:0] count];
}

-(id)objectInRow:(NSUInteger)row inCol:(NSUInteger)col
{
	return [[self myRowAtIndex:row] objectAtIndex:col];
}

-(void)replaceObjectInRow:(NSUInteger)row inCol:(NSUInteger)col withObject:(id) anObj{
	[[self myRowAtIndex:row] replaceObjectAtIndex:col withObject:anObj];
}

-(void)addRow
{
	NSInteger i;
	[self.rows addObject:[NSMutableArray arrayWithCapacity:[self colCount]]]; //retain]];
	for (i = [[self.rows objectAtIndex:[self.rows count]-1] count]; i < [self colCount]; i++) {
		[[self.rows objectAtIndex:[self.rows count]-1] addObject:@"0"];
	}
	activeRows++;

}

- (void)insertRow:(NSMutableArray*)row atIndex:(NSInteger)ind
{
	[self.rows insertObject:row atIndex:ind];
}

- (void)removeRow:(id )row
{
	[self.rows removeObject:row];
}

- (void)removeRowIdenticalTo:(id)row
{
	[self.rows removeObjectIdenticalTo:row];
}

- (void)removeRowAtIndex:(NSUInteger )ind
{
	[self.rows removeObjectAtIndex:ind];
}

-(void)addCol
{
	NSInteger i;
	for (i = 0; i < [self rowCount]; i++) {
 		[[self myRowAtIndex:i] addObject:@"0"];
	}
	activeCols++;
}

-(void)removeLastCol
{
	NSInteger i;
	for (i = 0; i < [self rowCount]; i++) {
		[[self myRowAtIndex:i] removeLastObject];
	}
	activeCols--;
}

-(void)removeLastRow
{
	[self.rows removeLastObject];
	activeRows--;
}

@end
