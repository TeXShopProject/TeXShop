	// TSAutoCompletionListEditor.m
// Created by Terada, Apr 2011

#import "globals.h"
#import "TSAutoCompletionListEditor.h"
#import "TSDialogButtonLayout.h"
#import "TSMarkMenu.h"
#import "GlobalData.h"

#define AutoCompletionRowsType @"TSAutoCompletionRowsType"

@implementation TSAutoCompletionListEditor

// BEGIN editor layout
// The guide names every placeholder a key binding can use, and the buttons
// follow the guidelines: Remove at the leading edge, Cancel and Save trailing.
- (void)layoutEditorWindow
{
    NSView *host = [window contentView];
    NSButton *save = nil, *cancel = nil, *remove = nil;
    NSTextField *guide = nil;
    for (NSView *view in host.subviews) {
        if ([view isKindOfClass:NSButton.class]) {
            SEL action = ((NSButton *)view).action;
            if (action == @selector(savePressed:)) save = (NSButton *)view;
            else if (action == @selector(cancelPressed:)) cancel = (NSButton *)view;
            else if (action == @selector(removePressed:)) remove = (NSButton *)view;
        } else if ([view isKindOfClass:NSTextField.class] && [((NSTextField *)view).stringValue containsString:@"#SEL#"]) guide = (NSTextField *)view;
    }
    if (guide) {
        guide.stringValue = [NSString stringWithFormat:@"%@\n%@", NSLocalizedString(@"* #SEL# = selected characters, #INS# = insertion point, #PASTE# = text on the clipboard", @"Key binding editor placeholder guide"), [TSMarkMenu markGuide]];
        guide.cell.wraps = YES; guide.cell.lineBreakMode = NSLineBreakByWordWrapping;
        // The guide spans the window with the same margin on both sides and
        // wraps at the window's width as designed, which is also its narrowest.
        NSSize minimum = window.contentMinSize;
        minimum.width = MAX(minimum.width, NSWidth(host.bounds));
        window.contentMinSize = minimum;
        NSRect frame = guide.frame;
        frame.size.width = NSWidth(host.bounds) - 2 * NSMinX(frame);
        guide.frame = frame;
        guide.autoresizingMask = NSViewWidthSizable | NSViewMaxYMargin;
        CGFloat needed = ceil([guide.cell cellSizeForBounds:NSMakeRect(0, 0, NSWidth(frame), CGFLOAT_MAX)].height);
        if (needed > NSHeight(frame)) {
            // Take the extra lines from the bottom of the list above the guide.
            CGFloat extra = needed - NSHeight(frame);
            frame.size.height = needed; guide.frame = frame;
            NSScrollView *list = [tableView enclosingScrollView];
            NSRect listFrame = list.frame;
            listFrame.origin.y += extra; listFrame.size.height -= extra;
            list.frame = listFrame;
        }
    }
    // The two input fields stand apart by the usual spacing between controls,
    // leaving room for the focus ring of each.
    if (newKeyField && newValueField) {
        NSRect key = newKeyField.frame;
        CGFloat gap = NSMinX(newValueField.frame) - NSMaxX(key);
        if (gap < 8) { key.size.width -= 8 - gap; newKeyField.frame = key; }
    }
    if (save && cancel) TSLayoutDialogButtons(host, @[save, cancel], remove ? @[remove] : @[]);
}
// END editor layout
- (IBAction)openAutoCompletionListEditor: (id)sender
{
	if(!window){
		if (![NSBundle loadNibNamed:@"AutoCompletionListEditor" owner:self]) {
			NSLog(@"Failed to load AutoCompletionListEditor.nib");
			NSBeep();
			return;
		}
		[tableView setDraggingSourceOperationMask:NSDragOperationMove forLocal:YES];
		[tableView registerForDraggedTypes:[NSArray arrayWithObject:AutoCompletionRowsType]];
		[self layoutEditorWindow];
		
		NSString *key;

		if ([GlobalData sharedGlobalData].g_autocompletionKeys) {
			self.autocompletionKeys = [NSMutableArray arrayWithArray:[GlobalData sharedGlobalData].g_autocompletionKeys];
		}else {
			self.autocompletionKeys = [NSMutableArray arrayWithArray:[[GlobalData sharedGlobalData].g_autocompletionDictionary allKeys]];
		}

		self.autocompletionValues = [NSMutableArray arrayWithCapacity:0];
        NSArray *autocompletionKeysCopy = [NSArray arrayWithArray:self.autocompletionKeys];
		NSEnumerator *enumerator = [autocompletionKeysCopy objectEnumerator];
		while ((key = [enumerator nextObject])) {
			if ([[[GlobalData sharedGlobalData].g_autocompletionDictionary allKeys] containsObject:key]){
                [self.autocompletionValues addObject:[[GlobalData sharedGlobalData].g_autocompletionDictionary objectForKey:key]];
            }else{
                [self.autocompletionKeys removeObjectIdenticalTo:key];
            }
		}

		enumerator = [[[GlobalData sharedGlobalData].g_autocompletionDictionary allKeys] objectEnumerator];
		while ((key = [enumerator nextObject])) {
            if (![self.autocompletionKeys containsObject:key]) {
                [self.autocompletionKeys addObject:key];
                [self.autocompletionValues addObject:[[GlobalData sharedGlobalData].g_autocompletionDictionary objectForKey:key]];
            }
		}
		
//		[autocompletionKeys retain];
//		[autocompletionValues retain];
	}
	
	[window makeKeyAndOrderFront:nil];
}



