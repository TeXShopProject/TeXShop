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
 * $Id: TSMacroOutlineController.m 159 2006-05-24 23:45:37Z fingolfin $
 *
 * Created by Mitsuhiro Shishikura on Wed Dec 18 2002.
 * This code was derived from Apple Sample code DrangNDropOutlineView
 *
 */

#import "TSMacroOutlineController.h"

#import "TSMacroMenuController.h"
#import "TSMacroEditor.h"
#import "TSMacroTreeNode.h"
#import "TSEncodingSupport.h"
#import "TSPrefPaneLayout.h"
#import "globals.h"

// ================================================================
// Constants
// ================================================================

#define DragDropSimplePboardType 	@"MyCustomOutlineViewPboardType"

#define COLUMNID_NAME	@"Name"
#define COLUMNID_KEY	@"Key"

#define NEW_ITEM_NAME	@"New Item"
#define NEW_SUBMENU_NAME	@"Submenu"

#define allowOnDropOnGroup 		YES
#define allowOnDropOnLeaf		NO
#define allowBetweenDrop		YES
#define onlyAcceptDropOnRoot	NO
#define autoSort 				NO


// ================================================================
// Method implimentations
// ================================================================

@implementation TSMacroOutlineController

static TSMacroOutlineController *_sharedOutlineViewController = nil;

+ (TSMacroOutlineController *)sharedInstance
{
	if (_sharedOutlineViewController == nil)
		_sharedOutlineViewController = [[TSMacroOutlineController alloc] init];
	return _sharedOutlineViewController;
}

- (id)init
{
	if (!_sharedOutlineViewController)
    {
        _sharedOutlineViewController = [super init];
		self.rootOfTree = nil; //[[TSMacroTreeNode alloc] init];
		self.draggedNodes = nil;
	}
	return _sharedOutlineViewController;
}

/*
- (void)dealloc
{
	if (self.rootOfTree)
		[self.rootOfTree release];
	if (self.draggedNodes)
		[self.draggedNodes release];
	[super dealloc];
	_sharedOutlineViewController = nil;
}
*/

- (void)awakeFromNib
{
	NSTableColumn *tableColumn = nil;
	ImageAndTextCell *imageAndTextCell = nil;

	// Insert custom cell types into the table view, the standard one does text only.
	// We want one column to have text and images, and one to have check boxes.
	tableColumn = [outlineView tableColumnWithIdentifier: COLUMNID_NAME];
	imageAndTextCell = [[ImageAndTextCell alloc] init];
	[imageAndTextCell setEditable: YES];
	[tableColumn setDataCell:imageAndTextCell];
	TSMacroUseShortcutCell(outlineView);

	// Register to get only our custom type.
	[outlineView registerForDraggedTypes:[NSArray arrayWithObjects: DragDropSimplePboardType, NSStringPboardType, nil]];
}


// ================================================================
//  Managing the tree root
// ================================================================

- (void)setRootOfTree: (TSMacroTreeNode *)newRootOfTree
{
	self.specialRootOfTree = newRootOfTree;
//    [newRootOfTree retain];
//	[rootOfTree release];
//	rootOfTree = newRootOfTree;
	self.draggedNodes = nil;
	[outlineView reloadData];
}

- (TSMacroTreeNode *)rootOfTree
{
	return self.specialRootOfTree;
}

// ================================================================
//  NSOutlineView related methods.
// ================================================================

/*
- (NSArray*)draggedNodes
{
	return draggedNodes;
}
*/

- (NSArray *)selectedNodes
{
	return [outlineView allSelectedItems];
}

- (void)addNewItem: (id)sender
{
	[self addNewDataToSelection: [TSMacroTreeNode nodeWithName: NEW_ITEM_NAME content: nil key: nil]];
}

- (void)addSubmenu: (id)sender
{
	[self addNewDataToSelection: [TSMacroTreeNode submenuNodeWithName: NEW_SUBMENU_NAME]];
}

- (void)addSeparator: (id)sender
{
	[self addNewDataToSelection: [TSMacroTreeNode separatorNode]];
}

