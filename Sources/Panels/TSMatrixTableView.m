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

// Tab separated text as spreadsheets copy it: a line for each row, a tab between the cells; a cell that holds a
// tab, a line break or starts with a quote is in quotes, with its quotes doubled.
static NSArray<NSArray<NSString *> *> *TSMatrixParseTabular(NSString *text)
{
	NSMutableArray<NSArray<NSString *> *> *rows = [NSMutableArray array];
	NSMutableArray<NSString *> *row = [NSMutableArray array];
	NSMutableString *cell = [NSMutableString string];
	NSCharacterSet *breaks = [NSCharacterSet characterSetWithCharactersInString:@"\t\r\n"];
	NSUInteger i = 0, n = [text length];
	BOOL atCellStart = YES;
	while (i < n) {
		unichar c = [text characterAtIndex:i];
		if (atCellStart && c == '"') {
			NSMutableString *quoted = [NSMutableString string];
			NSUInteger j = i + 1;
			BOOL closed = NO;
			while (j < n) {
				NSRange quote = [text rangeOfString:@"\"" options:NSLiteralSearch range:NSMakeRange(j, n - j)];
				if (quote.location == NSNotFound)
					break;
				[quoted appendString:[text substringWithRange:NSMakeRange(j, quote.location - j)]];
				if (quote.location + 1 < n && [text characterAtIndex:quote.location + 1] == '"') {
					[quoted appendString:@"\""];
					j = quote.location + 2;
				} else {
					closed = YES;
					j = quote.location + 1;
					break;
				}
			}
			// A quote that does not close the cell is part of its text.
			if (closed && (j == n || [breaks characterIsMember:[text characterAtIndex:j]])) {
				[cell setString:quoted];
				i = j;
				atCellStart = NO;
				continue;
			}
		}
		atCellStart = NO;
		if (c == '\t') {
			[row addObject:[cell copy]];
			[cell setString:@""];
			atCellStart = YES;
			i++;
		} else if (c == '\r' || c == '\n') {
			[row addObject:[cell copy]];
			[cell setString:@""];
			[rows addObject:row];
			row = [NSMutableArray array];
			atCellStart = YES;
			i += (c == '\r' && i + 1 < n && [text characterAtIndex:i + 1] == '\n') ? 2 : 1;
		} else {
			NSRange next = [text rangeOfCharacterFromSet:breaks options:NSLiteralSearch range:NSMakeRange(i, n - i)];
			NSUInteger stop = next.location == NSNotFound ? n : next.location;
			[cell appendString:[text substringWithRange:NSMakeRange(i, stop - i)]];
			i = stop;
		}
	}
	if (!atCellStart || [row count] > 0) {
		[row addObject:[cell copy]];
		[rows addObject:row];
	}
	return rows;
}

static NSString *TSMatrixTabularString(NSArray<NSArray<NSString *> *> *rows)
{
	NSCharacterSet *special = [NSCharacterSet characterSetWithCharactersInString:@"\t\r\n"];
	NSMutableArray<NSString *> *lines = [NSMutableArray array];
	for (NSArray<NSString *> *row in rows) {
		NSMutableArray<NSString *> *cells = [NSMutableArray array];
		for (NSString *cell in row) {
			if ([cell rangeOfCharacterFromSet:special].location != NSNotFound || [cell hasPrefix:@"\""])
				[cells addObject:[NSString stringWithFormat:@"\"%@\"", [cell stringByReplacingOccurrencesOfString:@"\"" withString:@"\"\""]]];
			else
				[cells addObject:cell];
		}
		[lines addObject:[cells componentsJoinedByString:@"\t"]];
	}
	return [lines componentsJoinedByString:@"\n"];
}

@implementation TSMatrixTableView
{
	NSInteger _tabStartColumn;	// the column where a row of Tabs started, where Return comes back to
	BOOL _replacing;			// editing started by typing: the arrow keys end it and move on, as in a spreadsheet
	BOOL _endingEditing;
}

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

