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
 * $Id: TSMatrixTableView.m 108 2006-02-10 13:50:25Z fingolfin $
 *
 */

#import "TSMatrixTableView.h"
#import "TSMatrixPanelController.h"

NSString *const TSMatrixRowNumberColumn = @"col";

// The cells that are inserted are shown on blue, in light and dark appearance.
static NSColor *StripeColor(void)
{
	return [NSColor.systemBlueColor colorWithAlphaComponent:0.14];
}

@implementation TSMatrixTableView

/*
-(NSDragOperation)draggingSourceOperationMaskForLocal:(BOOL)isLocal
{
	if (isLocal) return NSDragOperationEvery;
	else return NSDragOperationCopy;
}
*/

-(BOOL)ignoreModifierKeysWhileDragging
{
	return YES;
}

// The selection is not shown: the cells that are inserted are shown on blue instead. The table follows
// the light or dark appearance.
- (void)awakeFromNib
{
	[super awakeFromNib];
	[self setSelectionHighlightStyle:NSTableViewSelectionHighlightStyleNone];
	// The compiled panels give the table a fixed white background.
	[self setBackgroundColor:[NSColor controlBackgroundColor]];
}

- (void)drawBackgroundInClipRect:(NSRect)clipRect
{
	[super drawBackgroundInClipRect:clipRect];
	[self drawStripesInRect:clipRect];
}

-(void) reloadData
{
	[super reloadData];
	NSInteger i = 0, actCols = [[(TSMatrixPanelController *)[self dataSource] theMatrix] actCols];
	for (NSTableColumn *column in [self matrixColumns]) {
		if (i >= actCols)
			[column setDataCell:[[InactiveTextFieldCell alloc] init]];
		else
			[column setDataCell:[[ActiveTextFieldCell alloc] init]];
		i++;
	}
}

- (NSArray<NSTableColumn *> *)matrixColumns
{
	NSMutableArray<NSTableColumn *> *columns = [NSMutableArray array];
	for (NSTableColumn *column in [self tableColumns])
		if (![[column identifier] isEqualToString:TSMatrixRowNumberColumn])
			[columns addObject:column];
	return columns;
}

-(id)init
{
	if ((self = [super init])) {
		[self setDataSource:[MatrixData init]];
	}
	return self;
}

// draw background of area of tableview, which will be inserted

- (void) drawStripesInRect:(NSRect)clipRect
{
	NSInteger actCols = [[(TSMatrixPanelController *)[self dataSource] theMatrix] actCols];
	NSInteger actRows = [[(TSMatrixPanelController *)[self dataSource] theMatrix] actRows];
	NSArray<NSTableColumn *> *columns = [self matrixColumns];
	if (actCols < 1 || actRows < 1 || [columns count] == 0 || [self numberOfRows] == 0)
		return;
	actCols = MIN(actCols, (NSInteger)[columns count]);
	// From the first column of the matrix to the last one inserted, and from the top to the last row inserted.
	NSRect first = [self rectOfColumn:[[self tableColumns] indexOfObject:[columns objectAtIndex:0]]];
	NSRect last = [self rectOfColumn:[[self tableColumns] indexOfObject:[columns objectAtIndex:actCols - 1]]];
	NSRect lastRow = [self rectOfRow:MIN(actRows, [self numberOfRows]) - 1];
	NSRect stripes = NSMakeRect(NSMinX(first), 0, NSMaxX(last) - NSMinX(first), NSMaxY(lastRow));
	[StripeColor() set];
	NSRectFillUsingOperation(NSIntersectionRect(stripes, clipRect), NSCompositingOperationSourceOver);
}

@end

/*
//Old
 
 @implementation InactiveTextFieldCell
 
 -(id)init
 {
 if ((self = [super init])) {
 [self setTextColor:[NSColor colorWithCalibratedWhite:0.827 alpha:1]];
 [self setEditable:YES];
 [self setEnabled:YES];
 [self setDrawsBackground:YES];
 [self setBackgroundColor:[NSColor colorWithCalibratedRed:1 green:1 blue:.985 alpha:1]];
 }
 return self;
 }
 
 @end
 
 
 
 @implementation ActiveTextFieldCell
 
 -(id)init
 {
 if ((self = [super init])) {
 //[self setTextColor:[NSColor disabledControlTextColor]];
 [self setEditable:YES];
 [self setDrawsBackground:NO];
 // [self setBackgroundColor:[NSColor blueColor]];
 }
 return self;
 }
 */

@implementation InactiveTextFieldCell

-(id)init
{
	if ((self = [super init])) {
		[self setTextColor:[NSColor tertiaryLabelColor]];
		[self setEditable:YES];
		[self setEnabled:YES];
		[self setDrawsBackground:NO];
	}
	return self;
}

@end



@implementation ActiveTextFieldCell

-(id)init
{
	if ((self = [super init])) {
		// [self setTextColor:[NSColor disabledControlTextColor]];
        [self setTextColor:[NSColor systemRedColor]];
        // [self setTextColor:[NSColor colorWithCalibratedWhite:0.011 alpha:1]];
       // [self setTextColor:[NSColor blackColor]];
 		[self setEditable:YES];
		[self setDrawsBackground:NO];
	   // [self setBackgroundColor:[NSColor blueColor]];
	}
	return self;
}

@end



@implementation MatrixTableColumn

-(id) init
{
	return [self initWithIdentifier:@"0"];
}

- (id)initWithIdentifier:(id)identifier
{
	if ((self = [super initWithIdentifier:identifier])) {
		//[_inactiveDataCell init];
		
		// FIXME: BAD HACK! We are directly accessing a member variable of NSTextFieldCell here!
		self.dataCell = [[ActiveTextFieldCell alloc] init];
		
		_inactiveDataCell = [[InactiveTextFieldCell alloc] init];
	}
	return self;
}

-(id)dataCellForRow:(NSInteger)row
{
	// NSTextFieldCell *acell=[self dataCell];
	if ([self tableView] == nil || row == -1) {
		return [self dataCell];
	} else {
		if (([[(TSMatrixPanelController *)[[self tableView] dataSource] theMatrix] actRows] <= row) ) {
			return _inactiveDataCell;
		}
	}
	return [self dataCell];
}

@end
