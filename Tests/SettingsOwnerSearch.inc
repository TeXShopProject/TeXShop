@interface TSSettingsWindowController (SearchRegression)
- (BOOL)control:(NSControl *)control textView:(NSTextView *)editor doCommandBySelector:(SEL)command;
- (void)controlTextDidChange:(NSNotification *)note;
@end
static void ChooseOwnerResult(TSSettingsWindowController *shell,NSString *target){
    NSUInteger index=[shell.searchResults indexOfObjectPassingTest:^BOOL(TSSettingsSearchResult *result,NSUInteger i,BOOL *stop){return [result.targetIdentifier isEqual:target];}];
    Check(index!=NSNotFound,@"Named real search target is present");
    [shell.categoryTable selectRowIndexes:[NSIndexSet indexSetWithIndex:index] byExtendingSelection:NO];
}
static void CheckOwnerSearch(TSPreferences *owner,TSSettingsWindowController *shell){
    NSDictionary *saved=[TSIsolatedAppKitDefaults.values copy];
    [shell beginSession];[shell selectCategoryIdentifier:TSSettingsCategoryEditor];[shell selectCategoryIdentifier:TSSettingsCategoryConsole];[shell goBack:nil];
    NSString *title=[fixture localizedStringForKey:@"catalog.general.0.0.title" value:nil table:@"SettingsCategories"];
    NSSearchField *field=shell.settingsSearchField;
    [field selectText:nil];NSTextView *editor=(NSTextView *)field.currentEditor;Check(editor!=nil,@"Real search field has an AppKit editor");
    NSUInteger count=shell.history.count;NSString *raw=[@"  " stringByAppendingString:title];
    editor.string=raw;field.stringValue=raw;[shell controlTextDidChange:[NSNotification notificationWithName:NSControlTextDidChangeNotification object:field]];
    NSSegmentedControl *arrows=[shell valueForKey:@"navigationControl"];
    Check([shell.searchQuery isEqual:raw] && [shell.history.currentIdentifier isEqual:TSSettingsCategoryEditor] && shell.history.count==count,@"Typing real search text retains raw spaces, category and history");
    Check(shell.window.firstResponder==editor && [arrows isEnabledForSegment:0] && [arrows isEnabledForSegment:1],@"Search keeps editor focus and existing history arrows");
    ChooseOwnerResult(shell,@"row.catalog.general.0.0");
    NSArray<NSView *> *highlights=[shell valueForKey:@"searchHighlights"];
    Check([shell.history.currentIdentifier isEqual:TSSettingsCategoryGeneral] && !shell.history.forwardIdentifier && highlights.count==1 && [highlights.firstObject.superview.identifier isEqual:@"row.catalog.general.0.0"],@"Selecting a real result visits and highlights exactly its row");
    [shell goBack:nil];Check([shell.history.currentIdentifier isEqual:TSSettingsCategoryEditor] && [shell.searchQuery isEqual:raw],@"Search Back follows history and preserves query");
    [shell goForward:nil];Check([shell.history.currentIdentifier isEqual:TSSettingsCategoryGeneral],@"Search Forward follows history");
    [field selectText:nil];editor=(NSTextView *)field.currentEditor;
    Check([shell control:field textView:editor doCommandBySelector:@selector(cancelOperation:)] && shell.searchQuery.length==0 && [shell.history.currentIdentifier isEqual:TSSettingsCategoryGeneral],@"Escape in the actual field clears search without rewinding category");
    [shell setSettingsSearchQuery:title];
    [[(NSSearchFieldCell *)field.cell cancelButtonCell]performClick:field];
    Check(!shell.searchQuery.length && !field.stringValue.length,@"Actual search cancel button clears query and text");
    for(NSString *blank in @[@"",@"  ",@"　"]){[shell setSettingsSearchQuery:title];[field selectText:nil];field.stringValue=blank;[shell controlTextDidChange:[NSNotification notificationWithName:NSControlTextDidChangeNotification object:field]];
        Check(!shell.searchQuery.length && [field.stringValue isEqual:blank],@"All deletion and blank input clear results while retaining raw text");}
    navigationTestWindow=shell.window;navigationTestSheet=[[NSWindow alloc]initWithContentRect:NSZeroRect styleMask:NSWindowStyleMaskBorderless backing:NSBackingStoreBuffered defer:NO];
    Method sheet=class_getInstanceMethod(NSWindow.class,@selector(attachedSheet));IMP oldSheet=method_setImplementation(sheet,(IMP)NavigationSheet);
    Check(![shell setSettingsSearchQuery:title] && !shell.searchQuery.length,@"Attached sheet blocks search edits");
    navigationTestSheet=nil;method_setImplementation(sheet,oldSheet);navigationTestWindow=nil;
    [shell selectCategoryIdentifier:TSSettingsCategoryEditor];
    Method alert=class_getInstanceMethod(NSAlert.class,@selector(beginSheetModalForWindow:completionHandler:));IMP oldAlert=method_setImplementation(alert,(IMP)CaptureOwnerAlert);
    EditOwnerField(owner,[owner valueForKey:@"tabIndentField"],@"bad");
    [shell setSettingsSearchQuery:title];ChooseOwnerResult(shell,@"row.catalog.general.0.0");
    Check([shell.history.currentIdentifier isEqual:TSSettingsCategoryEditor] && ownerAlertCompletion!=nil,@"Invalid real field prevents selecting a search destination");
    [shell setSettingsSearchQuery:@""];FinishOwnerAlert(NSAlertSecondButtonReturn);method_setImplementation(alert,oldAlert);
    [shell selectCategoryIdentifier:TSSettingsCategoryKeyboard];TSShortcutPaneController *keyboard=[shell valueForKey:@"keyboardPane"];
    NSSegmentedControl *mode=[keyboard valueForKey:@"searchMode"];mode.selectedSegment=1;[mode sendAction:mode.action to:mode.target];
    [TSIsolatedAppKitDefaults setObject:@"TAB" forKey:CommandCompletionCharKey];
    Check([keyboard handleKeySearchEvent:[NSEvent keyEventWithType:NSEventTypeKeyDown location:NSZeroPoint modifierFlags:0 timestamp:0 windowNumber:shell.window.windowNumber context:nil characters:@"\t" charactersIgnoringModifiers:@"\t" isARepeat:NO keyCode:48]],@"Actual Keyboard provider receives Tab");
    NSView *row=[keyboard valueForKey:@"highlightedCompletionRow"];
    Check(row!=nil && row.window==shell.window && row.layer.backgroundColor!=nil,@"Tab reservation highlights the real completion control in the current window");
    [keyboard stopKeySearch];Check([keyboard valueForKey:@"highlightedCompletionRow"]==nil && row.layer.backgroundColor==nil,@"Stopping key search clears the real completion highlight");
    // Each merged color result must mark only its own grid row.
    NSGridView *grid=(NSGridView *)Find([shell viewForCategoryIdentifier:TSSettingsCategoryAppearance],@"settings.color-table");
    // Rows: the column headings, Source, Console, Log, the Light Pages heading, Preview.
    NSArray<NSNumber *> *named=@[@1,@2,@3,@5];
    Check(grid.numberOfRows==6,@"Color table retains header, four named rows and the Light Pages heading");
    for(NSInteger c=1;c<4;c++){
        NSTextField *header=(NSTextField *)[grid cellAtColumnIndex:c rowIndex:0].contentView;
        CGFloat required=[header.stringValue sizeWithAttributes:@{NSFontAttributeName:header.font}].width;
        Check(header.maximumNumberOfLines==1 && NSWidth(header.bounds)>=required,@"Localized color column headings fit without breaking words");
    }
    NSArray *targets=@[@"settings.L8Q-Ov-EVr",@"settings.Kx3-n3-dsv",@"settings.FoL-zy-obh",@"settings.hCM-4U-XkM"];
    for(NSUInteger i=0;i<4;i++){
        NSString *name=[fixture localizedStringForKey:[NSString stringWithFormat:@"catalog.appearance.2.0.item.%lu",(unsigned long)i] value:nil table:@"SettingsCategories"];
        [shell setSettingsSearchQuery:name];ChooseOwnerResult(shell,targets[i]);[shell.window.contentView layoutSubtreeIfNeeded];
        NSArray<NSView *> *marks=[shell valueForKey:@"searchHighlights"];
        Check(marks.count==1 && marks[0].superview==grid,@"Merged color search highlights only its selected grid row");
        NSRect selected=marks[0].frame;
        for(NSInteger c=0;c<4;c++){
            NSView *content=[grid cellAtColumnIndex:c rowIndex:named[i].integerValue].contentView;
            if(content==nil || content==NSGridCell.emptyContentView)continue;
            NSRect bounds=[content convertRect:content.bounds toView:grid];
            Check(NSContainsRect(NSInsetRect(selected,4,2),bounds),@"Color row highlight leaves padding around names and percent fields");
        }
        for(NSNumber *j in named){
            NSView *label=[grid cellAtColumnIndex:0 rowIndex:j.integerValue].contentView;
            NSRect bounds=[label convertRect:label.bounds toView:grid];
            Check(NSIntersectsRect(selected,bounds)==(j.integerValue==named[i].integerValue),@"Color highlight identifies one named row without neighboring rows");
        }
    }
    [shell setSettingsSearchQuery:@""];
    TSIsolatedAppKitDefaults.values=[saved mutableCopy];[owner updateControlsFromUserDefaults:TSIsolatedAppKitDefaults];[shell beginSession];
    puts("PASS: real search editing, cancel, Escape, blanks, focus, history, row highlight, sheets, validation and Tab reservation");
}