- (void)addNewDataToSelection:(TSMacroTreeNode *)newChild
{
	NSIndexSet		*myIndexSet;
	NSInteger childIndex = 0, newRow = 0;
	NSArray *selectedNodes = [self selectedNodes];
	TSMacroTreeNode *selectedNode = ([selectedNodes count] ? [selectedNodes lastObject] : self.rootOfTree);
	TSMacroTreeNode *parentNode = nil;
	
	if ([selectedNode isGroup]) {
		parentNode = selectedNode;
		childIndex = [parentNode numberOfChildren]; // it was 0;
		[outlineView expandItem: selectedNode];
	} else {
		parentNode = [selectedNode nodeParent];
		childIndex = [parentNode indexOfChildIdenticalTo:selectedNode] + 1;
	}
	
	[parentNode insertChild: newChild atIndex: childIndex];
	[outlineView reloadData];
	
	newRow = [outlineView rowForItem: newChild];
	if (newRow >= 0) {
		myIndexSet = [NSIndexSet indexSetWithIndex: newRow];
		// [outlineView selectRow: newRow byExtendingSelection: NO]; // deprecated, so
		[outlineView selectRowIndexes: myIndexSet byExtendingSelection: NO];
		}
	
#ifdef TSMacroOutlineViewAddedItemNotification
	// notify that item was added -- custom notification
	[[NSNotificationCenter defaultCenter] postNotificationName: TSMacroOutlineViewAddedItemNotification
														object: outlineView];
#endif
}

- (void)addNewDataArrayToSelection:(NSArray *)newChildren
{
	NSInteger childIndex = 0; //, newRow = 0;
	NSArray *selectedNodes = [self selectedNodes];
	TSMacroTreeNode *selectedNode;
	TSMacroTreeNode *parentNode = nil;

	if ([selectedNodes count] == 0) {
		parentNode = self.rootOfTree;
		childIndex = [self.rootOfTree numberOfChildren];
	} else {
		selectedNode = [selectedNodes lastObject];
		parentNode = [selectedNode nodeParent];
		childIndex = [parentNode indexOfChildIdenticalTo:selectedNode] + 1;
	}

	[parentNode insertChildren: newChildren atIndex: childIndex];
	[outlineView reloadData];

	[outlineView selectItems: newChildren byExtendingSelection: NO];

#ifdef TSMacroOutlineViewAddedItemNotification
	// notify that item was added -- custom notification
	[[NSNotificationCenter defaultCenter] postNotificationName: TSMacroOutlineViewAddedItemNotification
					object: outlineView];
#endif
}

- (void)deleteSelection: (id)sender
{
	NSArray *selection = [self selectedNodes];
	if ([selection count] == 0)
		return;

	// Tell all of the selected nodes to remove themselves from the model.
	[selection makeObjectsPerformSelector: @selector(removeFromParent)];
	[outlineView deselectAll:nil];
	[outlineView reloadData];

#ifdef TSMacroOutlineViewRemovedItemNotification
	// notify that item was deleted -- custom notification
	[[NSNotificationCenter defaultCenter] postNotificationName: TSMacroOutlineViewRemovedItemNotification
					object: outlineView];
#endif
}

- (void)duplicateSelection: (id)sender
{
	NSArray *selection = [self selectedNodes];
	if ([selection count] == 0)
		return;
	[self addNewDataArrayToSelection: [TSMacroTreeNode duplicateNodeArray: selection]];
}

- (void)selectAll: (id)sender
{
	[outlineView selectAll: sender];
}

- (void)sortData: (id)sender
{
	NSArray *itemsToSelect = [self selectedNodes];
	[self.rootOfTree recursiveSortChildren];
	[outlineView reloadData];
	[outlineView selectItems: itemsToSelect byExtendingSelection: NO];
}


// ================================================================
//  NSOutlineView data source methods. (The required ones)
// ================================================================
//  Need Interface Builder connection:
//		NSOutlineView.dataSource -> Instance of this class (or file's owner)

// Required methods.
- (id)outlineView:(NSOutlineView *)olv child:(NSInteger)idx ofItem:(id)item
{
	return [(item)?((TSMacroTreeNode*)item):self.rootOfTree childAtIndex:idx];
}

- (BOOL)outlineView:(NSOutlineView *)olv isItemExpandable:(id)item
{
	return [(TSMacroTreeNode*)item isExpandable];
}

- (NSInteger)outlineView:(NSOutlineView *)olv numberOfChildrenOfItem:(id)item
{
	return [(item)?((TSMacroTreeNode*)item):self.rootOfTree numberOfChildren];
}

- (id)outlineView:(NSOutlineView *)olv objectValueForTableColumn:(NSTableColumn *)tableColumn byItem:(id)item
{
	id objectValue = nil;
	// The return value from this method is used to configure the state of the items cell via setObjectValue:

#ifdef DEBUG_TREE
	NODE_INFO(@"ObjValue", item);
#endif

	if([[tableColumn identifier] isEqualToString: COLUMNID_NAME]) {
        if ([(TSMacroTreeNode*)item isSeparator]) {
			objectValue = @"";
        }
		else {
			objectValue = [(TSMacroTreeNode*)item name];
 		}
	} else if([[tableColumn identifier] isEqualToString: COLUMNID_KEY]) {
		// While its shortcut is recorded, the field over the cell shows it (TSMacroEditor).
		objectValue = item == [[TSMacroEditor sharedInstance] recordingItem] ? @"" : getMenuItemString([(TSMacroTreeNode*)item key]);
	}
	return objectValue;
}

