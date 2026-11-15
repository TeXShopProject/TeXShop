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
 * $Id: TSMacroOutlineController.h 108 2006-02-10 13:50:25Z fingolfin $
 *
 * Created by Mitsuhiro Shishikura on Wed Dec 18 2002.
 * This code was derived from Apple Sample code DrangNDropOutlineView
 *
 */

#import <Cocoa/Cocoa.h>

// In order to use this controller, create an instance of TSMacroOutlineView
// which is a subclass of NSOutlineView.
// Instantiate this class in Interface Builder and make connections
// with the outline view as "delegate" and "dataSource".
// Use "setRootOfTree" to assign the root node of the tree.
// Use "nodeFromDictionary" of "TSMacroTreeNode" to create such a node
// from a dictionary.

#define SEPARATOR_IMAGE @"Separator"
#define TSMacroOutlineViewAddedItemNotification		@"TSMacroOutlineViewAddedItem"
#define TSMacroOutlineViewRemovedItemNotification	@"TSMacroOutlineViewDeletedItem"
#define TSMacroOutlineViewAcceptedDropNotification	@"TSMacroOutlineViewAcceptedDrop"

@class TSMacroTreeNode;

@interface TSMacroOutlineController : NSObject 
{
//	TSMacroTreeNode	*rootOfTree;
//	NSArray	 		*draggedNodes;

	IBOutlet id outlineView;
}

@property (retain) TSMacroTreeNode	*rootOfTree;
@property (retain) TSMacroTreeNode  *specialRootOfTree;
@property (retain) NSArray	 		*draggedNodes;

+ (TSMacroOutlineController *)sharedInstance;

// - (void)setRootOfTree: (TSMacroTreeNode *)newRootOfTree;
// - (TSMacroTreeNode *)rootOfTree;
// - (NSArray*)draggedNodes;
- (NSArray *)selectedNodes;

- (void)deleteSelection: (id)sender;
- (void)addNewItem: (id)sender;
- (void)addSubmenu: (id)sender;
- (void)addSeparator: (id)sender;
- (void)addNewDataToSelection:(TSMacroTreeNode *)newChild;
- (void)addNewDataArrayToSelection:(NSArray *)newChildren;
- (void)duplicateSelection: (id)sender;
- (void)sortData: (id)sender;

@end


@interface NSOutlineView (MyExtensions)

- (NSArray*)allSelectedItems;
- (void)selectItems:(NSArray*)items byExtendingSelection:(BOOL)extend;

@end


@interface TSMacroOutlineView : NSOutlineView
{
}
// The row a second click on its name renames, after the double-click interval (nil: none).
@property (nonatomic, strong) NSNumber *pendingRename;
- (void)scheduleRenameOfRow:(NSInteger)row;
- (void)cancelPendingRename;
// The row that was selected alone when the mouse went down (-1: none, or several): a click on its
// shortcut records a new one (TSMacroEditor's listClicked:).
@property (nonatomic) NSInteger rowSelectedAtMouseDown;
// While a shortcut is recorded (TSMacroEditor): its item, and the field shown over the item's shortcut,
// at least recordingWidth wide.
@property (nonatomic, strong) id recordingItem;
@property (nonatomic, strong) NSView *recordingView;
@property (nonatomic) CGFloat recordingWidth;
- (void)placeRecordingView;
@end

// The shortcut of an item in the list; an inactive one has the yellow warning triangle before it.
@interface TSMacroShortcutCell : NSTextFieldCell
@property (nonatomic) BOOL showsWarning;
@end
// The list's shortcuts in a TSMacroShortcutCell, as the nib's cell has them.
void TSMacroUseShortcutCell(NSOutlineView *view);


@interface ImageAndTextCell : NSTextFieldCell
{
// @private
//	NSImage	*image;
}

@property (retain) NSImage *image1;

// - (void)setImage:(NSImage *)anImage;
// - (NSImage *)image;

- (void)drawWithFrame:(NSRect)cellFrame inView:(NSView *)controlView;
- (NSSize)cellSize;

@end

