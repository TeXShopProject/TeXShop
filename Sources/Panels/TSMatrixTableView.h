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
 * $Id: TSMatrixTableView.h 108 2006-02-10 13:50:25Z fingolfin $
 *
 */

#import <Cocoa/Cocoa.h>

// The identifier of the column that numbers the rows.
extern NSString *const TSMatrixRowNumberColumn;

// The table of the Matrix Panel works like a spreadsheet: a cell is chosen by a click or the arrow keys and
// a range by dragging or with Shift; typing replaces the cell, a double click, F2 or Control-U edits it;
// Return, Tab and the arrow keys move on; Delete empties the cells chosen; Copy, Cut and Paste use tab
// separated text as spreadsheets do. Rows are moved by dragging their numbers.
@interface TSMatrixTableView : NSTableView
{
	IBOutlet id myController;
}
- (void) drawStripesInRect:(NSRect)clipRect;
// The columns of the matrix, in the order they are shown, without the row numbers.
- (NSArray<NSTableColumn *> *)matrixColumns;

// The cell chosen and the other corner of the range chosen, in rows and in columns as shown.
@property (readonly) NSInteger activeRow, activeColumn, extentRow, extentColumn;
- (NSRange)selectedRows;
- (NSRange)selectedColumns;
- (void)selectRow:(NSInteger)row column:(NSInteger)column extending:(BOOL)extend;
- (void)selectRows:(NSRange)rows columns:(NSRange)columns;
// Whole rows, as after a drag of their numbers; whole columns, as after a click on their header.
- (void)selectWholeRows:(NSRange)rows;
- (void)selectWholeColumn:(NSInteger)column extending:(BOOL)extend;
// Starts editing the cell chosen: emptied for the characters typed when replace is YES, with its value otherwise.
- (void)editActiveCellReplacing:(BOOL)replace;
@property BOOL rowDragStarted;
// The pasteboard of Copy, Cut and Paste: the general one unless another is given.
@property (strong) NSPasteboard *pasteboard;

@end

// TODO: Try to get rid of this class
@interface InactiveTextFieldCell : NSTextFieldCell
-(id)init;
@end

// TODO: Try to get rid of this class
@interface ActiveTextFieldCell : NSTextFieldCell
-(id)init;
@end

@interface MatrixTableColumn : NSTableColumn
{
	NSCell *_inactiveDataCell;
}
-(id)init;
-(id)initWithIdentifier:(id)identifier;
@end