// Optional method: needed to allow editing.
// The name typed when an item is renamed in the list. An empty name keeps the old one, as in Finder.
- (void)outlineView:(NSOutlineView *)olv setObjectValue:(id)object forTableColumn:(NSTableColumn *)tableColumn byItem:(id)item
{
	if (![[tableColumn identifier] isEqualToString: COLUMNID_NAME] || [(TSMacroTreeNode*)item isSeparator]) return;
	NSString *name = [object isKindOfClass:NSString.class] ? object : [object description];
	if ([name stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet].length == 0) return;
	if ([name isEqualToString:[(TSMacroTreeNode*)item name]]) return;
	[(TSMacroTreeNode*)item setName: name];
    [[TSMacroEditor sharedInstance] outlineViewItemsChanged:nil];
}

// ================================================================
//  NSOutlineView delegate methods.
// ================================================================
//  Need Interface Builder connection:
//		NSOutlineView.delegate -> Instance of this class (or file's owner)

- (BOOL)outlineView:(NSOutlineView *)olv shouldExpandItem:(id)item
{
	return [(TSMacroTreeNode*)item isExpandable];
}

// Only the editor's renaming edits a name (TSMacroEditor's beginRenamingSelectedItem): a double click runs the macro.
- (BOOL)outlineView:(NSOutlineView *)olv shouldEditTableColumn: (NSTableColumn *)tableColumn item: (id)item
{
	return [[TSMacroEditor sharedInstance] isRenaming] && [[tableColumn identifier] isEqualToString: COLUMNID_NAME] && ![(TSMacroTreeNode*)item isSeparator];
}

// A name typed in the list is filtered as the name field was (the yen sign and the backslash).
- (void)controlTextDidChange:(NSNotification *)note
{
	[[TSEncodingSupport sharedInstance] controlTextDidChange:note];
}

- (void)outlineView: (NSOutlineView *)olv willDisplayCell: (NSCell *)cell forTableColumn: (NSTableColumn *)tableColumn item: (id)item
{
    // return;
    
	if ([[tableColumn identifier] isEqualToString: COLUMNID_NAME]) {
		// if (item && [(TSMacroTreeNode*)item iconRep]) // when there is an icon
		//	[(ImageAndTextCell*)cell setImage: [(TSMacroTreeNode*)item iconRep]];
		// else
		if ([item isSeparator]) {
			[(ImageAndTextCell*)cell setImage1: TSMacroSeparatorImage(tableColumn.width - 8)];
		}
        else {
			 [(ImageAndTextCell*)cell setImage1: nil];
        }
	} else if ([[tableColumn identifier] isEqualToString: COLUMNID_KEY]) {
		NSString *conflict = [[TSMacroEditor sharedInstance] shortcutConflictForNode:item];
		[(NSTextFieldCell *)cell setTextColor:conflict ? NSColor.secondaryLabelColor : NSColor.controlTextColor];
		if ([cell isKindOfClass:TSMacroShortcutCell.class])
			((TSMacroShortcutCell *)cell).showsWarning = conflict != nil && item != [[TSMacroEditor sharedInstance] recordingItem];
		// The item whose shortcut VoiceOver's press records (TSMacroShortcutCell).
		cell.representedObject = item;
		// VoiceOver reads the shortcut and why it is inactive, not the triangle.
		cell.accessibilityValue = conflict ? getMenuItemString([(TSMacroTreeNode*)item key]) : nil;
		cell.accessibilityLabel = conflict;
	}
}

// Why a shortcut with the warning triangle is inactive, as the item in the Macros menu says.
- (NSString *)outlineView:(NSOutlineView *)olv toolTipForCell:(NSCell *)cell rect:(NSRectPointer)rect tableColumn:(NSTableColumn *)tableColumn item:(id)item mouseLocation:(NSPoint)mouseLocation
{
	if (![[tableColumn identifier] isEqualToString: COLUMNID_KEY]) return nil;
	return [[TSMacroEditor sharedInstance] shortcutConflictForNode:item];
}

// ================================================================
//  NSOutlineView data source methods. (dragging related)
// ================================================================
//  Need Interface Builder connection:
//		NSOutlineView.dataSource -> Instance of this class (or file's owner)