- (IBAction)addPressed:(id)sender
{
	NSString *newKey = [newKeyField stringValue];
  //  if ([newKey isEqualToString:@"tab"])
  //\t      newKey = @"\t";
	if ([newKey isEqualToString:@""]) {
		NSBeep();
	}else{
		NSUInteger _index = [self.autocompletionKeys indexOfObject:newKey];
		if (_index != NSNotFound) {
			NSInteger result = NSRunAlertPanel(NSLocalizedString(@"Warning", @"Warning"), 
										 [NSString stringWithFormat:NSLocalizedString(@"Your current setting of %@ will be replaced. OK?", @"Your current setting of %@ will be replaced. OK?"), newKey], 
										 @"OK", NSLocalizedString(@"Cancel", @"Cancel"), nil);
			if (result == NSAlertDefaultReturn) {
				[self.autocompletionValues replaceObjectAtIndex:_index withObject:[newValueField stringValue]];
			}else {
				return;
			}
		}else {
			[self.autocompletionKeys insertObject:newKey atIndex:0];
			[self.autocompletionValues insertObject:[newValueField stringValue] atIndex:0];
		}

		[newKeyField setStringValue:@""];
		[newValueField setStringValue:@""];
		[newKeyField becomeFirstResponder];
		[tableView reloadData];
	}
}

/*
- (void)windowWillClose:(NSNotification *)notification
{
	[self.autocompletionKeys	release];
	[self.autocompletionValues release];
	window = nil;
}
*/


- (void)removeObjectsAtIndexes:(NSIndexSet*)indexes
{
	[self.autocompletionKeys removeObjectsAtIndexes:indexes];
	[self.autocompletionValues removeObjectsAtIndexes:indexes];
	[tableView reloadData];
}

- (IBAction)savePressed:(id)sender
{
	NSMutableDictionary *newAutoCompletionList = [NSMutableDictionary dictionaryWithCapacity:0];
	NSInteger i;
	for(i=0;i<[self.autocompletionKeys count];i++){
		[newAutoCompletionList setObject:[self.autocompletionValues objectAtIndex:i] forKey:[self.autocompletionKeys objectAtIndex:i]];
	}
    
/*
	if (g_autocompletionDictionary) [g_autocompletionDictionary release];
	g_autocompletionDictionary = [newAutoCompletionList retain];
	if (g_autocompletionKeys) [g_autocompletionKeys release];
	g_autocompletionKeys = [self.autocompletionKeys retain];
*/
    
    [GlobalData sharedGlobalData].g_autocompletionDictionary = newAutoCompletionList;
    [GlobalData sharedGlobalData].g_autocompletionKeys = self.autocompletionKeys;
	
	NSString	*filePath;
	filePath = [[[AutoCompletionPath stringByStandardizingPath] stringByAppendingPathComponent:@"autocompletion"] stringByAppendingPathExtension:@"plist"];
	[[GlobalData sharedGlobalData].g_autocompletionDictionary writeToFile:filePath atomically:NO];

	filePath = [[[AutoCompletionPath stringByStandardizingPath] stringByAppendingPathComponent:@"autocompletionDisplayOrder"] stringByAppendingPathExtension:@"plist"];
	[[GlobalData sharedGlobalData].g_autocompletionKeys writeToFile:filePath atomically:NO];

	[window close];
}

- (IBAction)cancelPressed:(id)sender
{
	[window close];
}

- (IBAction)removePressed:(id)sender
{
	[self removeObjectsAtIndexes:[tableView selectedRowIndexes]]; 
	[tableView selectRowIndexes:nil byExtendingSelection:NO];
}

- (NSInteger)numberOfRowsInTableView:(NSTableView*)aTableView
{
	return [self.autocompletionKeys count];
}