// The table's own selection is not shown: the cell and the range chosen are drawn instead, and the cells
// that are inserted are shown on blue. The table follows the light or dark appearance.
- (void)awakeFromNib
{
	[super awakeFromNib];
	[self setSelectionHighlightStyle:NSTableViewSelectionHighlightStyleNone];
	// The compiled panels give the table a fixed white background.
	[self setBackgroundColor:[NSColor controlBackgroundColor]];
	[self setAllowsColumnSelection:NO];
	[self setAllowsEmptySelection:YES];
	[self setAllowsMultipleSelection:YES];
	[self setAllowsTypeSelect:NO];
	_tabStartColumn = -1;
}

- (TSMatrixPanelController *)controller
{
	return (TSMatrixPanelController *)[self dataSource];
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

#pragma mark Cells and ranges

- (NSInteger)tableColumnIndexOfShownColumn:(NSInteger)column
{
	NSArray<NSTableColumn *> *columns = [self matrixColumns];
	if (column < 0 || column >= (NSInteger)[columns count])
		return -1;
	return [[self tableColumns] indexOfObject:columns[column]];
}

// The column of the matrix at an index of the table, or -1 for the row numbers.
- (NSInteger)shownColumnOfTableColumnIndex:(NSInteger)index
{
	if (index < 0 || index >= [self numberOfColumns])
		return -1;
	NSUInteger column = [[self matrixColumns] indexOfObject:[self tableColumns][index]];
	return column == NSNotFound ? -1 : (NSInteger)column;
}

- (NSRange)selectedRows
{
	NSInteger first = MIN(_activeRow, _extentRow), last = MAX(_activeRow, _extentRow);
	return NSMakeRange(first, last - first + 1);
}

- (NSRange)selectedColumns
{
	NSInteger first = MIN(_activeColumn, _extentColumn), last = MAX(_activeColumn, _extentColumn);
	return NSMakeRange(first, last - first + 1);
}

- (void)scrollToRow:(NSInteger)row column:(NSInteger)column
{
	if (row >= 0 && row < [self numberOfRows])
		[self scrollRowToVisible:row];
	NSInteger index = [self tableColumnIndexOfShownColumn:column];
	if (index >= 0)
		[self scrollColumnToVisible:index];
}

- (void)selectRow:(NSInteger)row column:(NSInteger)column extending:(BOOL)extend
{
	row = MIN(MAX(row, 0), TSMatrixLargestSize - 1);
	column = MIN(MAX(column, 0), TSMatrixLargestSize - 1);
	// Going past the last row or column adds one, as far as the largest size.
	[[self controller] growGridToRows:row + 1 columns:column + 1];
	if (!extend) {
		_activeRow = row;
		_activeColumn = column;
	}
	_extentRow = row;
	_extentColumn = column;
	[self scrollToRow:row column:column];
	[self setNeedsDisplay:YES];
}

- (void)selectRows:(NSRange)rows columns:(NSRange)columns
{
	if (rows.length == 0 || columns.length == 0)
		return;
	_activeRow = rows.location;
	_activeColumn = columns.location;
	_extentRow = NSMaxRange(rows) - 1;
	_extentColumn = NSMaxRange(columns) - 1;
	[self setNeedsDisplay:YES];
}

- (void)selectWholeRows:(NSRange)rows
{
	NSInteger columns = [[self controller] gridColumns];
	if (rows.length == 0 || columns == 0)
		return;
	[self selectRows:rows columns:NSMakeRange(0, columns)];
	[self scrollRowToVisible:_extentRow];
	[self scrollRowToVisible:_activeRow];
}

- (BOOL)wholeRowsSelected
{
	NSRange columns = [self selectedColumns];
	return columns.location == 0 && (NSInteger)columns.length == [[self controller] gridColumns];
}

- (void)selectWholeColumn:(NSInteger)column extending:(BOOL)extend
{
	NSInteger rows = [[self controller] gridRows];
	if (column < 0 || rows == 0)
		return;
	if (!extend)
		_activeColumn = column;
	_extentColumn = column;
	_activeRow = 0;
	_extentRow = rows - 1;
	_tabStartColumn = -1;
	[self scrollToRow:0 column:column];
	[self setNeedsDisplay:YES];
}

- (void)selectAll:(id)sender
{
	[self endCellEditing];
	[self selectRows:NSMakeRange(0, [[self controller] gridRows]) columns:NSMakeRange(0, [[self controller] gridColumns])];
}

#pragma mark Drawing the cell and the range chosen

- (NSRect)rectOfRows:(NSRange)rows columns:(NSRange)columns
{
	if (rows.length == 0 || columns.length == 0 || (NSInteger)NSMaxRange(rows) > [self numberOfRows])
		return NSZeroRect;
	NSInteger first = [self tableColumnIndexOfShownColumn:columns.location], last = [self tableColumnIndexOfShownColumn:NSMaxRange(columns) - 1];
	if (first < 0 || last < 0)
		return NSZeroRect;
	NSRect top = [self rectOfRow:rows.location], bottom = [self rectOfRow:NSMaxRange(rows) - 1];
	CGFloat left = NSMinX([self rectOfColumn:first]), right = NSMaxX([self rectOfColumn:last]);
	return NSMakeRect(left, NSMinY(top), right - left, NSMaxY(bottom) - NSMinY(top));
}

- (BOOL)showsFocus
{
	NSWindow *window = [self window];
	return [window isKeyWindow] && ([window firstResponder] == self || [self currentEditor] != nil);
}

- (void)drawRect:(NSRect)dirtyRect
{
	[super drawRect:dirtyRect];
	NSRect range = [self rectOfRows:[self selectedRows] columns:[self selectedColumns]];
	NSRect active = [self rectOfRows:NSMakeRange(_activeRow, 1) columns:NSMakeRange(_activeColumn, 1)];
	if (NSIsEmptyRect(range) || NSIsEmptyRect(active))
		return;
	NSColor *color = [self showsFocus] ? [NSColor controlAccentColor] : [NSColor secondaryLabelColor];
	// The range is tinted except the cell chosen, and framed, as in a spreadsheet.
	if (!NSEqualRects(range, active)) {
		NSBezierPath *tint = [NSBezierPath bezierPathWithRect:range];
		[tint appendBezierPathWithRect:active];
		[tint setWindingRule:NSWindingRuleEvenOdd];
		[[color colorWithAlphaComponent:0.15] set];
		[tint fill];
	}
	NSBezierPath *frame = [NSBezierPath bezierPathWithRect:NSInsetRect(range, 1, 1)];
	[frame setLineWidth:2];
	[color set];
	[frame stroke];
}

- (BOOL)becomeFirstResponder
{
	BOOL became = [super becomeFirstResponder];
	[self setNeedsDisplay:YES];
	return became;
}

- (BOOL)resignFirstResponder
{
	BOOL resigned = [super resignFirstResponder];
	[self setNeedsDisplay:YES];
	return resigned;
}

- (void)viewWillMoveToWindow:(NSWindow *)window
{
	[[NSNotificationCenter defaultCenter] removeObserver:self name:NSWindowDidBecomeKeyNotification object:nil];
	[[NSNotificationCenter defaultCenter] removeObserver:self name:NSWindowDidResignKeyNotification object:nil];
	if (window != nil) {
		[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(windowKeyChanged:) name:NSWindowDidBecomeKeyNotification object:window];
		[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(windowKeyChanged:) name:NSWindowDidResignKeyNotification object:window];
	}
	[super viewWillMoveToWindow:window];
}

- (void)windowKeyChanged:(NSNotification *)note
{
	[self setNeedsDisplay:YES];
}

#pragma mark Mouse

- (void)mouseDown:(NSEvent *)event
{
	NSPoint point = [self convertPoint:[event locationInWindow] fromView:nil];
	NSInteger row = [self rowAtPoint:point], index = [self columnAtPoint:point];
	BOOL shift = ([event modifierFlags] & NSEventModifierFlagShift) != 0;
	[self endCellEditing];
	[[self window] makeFirstResponder:self];
	_tabStartColumn = -1;
	if (row < 0 || index < 0)
		return;
	NSInteger column = [self shownColumnOfTableColumnIndex:index];
	if (column < 0) {
		// The row numbers: a click chooses the row, Shift adds the rows up to it, a drag moves the rows chosen.
		NSRange rows = [self selectedRows];
		if (shift)
			[self selectWholeRows:NSMakeRange(MIN(_activeRow, row), labs(_activeRow - row) + 1)];
		else if (![self wholeRowsSelected] || !NSLocationInRange(row, rows))
			[self selectWholeRows:NSMakeRange(row, 1)];
		NSRange chosen = [self selectedRows];
		[self selectRowIndexes:[NSIndexSet indexSetWithIndexesInRange:chosen] byExtendingSelection:NO];
		self.rowDragStarted = NO;
		[super mouseDown:event];
		if (!self.rowDragStarted && !shift)
			[self selectWholeRows:NSMakeRange(row, 1)];
		[[self window] makeFirstResponder:self];
		return;
	}
	if ([event clickCount] >= 2) {
		[self selectRow:row column:column extending:NO];
		[self editCellReplacing:NO event:event];
		return;
	}
	[self selectRow:row column:column extending:shift];
	// A drag chooses a range.
	while (YES) {
		NSEvent *next = [[self window] nextEventMatchingMask:NSEventMaskLeftMouseDragged | NSEventMaskLeftMouseUp];
		if (next == nil || [next type] == NSEventTypeLeftMouseUp)
			break;
		[self autoscroll:next];
		NSPoint at = [self convertPoint:[next locationInWindow] fromView:nil];
		NSInteger r = [self rowAtPoint:at], i = [self columnAtPoint:at];
		if (r < 0)
			r = at.y < NSMinY([self rectOfRow:0]) ? 0 : [self numberOfRows] - 1;
		NSInteger c = [self shownColumnOfTableColumnIndex:i];
		if (c < 0) {
			NSRect first = [self rectOfColumn:[self tableColumnIndexOfShownColumn:0]];
			c = (i >= 0 || at.x < NSMinX(first)) ? 0 : [[self matrixColumns] count] - 1;
		}
		[self selectRow:r column:c extending:YES];
	}
}

// Only the row numbers move rows.
- (BOOL)canDragRowsWithIndexes:(NSIndexSet *)rowIndexes atPoint:(NSPoint)mouseDownPoint
{
	return [self shownColumnOfTableColumnIndex:[self columnAtPoint:mouseDownPoint]] < 0 && [super canDragRowsWithIndexes:rowIndexes atPoint:mouseDownPoint];
}

#pragma mark Editing

- (void)editActiveCellReplacing:(BOOL)replace
{
	[self editCellReplacing:replace event:nil];
}

- (void)editCellReplacing:(BOOL)replace event:(NSEvent *)event
{
	NSInteger index = [self tableColumnIndexOfShownColumn:_activeColumn];
	if (index < 0 || _activeRow >= [self numberOfRows])
		return;
	_extentRow = _activeRow;
	_extentColumn = _activeColumn;
	[self scrollToRow:_activeRow column:_activeColumn];
	[self selectRowIndexes:[NSIndexSet indexSetWithIndex:_activeRow] byExtendingSelection:NO];
	_replacing = replace;
	[self editColumn:index row:_activeRow withEvent:event select:replace];
	NSText *editor = [self currentEditor];
	if (!replace && event == nil)
		[editor setSelectedRange:NSMakeRange([[editor string] length], 0)];
	[self setNeedsDisplay:YES];
}

// Ends the editing of a cell, keeping what was typed.
- (BOOL)endCellEditing
{
	if ([self currentEditor] == nil)
		return YES;
	_endingEditing = YES;
	BOOL ended = [[self window] makeFirstResponder:self];
	_endingEditing = NO;
	return ended;
}

// What was typed in a cell is undone as a change of the matrix, not as typing in an editor that is gone.
- (void)forgetTypingIn:(NSText *)editor
{
	NSUndoManager *undo = [[self window] undoManager];
	if (editor == nil || undo == nil)
		return;
	[undo removeAllActionsWithTarget:editor];
	if ([editor isKindOfClass:[NSTextView class]])
		[undo removeAllActionsWithTarget:[(NSTextView *)editor textStorage]];
}

- (void)textDidEndEditing:(NSNotification *)note
{
	NSInteger movement = [[note userInfo][NSTextMovementUserInfoKey] integerValue];
	NSMutableDictionary *info = [[note userInfo] mutableCopy] ?: [NSMutableDictionary dictionary];
	// The table keeps the value; where the cell chosen goes next is decided here.
	info[NSTextMovementUserInfoKey] = @(NSTextMovementOther);
	[super textDidEndEditing:[NSNotification notificationWithName:[note name] object:[note object] userInfo:info]];
	[self forgetTypingIn:[note object]];
	_replacing = NO;
	if (!_endingEditing)
		[[self window] makeFirstResponder:self];
	BOOL shift = ([[NSApp currentEvent] modifierFlags] & NSEventModifierFlagShift) != 0;
	if (movement == NSTextMovementReturn)
		[self moveForReturnUp:shift];
	else if (movement == NSTextMovementTab)
		[self moveForTabBack:NO];
	else if (movement == NSTextMovementBacktab)
		[self moveForTabBack:YES];
	[self setNeedsDisplay:YES];
}

- (BOOL)textView:(NSTextView *)textView doCommandBySelector:(SEL)selector
{
	NSEvent *event = [NSApp currentEvent];
	if (selector == @selector(cancelOperation:)) {
		// Escape puts back the value the cell had.
		NSText *editor = [self currentEditor];
		[self abortEditing];
		[self forgetTypingIn:editor];
		_replacing = NO;
		[[self window] makeFirstResponder:self];
		[self setNeedsDisplay:YES];
		return YES;
	}
	if ((selector == @selector(insertNewline:) || selector == @selector(noop:)) && [event type] == NSEventTypeKeyDown
		&& ([event modifierFlags] & NSEventModifierFlagCommand) && [[event charactersIgnoringModifiers] isEqualToString:@"\r"]) {
		[self endCellEditing];
		[[self controller] insertMatrix:self];
		return YES;
	}
	if (_replacing) {
		NSInteger rows = 0, columns = 0;
		if (selector == @selector(moveUp:)) rows = -1;
		else if (selector == @selector(moveDown:)) rows = 1;
		else if (selector == @selector(moveLeft:)) columns = -1;
		else if (selector == @selector(moveRight:)) columns = 1;
		if (rows != 0 || columns != 0) {
			[self endCellEditing];
			_tabStartColumn = -1;
			[self moveByRows:rows columns:columns extending:NO toEdge:NO];
			return YES;
		}
	}
	if ([NSTableView instancesRespondToSelector:@selector(textView:doCommandBySelector:)])
		return [super textView:textView doCommandBySelector:selector];
	return NO;
}

#pragma mark Keys

- (void)moveByRows:(NSInteger)rows columns:(NSInteger)columns extending:(BOOL)extend toEdge:(BOOL)edge
{
	NSInteger row = extend ? _extentRow : _activeRow, column = extend ? _extentColumn : _activeColumn;
	if (edge) {
		// To the last row or column inserted, then to the last of the table; or to the first.
		MatrixData *matrix = [[self controller] theMatrix];
		NSInteger lastRow = [matrix actRows] - 1, lastColumn = [matrix actCols] - 1;
		if (rows > 0) row = row < lastRow ? lastRow : [[self controller] gridRows] - 1;
		if (rows < 0) row = 0;
		if (columns > 0) column = column < lastColumn ? lastColumn : [[self controller] gridColumns] - 1;
		if (columns < 0) column = 0;
	} else {
		row += rows;
		column += columns;
	}
	[self selectRow:MAX(row, 0) column:MAX(column, 0) extending:extend];
}

// Return goes down, to the column where a row of Tabs started.
- (void)moveForReturnUp:(BOOL)up
{
	NSInteger column = _tabStartColumn >= 0 ? _tabStartColumn : _activeColumn;
	_tabStartColumn = -1;
	[self selectRow:MAX(_activeRow + (up ? -1 : 1), 0) column:column extending:NO];
}

- (void)moveForTabBack:(BOOL)back
{
	if (_tabStartColumn < 0)
		_tabStartColumn = _activeColumn;
	[self selectRow:_activeRow column:MAX(_activeColumn + (back ? -1 : 1), 0) extending:NO];
}

static BOOL TSMatrixTypesText(NSEvent *event)
{
	NSString *characters = [event characters];
	if ([characters length] == 0)
		return YES;	// a dead key, which starts a character
	unichar c = [characters characterAtIndex:0];
	return c >= 0x20 && c != 0x7F && !(c >= 0xF700 && c <= 0xF8FF);
}

- (void)keyDown:(NSEvent *)event
{
	NSString *characters = [event charactersIgnoringModifiers];
	NSEventModifierFlags flags = [event modifierFlags];
	BOOL shift = (flags & NSEventModifierFlagShift) != 0, command = (flags & NSEventModifierFlagCommand) != 0;
	BOOL control = (flags & NSEventModifierFlagControl) != 0;
	unichar key = [characters length] ? [characters characterAtIndex:0] : 0;
	NSInteger page = MAX(1, (NSInteger)floor(NSHeight([self visibleRect]) / ([self rowHeight] + [self intercellSpacing].height)) - 1);
	switch (key) {
		case NSUpArrowFunctionKey:
		case NSDownArrowFunctionKey:
		case NSLeftArrowFunctionKey:
		case NSRightArrowFunctionKey:
			_tabStartColumn = -1;
			[self moveByRows:key == NSUpArrowFunctionKey ? -1 : key == NSDownArrowFunctionKey ? 1 : 0
					 columns:key == NSLeftArrowFunctionKey ? -1 : key == NSRightArrowFunctionKey ? 1 : 0
				   extending:shift toEdge:command];
			return;
		case NSPageUpFunctionKey:
		case NSPageDownFunctionKey:
			_tabStartColumn = -1;
			[self moveByRows:key == NSPageUpFunctionKey ? -page : page columns:0 extending:shift toEdge:NO];
			return;
		case NSHomeFunctionKey:
		case NSEndFunctionKey: {
			_tabStartColumn = -1;
			MatrixData *matrix = [[self controller] theMatrix];
			NSInteger row = command ? (key == NSHomeFunctionKey ? 0 : [matrix actRows] - 1) : (shift ? _extentRow : _activeRow);
			[self selectRow:row column:key == NSHomeFunctionKey ? 0 : [matrix actCols] - 1 extending:shift];
			return;
		}
		case '\t':
		case NSBackTabCharacter:
			[self moveForTabBack:shift || key == NSBackTabCharacter];
			return;
		case '\r':
		case NSEnterCharacter:
			if (command)
				[[self controller] insertMatrix:self];
			else
				[self moveForReturnUp:shift];
			return;
		case NSDeleteCharacter:
		case NSDeleteFunctionKey:
			[self delete:self];
			return;
		case NSF2FunctionKey:
			[self editCellReplacing:NO event:nil];
			return;
		case 0x1B:
			[self selectRow:_activeRow column:_activeColumn extending:NO];
			return;
		default:
			break;
	}
	if (control && (key == 'u' || key == 'U') && !command) {
		[self editCellReplacing:NO event:nil];
		return;
	}
	if (!command && !control && TSMatrixTypesText(event)) {
		// Typing replaces what the cell holds; the key goes on to the editor, where input methods see it.
		[self editCellReplacing:YES event:nil];
		[[self currentEditor] keyDown:event];
		return;
	}
	[super keyDown:event];
}

#pragma mark Copy and paste

- (NSPasteboard *)usedPasteboard
{
	return self.pasteboard ?: [NSPasteboard generalPasteboard];
}

- (NSArray<NSArray<NSString *> *> *)selectedValues
{
	NSRange rows = [self selectedRows], columns = [self selectedColumns];
	NSMutableArray<NSArray<NSString *> *> *values = [NSMutableArray array];
	for (NSUInteger r = rows.location; r < NSMaxRange(rows) && (NSInteger)r < [[self controller] gridRows]; r++) {
		NSMutableArray<NSString *> *row = [NSMutableArray array];
		for (NSUInteger c = columns.location; c < NSMaxRange(columns) && (NSInteger)c < [[self controller] gridColumns]; c++)
			[row addObject:[[self controller] valueAtRow:r shownColumn:c] ?: @""];
		[values addObject:row];
	}
	return values;
}

- (void)copy:(id)sender
{
	NSString *text = TSMatrixTabularString([self selectedValues]);
	NSPasteboard *pasteboard = [self usedPasteboard];
	[pasteboard clearContents];
	[pasteboard setString:text forType:NSPasteboardTypeString];
	[pasteboard setString:text forType:NSPasteboardTypeTabularText];
}

- (void)cut:(id)sender
{
	[self copy:sender];
	[self delete:sender];
}

- (void)delete:(id)sender
{
	[self endCellEditing];
	[[self controller] clearRows:[self selectedRows] shownColumns:[self selectedColumns]];
}

- (void)paste:(id)sender
{
	NSPasteboard *pasteboard = [self usedPasteboard];
	NSString *text = [pasteboard stringForType:NSPasteboardTypeTabularText] ?: [pasteboard stringForType:NSPasteboardTypeString];
	NSArray<NSArray<NSString *> *> *values = TSMatrixParseTabular(text ?: @"");
	if ([values count] == 0)
		return;
	[self endCellEditing];
	NSRange rows = [self selectedRows], columns = [self selectedColumns];
	// One value fills the range chosen; more are put in place from its first cell.
	if ([values count] == 1 && [values[0] count] == 1 && (rows.length > 1 || columns.length > 1)) {
		NSMutableArray<NSArray<NSString *> *> *filled = [NSMutableArray array];
		for (NSUInteger r = 0; r < rows.length; r++) {
			NSMutableArray<NSString *> *row = [NSMutableArray array];
			for (NSUInteger c = 0; c < columns.length; c++)
				[row addObject:values[0][0]];
			[filled addObject:row];
		}
		values = filled;
	}
	NSUInteger width = 0;
	for (NSArray<NSString *> *row in values)
		width = MAX(width, [row count]);
	[[self controller] setValues:values atRow:rows.location shownColumn:columns.location];
	NSInteger lastRow = MIN((NSInteger)(rows.location + [values count]), [[self controller] gridRows]) - 1;
	NSInteger lastColumn = MIN((NSInteger)(columns.location + width), [[self controller] gridColumns]) - 1;
	[self selectRows:NSMakeRange(rows.location, lastRow - rows.location + 1) columns:NSMakeRange(columns.location, lastColumn - columns.location + 1)];
}

- (BOOL)validateUserInterfaceItem:(id<NSValidatedUserInterfaceItem>)item
{
	SEL action = [item action];
	if (action == @selector(copy:) || action == @selector(cut:) || action == @selector(delete:) || action == @selector(selectAll:))
		return [[self controller] gridRows] > 0;
	if (action == @selector(paste:))
		return [[self usedPasteboard] canReadObjectForClasses:@[[NSString class]] options:nil];
	return [super validateUserInterfaceItem:item];
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