- (BOOL)outlineView:(NSOutlineView *)olv writeItems:(NSArray*)items toPasteboard:(NSPasteboard*)pboard
{
	self.draggedNodes = items; // Don't retain since this is just holding temporaral drag information, and it is only used during a drag!  We could put this in the pboard actually.

	// Provide data for our custom type, and simple NSStrings.
	[pboard declareTypes:[NSArray arrayWithObjects: DragDropSimplePboardType, NSStringPboardType, nil] owner:self];

	// the actual data doesn't matter since DragDropSimplePboardType drags aren't recognized by anyone but us!.
	[pboard setData:[NSData data] forType:DragDropSimplePboardType];

	// Put string data on the pboard... notice you candrag into TextEdit!
	NSString *draggedString = ([self.draggedNodes count]>0)?([[self.draggedNodes objectAtIndex: 0] content]):@"";
	if (!draggedString)
		draggedString = @"";	// content may be nil?
	if (g_shouldFilter == kMacJapaneseFilterMode) {
		if ([SUD boolForKey:@"ConvertToBackslash"]) // this case isn't necessary?
			draggedString = filterYenToBackslash(draggedString);
		else
			draggedString = filterBackslashToYen(draggedString);
	} else if (g_shouldFilter == kOtherJapaneseFilterMode) {
		if ([SUD boolForKey:@"ConvertToYen"])
			draggedString = filterBackslashToYen(draggedString);
		else	// this case shouldn't be necessary
			draggedString = filterYenToBackslash(draggedString);
	}
	[pboard setString: draggedString forType: NSStringPboardType];

	return YES;
}

- (NSUInteger)outlineView:(NSOutlineView*)olv validateDrop:(id <NSDraggingInfo>)info proposedItem:(id)item proposedChildIndex:(NSInteger)childIndex
{
	// This method validates whether or not the proposal is a valid one. Returns NO if the drop should not be allowed.
	TSMacroTreeNode *targetNode = item;
	BOOL targetNodeIsValid = YES;

	if (onlyAcceptDropOnRoot) {
		targetNode = nil;
		childIndex = NSOutlineViewDropOnItemIndex;
	} else {
		BOOL isOnDropTypeProposal = childIndex==NSOutlineViewDropOnItemIndex;

		// Refuse if: dropping "on" the view itself unless we have no data in the view.
		if ((targetNode==nil) && (childIndex==NSOutlineViewDropOnItemIndex) &&
								([self.rootOfTree numberOfChildren]!=0))
			targetNodeIsValid = NO;

		if ((targetNode==nil) && (childIndex==NSOutlineViewDropOnItemIndex) && ((allowOnDropOnLeaf)==NO))
			targetNodeIsValid = NO;

		// Refuse if: we are trying to do something which is not allowed.
		if ((targetNodeIsValid && isOnDropTypeProposal==NO && allowBetweenDrop==NO) ||
			([(TSMacroTreeNode*)targetNode isGroup] && isOnDropTypeProposal==YES && allowOnDropOnGroup==NO) ||
			([(TSMacroTreeNode*)targetNode isLeaf ] && isOnDropTypeProposal==YES && allowOnDropOnLeaf==NO))
			targetNodeIsValid = NO;

		// Check to make sure we don't allow a node to be inserted into one of its descendants!
		if (targetNodeIsValid && ([info draggingSource]==outlineView) && [[info draggingPasteboard] availableTypeFromArray:[NSArray arrayWithObject: DragDropSimplePboardType]] != nil) {
			NSArray *myDraggedNodes = [(TSMacroOutlineController *)[[info draggingSource] dataSource] draggedNodes];
			targetNodeIsValid = ![targetNode isDescendantOfNodeInArray: myDraggedNodes];
		}
	}

	// Set the item and child idx in case we computed a retargeted one.
	[outlineView setDropItem:targetNode dropChildIndex:childIndex];

	return targetNodeIsValid ? NSDragOperationGeneric : NSDragOperationNone;
}

