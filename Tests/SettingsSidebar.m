// Complete production-owner regression; included by SettingsProductShell.m.
// Boundary substitutes report key/visible/sheet state without ordering windows.
static NSWindow *navigationTestWindow, *navigationTestSheet;
static NSRect NavigationSmallScreen(id receiver,SEL selector){return NSMakeRect(0,0,800,650);}
static BOOL NavigationRestoreFrame(id receiver,SEL selector,NSString *name){[(NSWindow *)receiver setFrame:NSMakeRect(25,35,960,680) display:NO];return YES;}
static BOOL navigationTestKey, navigationTestVisible, navigationTestMiniaturized;
static NSUInteger navigationFrontRequests;
static BOOL NavigationKey(id receiver,SEL selector){return receiver==navigationTestWindow && navigationTestKey;}
static BOOL NavigationVisible(id receiver,SEL selector){return receiver==navigationTestWindow && navigationTestVisible;}
static BOOL NavigationMiniaturized(id receiver,SEL selector){return receiver==navigationTestWindow && navigationTestMiniaturized;}
static id NavigationSheet(id receiver,SEL selector){return receiver==navigationTestWindow?navigationTestSheet:nil;}
static void NavigationFront(id receiver,SEL selector,id sender){if(receiver==navigationTestWindow)navigationFrontRequests++;}
static NSEvent *NavigationKeyEvent(NSString *characters,NSEventModifierFlags flags,NSUInteger code){return [NSEvent keyEventWithType:NSEventTypeKeyDown location:NSZeroPoint modifierFlags:flags timestamp:0 windowNumber:navigationTestWindow.windowNumber context:nil characters:characters charactersIgnoringModifiers:characters isARepeat:NO keyCode:code];}
@interface SettingsFontProbe:NSObject
@property NSFont *converted;
@end
@implementation SettingsFontProbe
- (NSFont *)convertFont:(NSFont *)font{return self.converted;}
@end
@interface SettingsNavigationSegment:NSSegmentedControl
@property NSInteger forcedSegment;
@end
@implementation SettingsNavigationSegment
- (NSInteger)selectedSegment{return self.forcedSegment;}
@end
static void CheckOwnerNavigation(TSPreferences *owner,TSSettingsWindowController *shell){
    TSSettingsNavigationHistory *h=[TSSettingsNavigationHistory new];[h resetWithIdentifier:@"a"];
    Check(h.count==1 && !h.backIdentifier && !h.forwardIdentifier,@"Initial history has only its current category");
    [h visitIdentifier:@"b"];[h visitIdentifier:@"c"];[h goBack];Check([h.currentIdentifier isEqual:@"b"] && [h.forwardIdentifier isEqual:@"c"],@"History moves back and forward");
    [h visitIdentifier:@"d"];Check(!h.forwardIdentifier && h.count==3,@"A new visit truncates forward history");[h visitIdentifier:@"d"];Check(h.count==3,@"Repeat visits do not duplicate history");
    for(int i=0;i<60;i++)[h visitIdentifier:[NSString stringWithFormat:@"%d",i]];Check(h.count==50,@"History has a fifty-entry bound");
    for(int i=0;i<60;i++)[h goBack];Check([h.currentIdentifier isEqual:@"10"],@"The oldest entries are evicted");
    Method screenFrame=class_getInstanceMethod(NSScreen.class,@selector(visibleFrame));IMP oldScreenFrame=method_setImplementation(screenFrame,(IMP)NavigationSmallScreen);
    TSSettingsWindowController *small=[[TSSettingsWindowController alloc]initWithDefaults:TSIsolatedAppKitDefaults];
    NSView *footer=[NSView new];footer.hidden=YES;[small hostPaneControllers:@{} footer:footer];
    Check(NSWidth(small.window.frame)<=800 && NSHeight(small.window.frame)<=650 && small.window.contentMinSize.width<=800,@"New settings window fits a small screen");
    method_setImplementation(screenFrame,oldScreenFrame);
    Method frameName=class_getInstanceMethod(NSWindow.class,@selector(setFrameAutosaveName:));IMP oldFrameName=method_setImplementation(frameName,(IMP)NavigationRestoreFrame);
    TSSettingsWindowController *restored=[[TSSettingsWindowController alloc]initWithDefaults:TSIsolatedAppKitDefaults];[restored hostPaneControllers:@{} footer:footer];
    Check(NSEqualRects(restored.window.frame,NSMakeRect(25,35,960,680)),@"Host setup respects the frame returned by AppKit restoration");
    method_setImplementation(frameName,oldFrameName);
    [shell.window.contentView layoutSubtreeIfNeeded];
    NSView *sidebar=shell.settingsSearchField.superview,*content=shell.contentScroll.superview;
    // As in System Settings: the search field stays below the titlebar, while the content
    // scrolls under the toolbar with a top inset equal to the titlebar height.
    CGFloat titlebar=NSMaxY(content.bounds)-NSMaxY(content.safeAreaRect);
    Check(NSMaxY(shell.settingsSearchField.frame)<=NSMaxY(sidebar.safeAreaRect)-5 && titlebar>0 && NSMaxY(shell.contentScroll.frame)>=NSMaxY(content.bounds)-1 && shell.contentScroll.automaticallyAdjustsContentInsets && fabs(shell.contentScroll.contentInsets.top-titlebar)<1,@"Search stays below the titlebar; content scrolls under the toolbar with a matching inset");
    NSDictionary *saved=[TSIsolatedAppKitDefaults.values copy];
    [TSIsolatedAppKitDefaults setObject:@"unknown" forKey:TSSettingsSelectedCategoryKey];[shell beginSession];
    Check([shell.history.currentIdentifier isEqual:TSSettingsCategoryGeneral] && shell.categoryTable.selectedRow==0,@"Unknown stored ID opens General");
    NSSegmentedControl *navigation=[shell valueForKey:@"navigationControl"];
    Check(shell.window.firstResponder==shell.categoryTable && ![navigation isEnabledForSegment:0] && ![navigation isEnabledForSegment:1],@"Reopening focuses the sidebar with no history arrows");
    Check(!shell.shouldCascadeWindows && shell.window.title.length>0,@"Settings has a title and disables cascading");
    Check(shell.window.toolbar.items.count==2 && [shell.window.toolbar.items[0] isKindOfClass:NSTrackingSeparatorToolbarItem.class] && shell.window.toolbar.items[1].navigational,@"Toolbar has its tracking divider and navigational control");
    NSRect frame=shell.window.frame;
    for(NSString *category in shell.categoryIdentifiers)[shell selectCategoryIdentifier:category];
    Check(NSEqualRects(frame,shell.window.frame),@"Category navigation does not resize the window");
    [shell selectCategoryIdentifier:TSSettingsCategoryKeyboard];Check(shell.window.contentMinSize.height>=560,@"Keyboard minimum fits its input sections");
    [shell selectCategoryIdentifier:TSSettingsCategoryGeneral];Check(shell.window.contentMinSize.height==560,@"Leaving Keyboard restores the ordinary minimum height");
    [shell selectCategoryIdentifier:TSSettingsCategoryEditor];[shell selectCategoryIdentifier:TSSettingsCategoryConsole];
    navigationTestWindow=shell.window;
    Method key=class_getInstanceMethod(NSWindow.class,@selector(isKeyWindow)),sheet=class_getInstanceMethod(NSWindow.class,@selector(attachedSheet));
    IMP oldKey=method_setImplementation(key,(IMP)NavigationKey),oldSheet=method_setImplementation(sheet,(IMP)NavigationSheet);
    navigationTestSheet=[[NSWindow alloc]initWithContentRect:NSZeroRect styleMask:NSWindowStyleMaskBorderless backing:NSBackingStoreBuffered defer:NO];
    NSUInteger count=shell.history.count;
    [shell goBack:nil];Check([shell.history.currentIdentifier isEqual:TSSettingsCategoryConsole] && ![shell selectCategoryIdentifier:TSSettingsCategoryGeneral] && shell.history.count==count,@"Attached sheet blocks both history and sidebar navigation");
    Check(![owner finishPreferenceEditing:YES],@"An attached sheet blocks the owner editing transaction");
    navigationTestSheet=nil;navigationTestKey=YES;
    Check([shell.window performKeyEquivalent:NavigationKeyEvent(@"[",NSEventModifierFlagCommand,33)] && [shell.history.currentIdentifier isEqual:TSSettingsCategoryEditor],@"Command-left-bracket follows real history in the key settings window");
    navigationTestKey=NO;[shell.window performKeyEquivalent:NavigationKeyEvent(@"[",NSEventModifierFlagCommand,33)];Check([shell.history.currentIdentifier isEqual:TSSettingsCategoryEditor],@"Inactive settings window does not consume history shortcut");
    navigationTestKey=YES;Check([shell.window performKeyEquivalent:NavigationKeyEvent(@"]",NSEventModifierFlagCommand,30)] && [shell.history.currentIdentifier isEqual:TSSettingsCategoryConsole],@"Command-right-bracket follows forward history");
    [shell selectCategoryIdentifier:TSSettingsCategoryGeneral];[shell.window makeFirstResponder:shell.categoryTable];
    NSString *typed=[fixture localizedStringForKey:TSSettingsCategoryUpdates value:nil table:@"SettingsCategories"];
    [shell.categoryTable keyDown:NavigationKeyEvent(typed,0,0)];
    Check([shell.history.currentIdentifier isEqual:TSSettingsCategoryUpdates],@"Typing a localized category name selects its sidebar row");
    [shell selectCategoryIdentifier:TSSettingsCategoryGeneral];[shell.window makeFirstResponder:shell.categoryTable];
    [shell.categoryTable keyDown:NavigationKeyEvent(@"\uF701",NSEventModifierFlagFunction|NSEventModifierFlagNumericPad,125)];
    Check([shell.history.currentIdentifier isEqual:TSSettingsCategoryDocuments],@"Arrow keys navigate the actual sidebar");
    [shell.categoryTable keyDown:NavigationKeyEvent(@"\uF701",NSEventModifierFlagFunction|NSEventModifierFlagNumericPad,125)];
    Check([shell.history.currentIdentifier isEqual:TSSettingsCategoryEditor],@"Arrow navigation skips group gaps");
    [shell endSession];[shell beginSession];Check(shell.history.count==1 && [shell.history.currentIdentifier isEqual:TSSettingsCategoryEditor] && ![navigation isEnabledForSegment:0] && ![navigation isEnabledForSegment:1],@"Reopening retains category and clears history/buttons");
    Method visible=class_getInstanceMethod(NSWindow.class,@selector(isVisible)),front=class_getInstanceMethod(NSWindow.class,@selector(makeKeyAndOrderFront:));
    IMP oldVisible=method_setImplementation(visible,(IMP)NavigationVisible),oldFront=method_setImplementation(front,(IMP)NavigationFront);
    navigationTestVisible=YES;NSDictionary *before=[TSIsolatedAppKitDefaults dictionaryRepresentation];NSMapTable *rules=[owner valueForKey:@"inputRules"];
    [owner showPreferences:nil];Check(navigationFrontRequests==1 && [owner valueForKey:@"inputRules"]==rules && [[TSIsolatedAppKitDefaults dictionaryRepresentation]isEqual:before],@"Showing an already-open panel only brings it forward");
    navigationTestVisible=NO;navigationTestMiniaturized=YES;
    Method mini=class_getInstanceMethod(NSWindow.class,@selector(isMiniaturized));IMP oldMini=method_setImplementation(mini,(IMP)NavigationMiniaturized);
    [owner showPreferences:nil];Check(navigationFrontRequests==2 && [owner valueForKey:@"inputRules"]==rules,@"Showing a miniaturized panel only brings the existing session forward");
    method_setImplementation(mini,oldMini);navigationTestMiniaturized=NO;
    navigationTestVisible=NO;method_setImplementation(visible,oldVisible);method_setImplementation(front,oldFront);
    // Forwarding and ownership are tested without asking NSFontManager to open a panel.
    SettingsFontProbe *font=[SettingsFontProbe new];font.converted=[NSFont userFontOfSize:17];
    [owner setValue:@NO forKey:@"endingPreferences"];[owner setValue:@YES forKey:@"ownsFontPanel"];[owner setValue:@1 forKey:@"fontEditingContext"];
    [shell changeFont:font];NSFont *stored=[NSUnarchiver unarchiveObjectWithData:[TSIsolatedAppKitDefaults dataForKey:DocumentFontKey]];
    Check(fabs(stored.pointSize-17)<0.01,@"Settings forwards font edits to the owning document-font setting");
    [owner setValue:@2 forKey:@"fontEditingContext"];font.converted=[NSFont userFontOfSize:19];[shell changeFont:font];
    Check(fabs([TSIsolatedAppKitDefaults doubleForKey:ConsoleFontSizeKey]-19)<0.01,@"Console font uses its explicit editing destination");
    before=[TSIsolatedAppKitDefaults dictionaryRepresentation];[owner setValue:@NO forKey:@"ownsFontPanel"];font.converted=[NSFont userFontOfSize:23];[shell changeFont:font];Check([[TSIsolatedAppKitDefaults dictionaryRepresentation]isEqual:before],@"A font panel owned elsewhere cannot change settings");
    NSUInteger queriedCount=shell.history.count;
    for(NSInteger row=0;row<shell.categoryTable.numberOfRows;row++)[(id<NSTableViewDelegate>)shell tableView:shell.categoryTable shouldSelectRow:row];
    Check(shell.history.count==queriedCount,@"Selection eligibility queries never add history");
    [shell selectCategoryIdentifier:TSSettingsCategoryGeneral];[shell selectCategoryIdentifier:TSSettingsCategoryEditor];[shell selectCategoryIdentifier:TSSettingsCategoryConsole];
    Check(navigation.target==shell && navigation.action==@selector(navigate:),@"Toolbar segments use the production navigation action");
    SettingsNavigationSegment *segment=[SettingsNavigationSegment new];segment.forcedSegment=0;[NSApp sendAction:navigation.action to:navigation.target from:segment];
    Check([shell.history.currentIdentifier isEqual:TSSettingsCategoryEditor] && [navigation isEnabledForSegment:1],@"Back toolbar segment synchronizes current category and forward availability");
    segment.forcedSegment=1;[NSApp sendAction:navigation.action to:navigation.target from:segment];
    Check([shell.history.currentIdentifier isEqual:TSSettingsCategoryConsole] && ![navigation isEnabledForSegment:1],@"Forward toolbar segment synchronizes current category and availability");
    [shell selectCategoryIdentifier:TSSettingsCategoryEditor];[shell.window.contentView layoutSubtreeIfNeeded];
    [shell.contentScroll.contentView scrollToPoint:NSMakePoint(0,150)];
    NSPoint scrolled=shell.contentScroll.contentView.bounds.origin;Check(scrolled.y>0,@"Tall Editor pane is scrolled before validation test");
    Method alertMethod=class_getInstanceMethod(NSAlert.class,@selector(beginSheetModalForWindow:completionHandler:));IMP oldAlert=method_setImplementation(alertMethod,(IMP)CaptureOwnerAlert);
    NSTextField *tabs=[owner valueForKey:@"tabIndentField"];EditOwnerField(owner,tabs,@"bad");
    NSResponder *focused=shell.window.firstResponder;NSUInteger rejectedCount=shell.history.count, rejectedAlerts=ownerAlertCount;
    [shell.categoryTable selectRowIndexes:[NSIndexSet indexSetWithIndex:0] byExtendingSelection:NO];
    Check([shell.history.currentIdentifier isEqual:TSSettingsCategoryEditor] && shell.categoryTable.selectedRow==3 && shell.history.count==rejectedCount && NSEqualPoints(scrolled,shell.contentScroll.contentView.bounds.origin),@"Rejected real sidebar selection restores row and preserves scroll/history");
    Check(ownerAlertCount==rejectedAlerts+1,@"A real category selection validates the invalid edit exactly once");
    Check(shell.window.firstResponder==focused,@"Rejected selection retains the invalid field's editor");
    FinishOwnerAlert(NSAlertSecondButtonReturn);Check([shell selectCategoryIdentifier:TSSettingsCategoryPreview],@"Restored field permits the next category");
    Check(fabs(shell.contentScroll.contentView.bounds.origin.y+shell.contentScroll.contentInsets.top)<1 && shell.contentScroll.contentInsets.top>0 && shell.window.firstResponder!=shell.categoryTable,@"Successful content navigation shows the top of the pane below the toolbar without stealing sidebar focus");
    // The four invisible-character pop-up menus beside switches share one width.
    {
        Check([shell selectCategoryIdentifier:TSSettingsCategoryEditor],@"Editor opens for pop-up widths");[shell.window.contentView layoutSubtreeIfNeeded];
        NSMutableArray<NSPopUpButton *> *popups=[NSMutableArray array];NSMutableArray<NSView *> *queue=[NSMutableArray arrayWithObject:shell.contentScroll.documentView];
        while(queue.count){NSView *v=queue.firstObject;[queue removeObjectAtIndex:0];
            if([v.identifier hasPrefix:@"row.catalog.editor.5."] && ![v.identifier isEqual:@"row.catalog.editor.5.0"]){NSMutableArray *q=[NSMutableArray arrayWithObject:v];while(q.count){NSView *w=q.firstObject;[q removeObjectAtIndex:0];if([w isKindOfClass:NSPopUpButton.class])[popups addObject:(NSPopUpButton *)w];[q addObjectsFromArray:w.subviews];}continue;}
            [queue addObjectsFromArray:v.subviews];}
        BOOL equal=popups.count==4;CGFloat width=NSWidth(popups.firstObject.frame);
        for(NSPopUpButton *p in popups)equal&=fabs(NSWidth(p.frame)-width)<0.5 && NSWidth(p.frame)+0.5>=p.intrinsicContentSize.width;
        NSMutableString *sizes=[NSMutableString string];for(NSPopUpButton *p in popups)[sizes appendFormat:@" %.1f/%.1f(%ld items)",NSWidth(p.frame),p.intrinsicContentSize.width,(long)p.numberOfItems];
        Check(equal,[NSString stringWithFormat:@"The four invisible-character pop-up menus share one width (%lu found:%@)",(unsigned long)popups.count,sizes]);
    }
    // Rows revealed in the pane are below the toolbar, not under it.
    {
        NSClipView *clip=shell.contentScroll.contentView; CGFloat inset=shell.contentScroll.contentInsets.top;
        NSMutableArray<NSView *> *rows=[NSMutableArray array]; NSMutableArray<NSView *> *queue=[NSMutableArray arrayWithObject:shell.contentScroll.documentView];
        while(queue.count){NSView *v=queue.firstObject;[queue removeObjectAtIndex:0];if([v.identifier hasPrefix:@"row."])[rows addObject:v];[queue addObjectsFromArray:v.subviews];}
        BOOL (^visible)(NSView *)=^BOOL(NSView *row){NSRect r=[row convertRect:row.bounds toView:clip];NSRect b=clip.bounds;
            CGFloat top=clip.isFlipped?NSMinY(r):NSMaxY(b)-NSMaxY(r), limit=clip.isFlipped?NSMinY(b)+inset:inset;
            return (clip.isFlipped?top>=limit-1:top>=limit-1) && (clip.isFlipped?NSMaxY(r)<=NSMaxY(b)+1:NSMinY(r)>=NSMinY(b)-1);};
        Check(rows.count>3 && visible(rows.firstObject),@"The first row of a pane starts below the toolbar");
        [rows.lastObject scrollRectToVisible:rows.lastObject.bounds];
        Check(visible(rows.lastObject),@"A revealed lower row is below the toolbar");
        [rows.firstObject scrollRectToVisible:rows.firstObject.bounds];
        Check(visible(rows.firstObject),@"A revealed upper row is not hidden under the toolbar");
    }
    method_setImplementation(alertMethod,oldAlert);
    Check((shell.window.styleMask&NSWindowStyleMaskFullSizeContentView)!=0 && shell.contentScroll.documentView.isFlipped,@"Full-height shell keeps a top-origin document");
    Check([shell.categoryIdentifiers isEqual:@[@"general",@"documents",@"editor",@"keyboard",@"spelling",@"appearance",@"preview",@"typesetting",@"console",@"updates"]] && shell.categoryTable.numberOfRows==13,@"Ten categories retain stable order and three grouping gaps");
    {NSMutableArray *starts=[NSMutableArray array];for(NSString *category in shell.categoryIdentifiers)if([TSSettingsCategory standardCategoryWithIdentifier:category].startsGroup)[starts addObject:category];
     Check([starts isEqual:@[@"editor",@"preview",@"updates"]],@"Keyboard follows Editor in its group; Updates is a group of its own");}
    for(NSString *category in shell.categoryIdentifiers){BOOL selected=[shell selectCategoryIdentifier:category];[shell.window.contentView layoutSubtreeIfNeeded];NSView *view=[category isEqual:TSSettingsCategoryKeyboard]?[[shell valueForKey:@"keyboardPane"]view]:[shell viewForCategoryIdentifier:category];Check(selected && view.window==shell.window,[NSString stringWithFormat:@"Selected %@ current %@ attached %@ expected %@ accepted %d",category,shell.history.currentIdentifier,view.window,shell.window,selected]);}
    [owner setValue:@0 forKey:@"fontEditingContext"];
    method_setImplementation(key,oldKey);method_setImplementation(sheet,oldSheet);navigationTestWindow=nil;
    TSIsolatedAppKitDefaults.values=[saved mutableCopy];[owner updateControlsFromUserDefaults:TSIsolatedAppKitDefaults];[shell beginSession];
    puts("PASS: actual shell history bound, arrows, sheets, reopen, frame, already-visible owner and font ownership");
}