- (id)tableView:(NSTableView *)aTableView objectValueForTableColumn:(NSTableColumn *)aTableColumn row:(NSInteger)rowIndex
{
	return [[aTableColumn identifier] isEqualToString:@"key"] ? [self.autocompletionKeys objectAtIndex:rowIndex] :[self.autocompletionValues objectAtIndex:rowIndex];
}

- (void)tableView:(NSTableView *)aTableView
   setObjectValue:(id)object 
   forTableColumn:(NSTableColumn *)tableColumn 
			  row:(NSInteger)rowIndex;
{
	if ([[tableColumn identifier] isEqualToString:@"key"]) {
		[self.autocompletionKeys replaceObjectAtIndex:rowIndex withObject:object];
    }else {
		[self.autocompletionValues replaceObjectAtIndex:rowIndex withObject:object];
	}

}

- (void)removeDraggedOutRows
{
	NSPasteboard *pboard = [NSPasteboard pasteboardWithName:NSDragPboard];
	NSData *rowData = [pboard dataForType:AutoCompletionRowsType];
	NSIndexSet *rowIndexes = [NSKeyedUnarchiver unarchiveObjectWithData:rowData];
	[self removeObjectsAtIndexes:rowIndexes];
}

- (BOOL)tableView:(NSTableView *)aTableView
writeRowsWithIndexes:(NSIndexSet *)rowIndexes 
	 toPasteboard:(NSPasteboard *)pboard
{
	// declare our own pasteboard types
    NSArray *typesArray = [NSArray arrayWithObject:AutoCompletionRowsType];
	[pboard declareTypes:typesArray owner:self];
	
    // add rows array for local move
	NSData *rowIndexesArchive = [NSKeyedArchiver archivedDataWithRootObject:rowIndexes];
    [pboard setData:rowIndexesArchive forType:AutoCompletionRowsType];
	
    return YES;
}


- (NSDragOperation)tableView:(NSTableView*)aTableView 
				validateDrop:(id <NSDraggingInfo>)info 
				 proposedRow:(NSInteger)row 
	   proposedDropOperation:(NSTableViewDropOperation)op
{
	// Accept drop between rows. (not on a row)
    [aTableView setDropRow:row dropOperation:NSTableViewDropAbove];
	
	return NSDragOperationMove;
}

- (NSIndexSet*)moveObjectsOf:(NSMutableArray*)anArray
				 fromIndexes:(NSIndexSet*)fromIndexSet 
					 toIndex:(NSUInteger)insertIndex
{	
	// If any of the removed objects come before the insertion index,
	// we need to decrement the index appropriately
	NSUInteger adjustedInsertIndex = insertIndex - [fromIndexSet countOfIndexesInRange:(NSRange){0, insertIndex}];
	NSRange destinationRange = NSMakeRange(adjustedInsertIndex, [fromIndexSet count]);
	NSIndexSet *destinationIndexes = [NSIndexSet indexSetWithIndexesInRange:destinationRange];
	
	NSArray *objectsToMove = [anArray objectsAtIndexes:fromIndexSet];
	[anArray removeObjectsAtIndexes:fromIndexSet];	
	[anArray insertObjects:objectsToMove atIndexes:destinationIndexes];
	
	return destinationIndexes;
}

- (BOOL)tableView:(NSTableView*)aTableView
	   acceptDrop:(id <NSDraggingInfo>)info
			  row:(NSInteger)insertionRow
	dropOperation:(NSTableViewDropOperation)op
{
    if (insertionRow < 0)
	{
		insertionRow = 0;
	}
	// if drag source is self, it's a move unless the Option key is pressed
    if ([info draggingSource] == tableView)
	{
		NSEvent *currentEvent = [NSApp currentEvent];
		NSInteger optionKeyPressed = [currentEvent modifierFlags] & NSAlternateKeyMask;
		
		if (optionKeyPressed == 0)
		{
			NSData *rowsData = [[info draggingPasteboard] dataForType:AutoCompletionRowsType];
			NSIndexSet *indexSet = [NSKeyedUnarchiver unarchiveObjectWithData:rowsData];
			NSIndexSet *newIndexes = [self moveObjectsOf:self.autocompletionKeys fromIndexes:indexSet toIndex:insertionRow];
			[self moveObjectsOf:self.autocompletionValues fromIndexes:indexSet toIndex:insertionRow];
			[aTableView selectRowIndexes:newIndexes byExtendingSelection:NO]; // select the row which has just been moved
			[aTableView reloadData];
			return YES;
		}
    }
	
    return NO;
}

@end