- (void)performDropOperation:(id <NSDraggingInfo>)info onNode:(TSMacroTreeNode*)parentNode atIndex:(NSInteger)childIndex
{
	// Helper method to insert dropped data into the model.
	NSPasteboard * pboard = [info draggingPasteboard];
	NSMutableArray * itemsToSelect = nil;
	
	// Do the appropriate thing depending on whether the data is DragDropSimplePboardType or NSStringPboardType.
	if ([pboard availableTypeFromArray:[NSArray arrayWithObjects:DragDropSimplePboardType, nil]] != nil) {
		TSMacroOutlineController *dragDataSource = [[info draggingSource] dataSource];
		NSArray *myDraggedNodes = [TSMacroTreeNode minimumNodeCoverFromNodesInArray: [dragDataSource draggedNodes]];
		NSEnumerator *draggedNodesEnum = [myDraggedNodes objectEnumerator];
		TSMacroTreeNode *aDraggedNode = nil, *aDraggedNodeParent = nil;
		
		itemsToSelect = [NSMutableArray arrayWithArray:[self selectedNodes]];
		
		while ((aDraggedNode = [draggedNodesEnum nextObject])) {
			aDraggedNodeParent = (TSMacroTreeNode *)[aDraggedNode nodeParent];
			if (parentNode==aDraggedNodeParent && [parentNode indexOfChild: aDraggedNode]<childIndex)
				childIndex--;
			[aDraggedNodeParent removeChild: aDraggedNode];
		}
		[parentNode insertChildren: myDraggedNodes atIndex: childIndex];
	} else if ([pboard availableTypeFromArray:[NSArray arrayWithObject: NSStringPboardType]]) {
		NSString *string = [pboard stringForType: NSStringPboardType];
		NSString *tempStr = string;
		if (g_shouldFilter == kMacJapaneseFilterMode)
			tempStr = filterBackslashToYen(string);
		else if (g_shouldFilter == kOtherJapaneseFilterMode)
			tempStr = filterYenToBackslash(string);
		NSMutableString *nameStr = [[tempStr substringToIndex: MIN([tempStr length], 50)] mutableCopy];
		[nameStr replaceOccurrencesOfString: @"\n" withString: @""
									options: 0 range: NSMakeRange(0, [nameStr length])];
		if (g_shouldFilter)	// we only use backslashes
			string = filterYenToBackslash(string);
		TSMacroTreeNode *newItem = [TSMacroTreeNode nodeWithName: nameStr content: string key: nil];
	//	[nameStr release];
		
		itemsToSelect = [NSMutableArray arrayWithObject: newItem];
		[parentNode insertChild: newItem atIndex:childIndex++];
	}
	
	[outlineView reloadData];
	[outlineView selectItems: itemsToSelect byExtendingSelection: NO];
}

- (BOOL)outlineView:(NSOutlineView*)olv acceptDrop:(id <NSDraggingInfo>)info item:(id)targetItem childIndex:(NSInteger)childIndex
{
	TSMacroTreeNode * 		parentNode = nil;

	// Determine the parent to insert into and the child idx to insert at.
	if ([(TSMacroTreeNode*)targetItem isLeaf]) {
		parentNode = (childIndex == NSOutlineViewDropOnItemIndex ? [targetItem nodeParent] : targetItem);
		childIndex = (childIndex == NSOutlineViewDropOnItemIndex ? [[targetItem nodeParent] indexOfChild: targetItem] + 1 : 0);
	} else {
		parentNode = (targetItem ? targetItem : self.rootOfTree);
		childIndex = (childIndex == NSOutlineViewDropOnItemIndex ? 0 : childIndex);
	}

	[self performDropOperation:info onNode:parentNode atIndex:childIndex];

#ifdef TSMacroOutlineViewAcceptedDropNotification
	// notify that item was moved or dropped -- custom notification
	[[NSNotificationCenter defaultCenter] postNotificationName: TSMacroOutlineViewAcceptedDropNotification
					object: outlineView];
#endif
	return YES;
}

@end


@implementation NSOutlineView (MyExtensions)

- (id)selectedItem {
	return [self itemAtRow: [self selectedRow]];
}

- (NSArray*)allSelectedItems {
	NSIndexSet *theIndexes = [self selectedRowIndexes];
	NSMutableArray *items = [NSMutableArray array];
	/* selectedRowEnumerator is deprecated
	NSEnumerator *selectedRows = [self selectedRowEnumerator];
	NSNumber *selRow = nil;
	while ((selRow = [selectedRows nextObject])) {
		if ([self itemAtRow:[selRow intValue]])
			[items addObject: [self itemAtRow:[selRow intValue]]];
	}
	*/
	NSInteger rows = [self numberOfRows];
	NSInteger i;
	for (i = 0; i < rows; i++)
		if ([theIndexes containsIndex:i]) {
			if ([self itemAtRow: i])
				[items addObject: [self itemAtRow:i]];
			}
	
	return items;
}

- (void)selectItems:(NSArray*)items byExtendingSelection:(BOOL)shouldExtend {
	NSIndexSet		*myIndexSet;
	NSInteger i;
	if (shouldExtend == NO)
		[self deselectAll:nil];
	for (i = 0; i < [items count]; i++) {
		NSInteger row = [self rowForItem:[items objectAtIndex:i]];
		if(row >= 0) {
			myIndexSet = [NSIndexSet indexSetWithIndex: row];
			// [self selectRow: row byExtendingSelection:YES]; // deprecated, so
			[self selectRowIndexes: myIndexSet byExtendingSelection:YES];
			}
	}
}

- (void)delete: (id)sender
{
	[(TSMacroOutlineController *)[self delegate] deleteSelection: sender];
}


- (BOOL)validateMenuItem:(NSMenuItem *)anItem
{
	if ([anItem action] == @selector(delete:))
		return ([[self allSelectedItems] count] > 0);

	return YES;
}

@end


// While an item is renamed, its field is as wide as the name and grows with it, as in Finder,
// up to the name's column.
static const CGFloat TSNameEditingSlack = 10, TSNameEditingMinimum = 48;
static CGFloat TSNameEditingWidth(NSString *string, NSFont *font)
{
	return MAX(TSNameEditingMinimum, ceil([string ?: @"" sizeWithAttributes:@{NSFontAttributeName: font ?: [NSFont systemFontOfSize:NSFont.systemFontSize]}].width) + TSNameEditingSlack);
}

@implementation TSMacroOutlineView

// As in Finder, a click on the name of the item that is already selected, and not followed by
// a second click, renames it: the editor's renameSelectedMacro:, reached through the responder
// chain (the window's delegate). Anything done before then (a second click, a key, another
// selection, the list leaving its window) cancels it.
- (void)mouseDown:(NSEvent *)event
{
	[self cancelPendingRename];
	NSPoint point = [self convertPoint:event.locationInWindow fromView:nil];
	NSInteger row = [self rowAtPoint:point];
	NSEventModifierFlags modifiers = event.modifierFlags & (NSEventModifierFlagCommand | NSEventModifierFlagShift | NSEventModifierFlagOption | NSEventModifierFlagControl);
	BOOL again = event.clickCount == 1 && modifiers == 0 && row >= 0 && self.numberOfSelectedRows == 1 && [self isRowSelected:row]
		&& self.window.isKeyWindow && self.window.firstResponder == self && [self isNameAtPoint:point row:row];
	self.rowSelectedAtMouseDown = modifiers == 0 && self.numberOfSelectedRows == 1 ? self.selectedRow : -1;
	[super mouseDown:event];
	NSEvent *up = NSApp.currentEvent;
	NSPoint end = [self convertPoint:up.locationInWindow fromView:nil];
	if (again && up.type == NSEventTypeLeftMouseUp && hypot(end.x - point.x, end.y - point.y) < 4 && self.selectedRow == row && self.numberOfSelectedRows == 1)
		[self scheduleRenameOfRow:row];
}

- (void)scheduleRenameOfRow:(NSInteger)row
{
	[self cancelPendingRename];
	self.pendingRename = @(row);
	[self performSelector:@selector(renameAfterClick) withObject:nil afterDelay:NSEvent.doubleClickInterval];
}

- (void)cancelPendingRename
{
	[NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(renameAfterClick) object:nil];
	self.pendingRename = nil;
}

- (void)renameAfterClick
{
	NSNumber *row = self.pendingRename;
	self.pendingRename = nil;
	if (row == nil || !self.window.isKeyWindow || self.window.firstResponder != self || self.numberOfSelectedRows != 1 || self.selectedRow != row.integerValue) return;
	[NSApp sendAction:@selector(renameSelectedMacro:) to:nil from:self];
}

- (void)selectRowIndexes:(NSIndexSet *)indexes byExtendingSelection:(BOOL)extend
{
	[self cancelPendingRename];
	[super selectRowIndexes:indexes byExtendingSelection:extend];
}

// The field of the name being renamed follows what is typed.
- (void)textDidChange:(NSNotification *)note
{
	[super textDidChange:note];
	NSText *editor = self.currentEditor;
	NSView *clip = editor.superview;
	if (editor == nil || clip == nil || self.editedRow < 0 || self.editedColumn < 0) return;
	NSRect cell = [self frameOfCellAtColumn:self.editedColumn row:self.editedRow], frame = clip.frame, before = frame;
	frame.size.width = MIN(NSMaxX(cell) - NSMinX(frame), TSNameEditingWidth(editor.string, editor.font));
	if (NSWidth(frame) == NSWidth(before)) return;
	clip.frame = frame;
	[self setNeedsDisplayInRect:NSInsetRect(NSUnionRect(before, frame), -4, -4)];
}

- (void)keyDown:(NSEvent *)event
{
	[self cancelPendingRename];
	[super keyDown:event];
}

// The name itself, not the space after it or the shortcut.
- (BOOL)isNameAtPoint:(NSPoint)point row:(NSInteger)row
{
	NSInteger column = [self columnWithIdentifier:COLUMNID_NAME];
	if (column < 0 || [self columnAtPoint:point] != column || [[self itemAtRow:row] isSeparator]) return NO;
	NSRect frame = [self frameOfCellAtColumn:column row:row];
	NSFont *font = ((NSCell *)[self.tableColumns[column] dataCell]).font ?: [NSFont systemFontOfSize:NSFont.systemFontSize];
	CGFloat name = [[[self itemAtRow:row] name] ?: @"" sizeWithAttributes:@{NSFontAttributeName: font}].width;
	return point.x <= NSMinX(frame) + MIN(NSWidth(frame), name + 4) + 2; // the text is inset 2 points in its cell
}

- (void)viewWillMoveToWindow:(NSWindow *)newWindow
{
	[self cancelPendingRename];
	[super viewWillMoveToWindow:newWindow];
}

// The field of a shortcut being recorded, over the shortcut of its item: as wide as the shortcut's cell,
// or, where the field needs more, wider towards the name, as far as the name's column begins.
- (void)placeRecordingView
{
	NSView *view = self.recordingView;
	if (view == nil) return;
	if (view.superview != self) [self addSubview:view];
	NSInteger row = [self rowForItem:self.recordingItem], key = [self columnWithIdentifier:COLUMNID_KEY], name = [self columnWithIdentifier:COLUMNID_NAME];
	if (row < 0 || key < 0) { view.hidden = YES; return; }
	NSRect cell = [self frameOfCellAtColumn:key row:row], line = [self rectOfRow:row];
	CGFloat leading = name >= 0 ? NSMinX([self rectOfColumn:name]) : NSMinX(cell);
	CGFloat width = MAX(NSWidth(cell), MIN(self.recordingWidth, NSMaxX(cell) - leading));
	view.frame = NSMakeRect(NSMaxX(cell) - width, NSMinY(line), width, NSHeight(line));
	view.hidden = NO;
}

- (void)setRecordingView:(NSView *)view
{
	if (_recordingView != view) [_recordingView removeFromSuperview];
	_recordingView = view;
	[self placeRecordingView];
}

- (void)tile
{
	[super tile];
	[self placeRecordingView];
}

- (void)setFrameSize:(NSSize)size
{
	[super setFrameSize:size];
	[self placeRecordingView];
}

- (NSDragOperation)draggingSourceOperationMaskForLocal:(BOOL)isLocal {
	if (isLocal)
		return NSDragOperationEvery;
	else
		return NSDragOperationCopy;
}

@end


@implementation ImageAndTextCell

/*
- (void)dealloc {
	[image release];
	image = nil;
	[super dealloc];
}
*/

- copyWithZone:(NSZone *)zone {
	ImageAndTextCell *cell = (ImageAndTextCell *)[super copyWithZone:zone];
//	cell->image = [image retain];
    cell.image1 = self.image1;
	return cell;
}

/*
- (void)setImage:(NSImage *)anImage {
	if (anImage != image) {
		[image release];
		image = [anImage retain];
	}
}

- (NSImage *)image {
	return image;
}
*/

- (NSRect)imageFrameForCellFrame:(NSRect)cellFrame {
	if (self.image1 != nil) {
		NSRect imageFrame;
		imageFrame.size = [self.image1 size];
		imageFrame.origin = cellFrame.origin;
		imageFrame.origin.x += 3;
		imageFrame.origin.y += ceil((cellFrame.size.height - imageFrame.size.height) / 2);
		return imageFrame;
	}
	else
		return NSZeroRect;
}

- (void)editWithFrame:(NSRect)aRect inView:(NSView *)controlView editor:(NSText *)textObj delegate:(id)anObject event:(NSEvent *)theEvent {
	NSRect textFrame, imageFrame;
	NSDivideRect (aRect, &imageFrame, &textFrame, 3 + [self.image1 size].width, NSMinXEdge);
	textFrame.size.width = MIN(NSWidth(textFrame), TSNameEditingWidth(self.stringValue, self.font));
	[super editWithFrame: textFrame inView: controlView editor:textObj delegate:anObject event: theEvent];
}

- (void)selectWithFrame:(NSRect)aRect inView:(NSView *)controlView editor:(NSText *)textObj delegate:(id)anObject start:(NSInteger)selStart length:(NSInteger)selLength {
	NSRect textFrame, imageFrame;
	NSDivideRect (aRect, &imageFrame, &textFrame, 3 + [self.image1 size].width, NSMinXEdge);
	textFrame.size.width = MIN(NSWidth(textFrame), TSNameEditingWidth(self.stringValue, self.font));
	[super selectWithFrame: textFrame inView: controlView editor:textObj delegate:anObject start:selStart length:selLength];
}

- (void)drawWithFrame:(NSRect)cellFrame inView:(NSView *)controlView {
   if (self.image1 != nil) {
		NSSize	imageSize;
		NSRect	imageFrame;

		imageSize = [self.image1 size];
		NSDivideRect(cellFrame, &imageFrame, &cellFrame, 3 + imageSize.width, NSMinXEdge);
		if ([self drawsBackground]) {
			[[self backgroundColor] set];
			NSRectFill(imageFrame);
		}
		imageFrame.origin.x += 3;
// changed by mitsu 2002.12.02 from Apple Sample code
		imageFrame.size.height = imageSize.height;
		if (imageFrame.size.width > imageSize.width)
			imageFrame.size.width = imageSize.width;

		if ( ! [controlView isFlipped])	// I don't know why ! was necessary
			imageFrame.origin.y += ceil((cellFrame.size.height + imageFrame.size.height) / 2);
		else
			imageFrame.origin.y += ceil((cellFrame.size.height - imageFrame.size.height) / 2);

		NSRect imageSrcRect;
		imageSrcRect.size = imageSize;
		imageSrcRect.origin = NSMakePoint(0,0);
		[self.image1 drawInRect: imageFrame fromRect: imageSrcRect
						operation: NSCompositeSourceOver fraction: 1.0];
// original was:
		//imageFrame.size = imageSize;

		//if ([controlView isFlipped])
		//    imageFrame.origin.y += ceil((cellFrame.size.height + imageFrame.size.height) / 2);
		//else
		//    imageFrame.origin.y += ceil((cellFrame.size.height - imageFrame.size.height) / 2);

		//[image compositeToPoint:imageFrame.origin operation:NSCompositeSourceOver];
// change end
	}
	[super drawWithFrame:cellFrame inView:controlView];
}

- (NSSize)cellSize {
	NSSize cellSize = [super cellSize];
	//cellSize.width += (image ? [image size].width : 0) + 3;
	return cellSize;
}

@end


// The shortcut at the trailing edge of its cell, as in a menu; an inactive one with the yellow warning
// triangle of the shortcut warnings (TSShortcutRecordingCell, the message below the contents) before it,
// 4 points from it, on the middle of its capitals.
static const CGFloat TSMacroShortcutWarningSpacing = 4;
@implementation TSMacroShortcutCell

- (id)copyWithZone:(NSZone *)zone {
	TSMacroShortcutCell *cell = [super copyWithZone:zone];
	cell.showsWarning = self.showsWarning;
	return cell;
}

- (void)drawInteriorWithFrame:(NSRect)frame inView:(NSView *)controlView {
	if (!self.showsWarning) { [super drawInteriorWithFrame:frame inView:controlView]; return; }
	NSImage *mark = [TSPrefPaneLayout warningSymbolImageForFont:[NSFont systemFontOfSize:NSFont.smallSystemFontSize]];
	NSSize size = mark.size;
	NSRect title = [self titleRectForBounds:frame], text = frame;
	NSFont *font = self.font ?: [NSFont systemFontOfSize:NSFont.systemFontSize];
	// The shortcut where it always is; when the cell is too narrow for both, the triangle at the leading edge
	// and the shortcut, shortened, after it.
	CGFloat width = ceil(self.attributedStringValue.size.width), room = NSWidth(title) - size.width - TSMacroShortcutWarningSpacing;
	CGFloat x = NSMaxX(title) - MIN(width, room) - TSMacroShortcutWarningSpacing - size.width;
	if (width > room) { text.origin.x += size.width + TSMacroShortcutWarningSpacing; text.size.width -= size.width + TSMacroShortcutWarningSpacing; }
	CGFloat middle = controlView.isFlipped ? NSMinY(title) + font.ascender - font.capHeight / 2 : NSMaxY(title) - font.ascender + font.capHeight / 2;
	// Over what the cell draws, which may fill its frame.
	[super drawInteriorWithFrame:text inView:controlView];
	[mark drawInRect:NSMakeRect(x, round(middle - size.height / 2), size.width, size.height) fromRect:NSZeroRect
		operation:NSCompositingOperationSourceOver fraction:1 respectFlipped:YES hints:nil];
}

// VoiceOver's press records a new shortcut for the item of the row (outlineView:willDisplayCell:...).
- (BOOL)isAccessibilitySelectorAllowed:(SEL)selector {
	if (selector == @selector(accessibilityPerformPress)) return [self.representedObject isKindOfClass:TSMacroTreeNode.class] && [self.representedObject isStandardItem];
	return [super isAccessibilitySelectorAllowed:selector];
}

- (BOOL)accessibilityPerformPress {
	TSMacroTreeNode *item = self.representedObject;
	return [item isKindOfClass:TSMacroTreeNode.class] && [[TSMacroEditor sharedInstance] beginRecordingShortcutForItem:item];
}

@end

void TSMacroUseShortcutCell(NSOutlineView *view)
{
	NSTableColumn *column = [view tableColumnWithIdentifier:COLUMNID_KEY];
	NSTextFieldCell *old = column.dataCell;
	if (column == nil || [old isKindOfClass:TSMacroShortcutCell.class]) return;
	TSMacroShortcutCell *cell = [[TSMacroShortcutCell alloc] initTextCell:@""];
	cell.font = old.font; cell.alignment = old.alignment; cell.lineBreakMode = old.lineBreakMode; cell.controlSize = old.controlSize;
	cell.textColor = old.textColor; cell.drawsBackground = old.drawsBackground; cell.backgroundColor = old.backgroundColor;
	cell.editable = NO; cell.selectable = old.isSelectable;
	column.dataCell = cell;
}
