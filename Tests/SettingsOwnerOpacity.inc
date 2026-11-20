#import "TSThemeFileStore.h"
#import "TSSettingsThemeList.h"
#import <objc/message.h>
static NSLocale *opacityTestLocale;
static id OpacityLocale(id cls, SEL cmd) { return opacityTestLocale; }
static NSUInteger opacityWrites;
static IMP opacityOriginalWrite;
static BOOL CountOpacityWrite(id store,SEL selector,NSDictionary *colors,NSString *title,NSError **error){
    opacityWrites++;return ((BOOL(*)(id,SEL,id,id,NSError **))opacityOriginalWrite)(store,selector,colors,title,error);
}
// A color change in Settings writes only its changes into the file (writeChangesFrom:to:title:error:).
static IMP opacityOriginalChanges;
static NSDictionary *CountOpacityChanges(id store,SEL selector,NSDictionary *before,NSDictionary *after,NSString *title,NSError **error){
    opacityWrites++;return ((NSDictionary *(*)(id,SEL,id,id,id,NSError **))opacityOriginalChanges)(store,selector,before,after,title,error);
}
static NSUInteger opacityRejections;
static void EnterOpacity(NSTextField *field,NSString *text,BOOL typing){
    [field selectText:nil];NSTextView *editor=(NSTextView *)field.currentEditor;
    Check(editor!=nil,@"Opacity field uses the AppKit field editor");
    [editor selectAll:nil];
    if(typing){
        [editor insertText:@"" replacementRange:editor.selectedRange];
        for(NSUInteger i=0;i<text.length;i++)[editor insertText:[text substringWithRange:NSMakeRange(i,1)] replacementRange:editor.selectedRange];
    }else [editor insertText:text replacementRange:editor.selectedRange];
    Check([editor.string isEqual:text.precomposedStringWithCompatibilityMapping],@"Opacity retains the complete typed or pasted text until commit");
}
static void TypeOpacity(NSTextField *field,NSString *text){EnterOpacity(field,text,NO);}
static void EndOpacity(NSTextField *field){[field.window makeFirstResponder:nil];}
static double StoredOpacity(TSPreferences *owner,NSString *key){return [[owner valueForKey:@"EditingColors"][key][3]doubleValue];}
static void CheckOpacityField(TSPreferences *owner,TSSettingsWindowController *shell,NSColorWell *well,NSArray *rgb,NSString *key,NSString *path){
    NSView *pane=[shell viewForCategoryIdentifier:TSSettingsCategoryAppearance];
    NSSlider *slider=(NSSlider *)Find(pane,[@"opacity." stringByAppendingString:well.identifier]);
    NSTextField *field=(NSTextField *)Find(pane,[@"opacity-value." stringByAppendingString:well.identifier]);
    Check(field!=nil && field.editable && [field.formatter isKindOfClass:TSOpacityFormatter.class] && field.controlSize==NSControlSizeSmall && [field.accessibilityLabel isEqual:slider.accessibilityLabel],@"Opacity has an editable whole-percentage field");
    TSOpacityFormatter *formatter=(TSOpacityFormatter *)field.formatter;
    formatter.rejectionHandler=^{opacityRejections++;};
    id value=nil;
    Check([formatter getObjectValue:&value forString:@"150" errorDescription:NULL] && [value integerValue]==100,@"Opacity entry above 100 is clamped to 100");
    Check([formatter getObjectValue:&value forString:@"\uFF16\uFF15" errorDescription:NULL] && [value integerValue]==65,@"Full-width opacity digits follow the other numeric fields");
    TSPreferenceInput *numericRule=[[TSPreferenceInput alloc]initWithKey:@"test" kind:TSPreferenceInputInteger minimum:0 maximum:100 allowsEmpty:NO notification:nil];
    Check([numericRule validatedValue:@"\uFF16\uFF15"].numberValue.integerValue==65,@"Full-width opacity digits follow the other numeric fields");
    Check([formatter getObjectValue:&value forString:@"-5" errorDescription:NULL] && [value integerValue]==0,@"Negative opacity is clamped to zero");
    for(NSString *bad in @[@"abc",@"-",@"+",@".",@"",@"   ",@"65.5",@"65,5",@"+3",@"6a"])Check(![formatter getObjectValue:&value forString:bad errorDescription:NULL],@"Opacity entry refuses letters, signs and decimals");
    // Start from a known fractional alpha, then exercise typed entry through the real field editor.
    well.color=[NSColor colorWithSRGBRed:[rgb[0]doubleValue] green:[rgb[1]doubleValue] blue:[rgb[2]doubleValue] alpha:0.1234];
    NSUInteger writes=opacityWrites;
    double savedBefore=StoredOpacity(owner,key);
    [field selectText:nil];EndOpacity(field);
    Check(opacityWrites==writes && fabs(StoredOpacity(owner,key)-savedBefore)<1e-12 && fabs(well.color.alphaComponent-0.1234)<1e-9,@"Passing through the opacity field keeps the stored fractional alpha");
    TypeOpacity(field,@"12");EndOpacity(field);
    Check(opacityWrites==writes+1 && fabs(StoredOpacity(owner,key)-0.12)<1e-9,@"Explicitly entering the displayed integer replaces a fractional opacity");
    struct {__unsafe_unretained NSString *text; double expected; BOOL rejected;} cases[]={
        {@"65",65,NO},{@"150",100,NO},{@" 65 ",65,NO},{@"-5",0,NO},{@"99999",100,NO},{@"9999999999999999999",100,NO},{@"18446744073709551615",100,NO},{@"999999999999999999999999999999",100,NO},{@"00065",65,NO},{@"7",7,NO},{@"0",0,NO},
        {@"abc",-1,YES},{@"\uFF16\uFF15",65,NO},{@"1e2",-1,YES},{@"+5",-1,YES},{@"−5",-1,YES},{@"65.5",-1,YES},{@"65,5",-1,YES},{@"-",-1,YES},{@"+",-1,YES},{@".",-1,YES},{@"   ",-1,YES},
    };
    for(NSNumber *typing in @[@NO,@YES])for(NSUInteger i=0;i<sizeof(cases)/sizeof(cases[0]);i++){
        double before=slider.doubleValue;NSUInteger w=opacityWrites,r=opacityRejections;
        EnterOpacity(field,cases[i].text,typing.boolValue);
        if(typing.boolValue)[(NSTextView *)field.currentEditor insertNewline:nil];
        EndOpacity(field);
        if(cases[i].rejected){
            Check(opacityRejections>r && opacityWrites==w && slider.doubleValue==before,@"Opacity entry refuses letters, signs and decimals");
            Check([field.stringValue isEqual:[NSString stringWithFormat:@"%ld",lround(before)]],@"Refused opacity entry shows the stored value again");
        } else {
            BOOL changed=lround(cases[i].expected)!=lround(before);
            NSArray *rgba=[owner valueForKey:@"EditingColors"][key];
            Check(fabs(slider.doubleValue-cases[i].expected)<1e-9 && [field.stringValue isEqual:[NSString stringWithFormat:@"%ld",lround(cases[i].expected)]],@"Typed opacity moves the slider and saves once");
            Check(opacityWrites==w+(changed?1:0) && fabs([rgba[3]doubleValue]-cases[i].expected/100)<1e-9,@"Typed opacity moves the slider and saves once");
            Check(fabs([rgba[0]doubleValue]-[rgb[0]doubleValue])<1e-6 && fabs([rgba[1]doubleValue]-[rgb[1]doubleValue])<1e-6 && fabs([rgba[2]doubleValue]-[rgb[2]doubleValue])<1e-6,@"Opacity action preserves RGB and changes only alpha");
            if(cases[i].expected==100)Check(opacityWrites==w+(changed?1:0),@"Opacity entry above 100 is clamped to 100");
        }
    }
    double before=slider.doubleValue;NSUInteger w=opacityWrites,r=opacityRejections;
    TypeOpacity(field,@"");EndOpacity(field);
    Check(opacityRejections>r && opacityWrites==w && slider.doubleValue==before && [field.stringValue isEqual:[NSString stringWithFormat:@"%ld",lround(before)]],@"Empty opacity entry is refused and shows the stored value");
    w=opacityWrites;TypeOpacity(field,@"47");[(NSTextView *)field.currentEditor insertNewline:nil];EndOpacity(field);
    Check(opacityWrites==w+1 && fabs(StoredOpacity(owner,key)-0.47)<1e-9,@"Return followed by focus departure saves opacity exactly once");
    slider.doubleValue=30;[slider sendAction:slider.action to:slider.target];
    Check([field.stringValue isEqual:@"30"],@"Slider changes update the opacity field");
    NSStepper *stepper=(NSStepper *)Find(pane,[field.identifier stringByAppendingString:@".stepper"]);
    [pane layoutSubtreeIfNeeded];
    Check([stepper isKindOfClass:NSStepper.class] && stepper.superview==field.superview && NSMinX(stepper.frame)>=NSMaxX(field.frame) && [stepper.accessibilityLabel isEqual:field.accessibilityLabel] && stepper.enabled,@"Opacity has a stepper beside its field");
    void (^step)(NSInteger)=^(NSInteger direction){stepper.integerValue=1+direction;[stepper sendAction:stepper.action to:stepper.target];};
    w=opacityWrites;step(1);
    Check(opacityWrites==w+1 && fabs(StoredOpacity(owner,key)-0.31)<1e-9 && fabs(slider.doubleValue-31)<1e-9 && [field.stringValue isEqual:@"31"] && stepper.integerValue==1,@"Opacity stepper changes the value by one and saves once");
    step(-1);
    Check(opacityWrites==w+2 && fabs(StoredOpacity(owner,key)-0.30)<1e-9 && [field.stringValue isEqual:@"30"],@"Opacity stepper changes the value by one and saves once");
    slider.doubleValue=100;[slider sendAction:slider.action to:slider.target];w=opacityWrites;step(1);
    Check(opacityWrites==w && slider.doubleValue==100 && [field.stringValue isEqual:@"100"],@"Opacity stepper stops at 100");
    slider.doubleValue=0;[slider sendAction:slider.action to:slider.target];w=opacityWrites;step(-1);
    Check(opacityWrites==w && slider.doubleValue==0 && [field.stringValue isEqual:@"0"],@"Opacity stepper stops at 0");
    TypeOpacity(field,@"55");w=opacityWrites;step(1);
    Check(fabs(StoredOpacity(owner,key)-0.56)<1e-9 && fabs(slider.doubleValue-56)<1e-9 && field.currentEditor==nil,@"Opacity stepper continues from the number being typed");
    slider.doubleValue=30;[slider sendAction:slider.action to:slider.target];
    well.enabled=NO;Check(!field.enabled && !slider.enabled && !stepper.enabled,@"Disabled opacity disables its numeric field");
    w=opacityWrites;step(1);
    Check(opacityWrites==w && [field.stringValue isEqual:@"30"],@"Disabled opacity stepper changes nothing");
    w=opacityWrites;field.stringValue=@"80";[field sendAction:field.action to:field.target];
    Check(opacityWrites==w && [field.stringValue isEqual:@"30"],@"Disabled opacity disables its numeric field");well.enabled=YES;
    formatter.rejectionHandler=^{NSBeep();};
}
static NSTextField *ThemeRowField(TSSettingsThemeList *list,NSString *title){
    NSUInteger row=[list.titles indexOfObject:title];
    if(row==NSNotFound)return nil;
    NSTableCellView *cell=[list.tableView viewAtColumn:0 row:(NSInteger)row makeIfNecessary:YES];
    return cell.textField;
}
static NSArray<NSString *> *ThemeRowMarks(TSSettingsThemeList *list,NSString *title){
    NSUInteger row=[list.titles indexOfObject:title];
    NSTableCellView *cell=row==NSNotFound?nil:[list.tableView viewAtColumn:0 row:(NSInteger)row makeIfNecessary:YES];
    NSMutableArray *marks=[NSMutableArray array];
    for(NSView *child in cell.subviews)if([child isKindOfClass:NSStackView.class])for(NSView *mark in ((NSStackView *)child).arrangedSubviews)[marks addObject:mark.toolTip?:@""];
    return marks;
}
// Edit Theme is the list of themes with ＋, − and the actions menu under it: no pop-up menu of the theme to edit, no
// button to save the theme (colors are saved as they change) and none that makes a theme from earlier color settings.
static void CheckThemeActionButtons(TSPreferences *owner,TSSettingsWindowController *shell){
    [shell selectCategoryIdentifier:TSSettingsCategoryAppearance];
    NSView *pane=[shell viewForCategoryIdentifier:TSSettingsCategoryAppearance];[pane layoutSubtreeIfNeeded];
    NSView *row=Find(pane,@"row.catalog.appearance.1.0");
    TSSettingsThemeList *list=owner.themeList;
    Check(row!=nil && list!=nil && Find(row,@"settings.theme-list")==list.view,@"Edit Theme holds the theme list");
    Check(Find(pane,@"settings.O5R-pm-csa")==nil && Find(pane,@"settings.8bu-du-vzc")==nil && Find(pane,@"settings.save-theme")==nil,@"No pop-up menu of the theme to edit, no New Theme or Save Theme button");
    Check(Find(pane,@"settings.uXA-S0-9dP")==nil && ![owner respondsToSelector:NSSelectorFromString(@"NewStyleFromPrefs:")],@"No button makes a theme from earlier color settings");
    Check(Find(row,@"settings.theme-list.add")==list.addButton && Find(row,@"settings.theme-list.remove")==list.removeButton && Find(row,@"settings.theme-list.actions")==list.actionsButton,@"＋, − and the actions menu are under the list");
    // The independent reference catalog names the same actions as the list (Japanese, as the catalog).
    if([fixture.bundlePath.lastPathComponent isEqual:@"ja.bundle"]){
        NSDictionary *catalog=[NSJSONSerialization JSONObjectWithData:[NSData dataWithContentsOfURL:[fixture URLForResource:@"SettingsCatalogReference" withExtension:@"json"]] options:0 error:NULL];
        NSDictionary *edit=nil;for(NSDictionary *category in catalog[@"categories"])if([category[@"id"] isEqual:@"appearance"])for(NSDictionary *group in category[@"groups"])if([group[@"title"] isEqual:[fixture localizedStringForKey:@"group.appearance.1.title" value:nil table:@"SettingsCategories"]])edit=group;
        NSMutableArray *names=[NSMutableArray array];for(NSString *key in @[@"add",@"duplicate",@"rename",@"restore",@"delete",@"export",@"import"])[names addObject:[fixture localizedStringForKey:[@"theme.list." stringByAppendingString:key] value:nil table:@"SettingsCategories"]];
        Check([edit[@"rows"] count]==1 && [edit[@"rows"][0][@"kind"] isEqual:@"themelist"] && [edit[@"rows"][0][@"choices"] isEqual:names] && [edit[@"rows"][0][@"src"] isEqual:@[@"new:theme-list"]],[NSString stringWithFormat:@"The reference catalog has the list of themes with its actions: %@",edit[@"rows"]]);
    }
    NSString *addTip=[fixture localizedStringForKey:@"theme.list.add" value:nil table:@"SettingsCategories"];
    Check([list.addButton.toolTip isEqual:addTip] && ![addTip hasPrefix:@"theme."],[NSString stringWithFormat:@"＋ is named in the language of Settings: %@",list.addButton.toolTip]);
    NSRect frame=[list.view convertRect:list.view.bounds toView:row];
    Check(fabs(NSWidth(row.bounds)-NSMaxX(frame)-12)<0.5 && NSMinX(frame)>=11.5 && NSHeight(frame)>=8*24,[NSString stringWithFormat:@"The list takes the width of its row, inside the card, and shows eight themes: %@ in %@ ambiguous=%d/%d",NSStringFromRect(frame),NSStringFromRect(row.bounds),list.view.hasAmbiguousLayout,row.hasAmbiguousLayout]);
    // Themes that come with TeXShop (the bundled copies of the test) cannot be renamed or deleted.
    if(getenv("TS_TEST_BUNDLED_THEMES"))[list setValue:[NSURL fileURLWithPath:@(getenv("TS_TEST_BUNDLED_THEMES")) isDirectory:YES] forKey:@"bundledDirectory"];
    [TSIsolatedAppKitDefaults setObject:@"LiteTheme" forKey:DefaultLiteThemeKey];[TSIsolatedAppKitDefaults setObject:@"DarkTheme" forKey:DefaultDarkThemeKey];
    [owner themeListDidChooseTitle:@"LiteTheme"];[list reload];
    Check([list.titles containsObject:@"LiteTheme"] && [list.titles containsObject:@"DarkTheme"],[NSString stringWithFormat:@"The list shows the themes of the folder: %@",list.titles]);
    if(getenv("TS_TEST_BUNDLED_THEMES")){
        Check([list isBundledTitle:@"LiteTheme"] && !ThemeRowField(list,@"LiteTheme").editable && !list.removeButton.enabled,@"A theme that comes with TeXShop cannot be renamed or deleted");
        NSString *light=[fixture localizedStringForKey:@"catalog.appearance.0.0.title" value:nil table:@"SettingsCategories"],*dark=[fixture localizedStringForKey:@"catalog.appearance.0.1.title" value:nil table:@"SettingsCategories"];
        Check([ThemeRowMarks(list,@"LiteTheme") isEqual:@[light]] && [ThemeRowMarks(list,@"DarkTheme") isEqual:@[dark]],[NSString stringWithFormat:@"The themes of Light and Dark Mode are marked: %@ %@",ThemeRowMarks(list,@"LiteTheme"),ThemeRowMarks(list,@"DarkTheme")]);
    }
    Check(list.tableView.selectedRow==(NSInteger)[list.titles indexOfObject:@"LiteTheme"],@"The theme being edited is selected in the list");
    if(getenv("TS_TEST_BUNDLED_THEMES")){
        NSString *(^tr)(NSString *)=^NSString *(NSString *key){return [fixture localizedStringForKey:key value:nil table:@"SettingsCategories"];};
        TSThemeFileStore *store=[owner themeStore];NSArray *before=[store titles];
        // The actions menu names the selected theme; renaming and deleting a bundled theme are dimmed, as is restoring
        // one whose colors are TeXShop's.
        NSMenu *menu=list.actionsButton.menu;[(id<NSMenuDelegate>)list menuNeedsUpdate:menu];
        NSMutableDictionary<NSString *,NSMenuItem *> *items=[NSMutableDictionary dictionary];for(NSMenuItem *item in menu.itemArray)if(item.action)items[NSStringFromSelector(item.action)]=item;
        Check([items[@"duplicateTheme:"].title isEqual:[NSString stringWithFormat:tr(@"theme.list.duplicate.named"),@"LiteTheme"]] && items[@"importThemes:"]!=nil && items[@"exportTheme:"]!=nil && items[@"deleteTheme:"]==nil,@"The actions menu names the selected theme and has Import");
        Check(![(id<NSMenuItemValidation>)list validateMenuItem:items[@"renameTheme:"]] && ![(id<NSMenuItemValidation>)list validateMenuItem:items[@"restoreTheme:"]] && [(id<NSMenuItemValidation>)list validateMenuItem:items[@"duplicateTheme:"]],@"A bundled theme with TeXShop's colors cannot be renamed or restored");
        // ＋ makes a theme with TeXShop's colors, Duplicate a copy of the selected one.
        [owner themeListDidChooseTitle:@"LiteTheme"];[list reload];
        [list addTheme:nil];NSString *untitled=tr(@"theme.list.untitled");
        Check([[store titles] containsObject:untitled] && [[store readTitle:untitled][@"EditorText"] isEqual:owner.newThemeColors[@"EditorText"]] && ![list isBundledTitle:untitled],[NSString stringWithFormat:@"＋ adds “%@” with TeXShop's colors: %@",untitled,[store titles]]);
        Check([owner.editingThemeTitle isEqual:untitled],[NSString stringWithFormat:@"＋ edits the new theme: %@",owner.editingThemeTitle]);
        Check(list.removeButton.enabled && ThemeRowField(list,untitled).editable,@"A theme of the user's own can be renamed and deleted");
        [owner themeListDidChooseTitle:@"LiteTheme"];[list reload];[list duplicateTheme:nil];NSString *copy=[NSString stringWithFormat:tr(@"theme.list.copy"),@"LiteTheme"];
        Check([[store readTitle:copy][@"EditorText"] isEqual:[store readTitle:@"LiteTheme"][@"EditorText"]] && [[store readTitle:copy][@"Title"] isEqual:copy],[NSString stringWithFormat:@"Duplicate copies the selected theme as “%@”",copy]);
        // A bundled theme whose colors were changed is marked and can be restored.
        NSMutableDictionary *changed=[[store readTitle:@"LiteTheme"] mutableCopy];NSArray *text=changed[@"EditorText"];changed[@"EditorText"]=@[@0.9,@0.1,@0.1,@1];[store writeColors:changed title:@"LiteTheme" error:NULL];
        [owner themeListDidChooseTitle:@"LiteTheme"];[list reload];[(id<NSMenuDelegate>)list menuNeedsUpdate:menu];
        NSMenuItem *restore=nil;for(NSMenuItem *item in menu.itemArray)if(item.action==@selector(restoreTheme:))restore=item;
        Check([list isChangedTitle:@"LiteTheme"] && [(id<NSMenuItemValidation>)list validateMenuItem:restore] && [ThemeRowMarks(list,@"LiteTheme") containsObject:tr(@"theme.list.changed")],@"A changed bundled theme is marked and can be restored");
        // Saving a changed color of a bundled theme marks its row at once, and restoring clears the mark at once.
        [list restoreTheme:nil];
        Check(![list isChangedTitle:@"LiteTheme"] && [[store readTitle:@"LiteTheme"][@"EditorText"] isEqual:[NSDictionary dictionaryWithContentsOfFile:[@(getenv("TS_TEST_BUNDLED_THEMES")) stringByAppendingPathComponent:@"LiteTheme.plist"]][@"EditorText"]] && [[owner valueForKey:@"EditingColors"][@"EditorText"] isEqual:[store readTitle:@"LiteTheme"][@"EditorText"]],@"Restore gives the theme TeXShop's colors and the wells show them");
        (void)text;
        // The row is shown before the change, so that the check sees that row, not one made for it afterwards.
        [list.tableView scrollRowToVisible:(NSInteger)[list.titles indexOfObject:@"LiteTheme"]];[pane layoutSubtreeIfNeeded];(void)ThemeRowMarks(list,@"LiteTheme");
        NSMutableDictionary *editing=[owner valueForKey:@"EditingColors"];editing[@"EditorText"]=@[@0.2,@0.6,@0.2,@1];[owner SaveEditedStyle:nil];
        NSUInteger liteRow=[list.titles indexOfObject:@"LiteTheme"];NSTableCellView *shown=[list.tableView viewAtColumn:0 row:(NSInteger)liteRow makeIfNecessary:NO];
        NSMutableArray *shownMarks=[NSMutableArray array];for(NSView *child in shown.subviews)if([child isKindOfClass:NSStackView.class])for(NSView *mark in ((NSStackView *)child).arrangedSubviews)[shownMarks addObject:mark.toolTip?:@""];
        Check(shown!=nil && [shownMarks containsObject:tr(@"theme.list.changed")],[NSString stringWithFormat:@"The first change of a bundled theme's color marks the row shown without reading the list again: %@",shownMarks]);
        [list restoreTheme:nil];
        Check(![ThemeRowMarks(list,@"LiteTheme") containsObject:tr(@"theme.list.changed")],@"Restoring clears the mark at once");
        // A property list of other settings is not imported as a theme; one with some of the colors is.
        NSData *settingsOnly=[NSPropertyListSerialization dataWithPropertyList:@{@"WindowWidth":@800,@"ShowRuler":@YES,@"WindowFrame":@[@0,@0,@800,@600]} format:NSPropertyListXMLFormat_v1_0 options:0 error:NULL];
        NSData *someColors=[NSPropertyListSerialization dataWithPropertyList:@{@"EditorText":@[@0,@0,@0,@1],@"Title":@"Old"} format:NSPropertyListXMLFormat_v1_0 options:0 error:NULL];
        Check(![owner themeListAcceptsData:settingsOnly] && [owner themeListAcceptsData:someColors],@"Only a file with theme colors is imported");
        // Deleting a theme in use for Dark Mode gives Dark Mode TeXShop's DarkTheme (the file is removed here, not trashed).
        [TSIsolatedAppKitDefaults setObject:copy forKey:DefaultDarkThemeKey];[owner themeListDidChooseTitle:copy];[list reload];
        Check([ThemeRowMarks(list,copy) containsObject:tr(@"catalog.appearance.0.1.title")],[NSString stringWithFormat:@"The copy in use for Dark Mode is marked: %@ %@ %@",ThemeRowMarks(list,copy),owner.darkThemeTitle,list.titles]);
        Method trash=class_getInstanceMethod(TSThemeFileStore.class,@selector(trashTitle:error:));
        IMP original=method_setImplementation(trash,imp_implementationWithBlock(^BOOL(TSThemeFileStore *s,NSString *title,NSError **error){return [NSFileManager.defaultManager removeItemAtURL:(NSURL *_Nonnull)[s URLForTitle:title] error:error];}));
        ((void (*)(id,SEL,NSString *))objc_msgSend)(list,NSSelectorFromString(@"trashTitle:"),copy);
        method_setImplementation(trash,original);
        Check(![[store titles] containsObject:copy] && [[TSIsolatedAppKitDefaults objectForKey:DefaultDarkThemeKey] isEqual:@"DarkTheme"] && owner.editingThemeTitle!=nil && ![owner.editingThemeTitle isEqual:copy],@"Deleting the Dark Mode theme falls back to DarkTheme and edits the next theme");
        [NSFileManager.defaultManager removeItemAtURL:(NSURL *_Nonnull)[store URLForTitle:untitled] error:NULL];
        Check([[store titles] isEqual:before],@"The list's test leaves the theme folder as it was");
        [TSIsolatedAppKitDefaults setObject:@"DarkTheme" forKey:DefaultDarkThemeKey];[owner themeListDidChooseTitle:@"LiteTheme"];[list reload];
        // Reopened after the theme of Light Mode was deleted elsewhere: Light Mode gives way to LiteTheme, and the
        // theme edited is one that is there, selected in the list.
        [TSIsolatedAppKitDefaults setObject:@"Gone Elsewhere" forKey:DefaultLiteThemeKey];
        [owner PrepareColorPane:TSIsolatedAppKitDefaults];
        NSPopUpButton *liteMenu=[owner valueForKey:@"LiteStyle"];
        Check([[TSIsolatedAppKitDefaults objectForKey:DefaultLiteThemeKey] isEqual:@"LiteTheme"] && [liteMenu.titleOfSelectedItem isEqual:@"LiteTheme"],@"Reopened Settings gives a deleted Light Mode theme's place to LiteTheme");
        Check(owner.editingThemeTitle!=nil && [[store titles] containsObject:owner.editingThemeTitle] && list.tableView.selectedRow==(NSInteger)[list.titles indexOfObject:owner.editingThemeTitle] && [owner valueForKey:@"EditingColors"]!=nil,[NSString stringWithFormat:@"Reopened Settings edits a theme that is there: %@",owner.editingThemeTitle]);
        [owner themeListDidChooseTitle:@"LiteTheme"];[list reload];
        // A theme replaced by other settings (also with arrays that are not colors), or broken, before it is chosen is
        // not edited: another theme is, and the list says so in an alert that is caught here before it is shown.
        {
            __block NSMutableArray<NSString *> *notices=[NSMutableArray array];
            Method sheet=class_getInstanceMethod(NSAlert.class,@selector(beginSheetModalForWindow:completionHandler:));
            IMP shown=method_setImplementation(sheet,imp_implementationWithBlock(^(NSAlert *alert,NSWindow *window,id handler){[notices addObject:[NSString stringWithFormat:@"%@|%@",alert.messageText,alert.informativeText]];}));
            NSArray *bads=@[[NSPropertyListSerialization dataWithPropertyList:@{@"WindowFrame":@[@0,@0,@800,@600],@"ShowRuler":@YES} format:NSPropertyListXMLFormat_v1_0 options:0 error:NULL],
                            [NSPropertyListSerialization dataWithPropertyList:@{@"EditorText":@[@"red",@"green"],@"ShowRuler":@YES} format:NSPropertyListXMLFormat_v1_0 options:0 error:NULL],
                            [NSPropertyListSerialization dataWithPropertyList:@{@"EditorText":@[@0.5,@0.5]} format:NSPropertyListXMLFormat_v1_0 options:0 error:NULL],
                            [@"<?xml version=\"1.0\"?><plist><dict><key>EditorText" dataUsingEncoding:NSUTF8StringEncoding]];
            NSString *expected=[NSString stringWithFormat:@"%@|",[NSString stringWithFormat:tr(@"theme.list.notTheme"),@"Replaced"]];
            for(NSData *bad in bads){
                NSString *badPath=[ColorPath stringByAppendingPathComponent:@"Replaced.plist"];[bad writeToFile:badPath atomically:YES];[list reload];
                NSUInteger before=notices.count;
                [owner themeListDidChooseTitle:@"Replaced"];
                Check(owner.editingThemeTitle!=nil && ![owner.editingThemeTitle isEqual:@"Replaced"] && [owner valueForKey:@"EditingColors"]!=nil && [[NSData dataWithContentsOfFile:badPath] isEqual:bad],[NSString stringWithFormat:@"A theme that cannot be read as one is not edited: %@",owner.editingThemeTitle]);
                Check(notices.count==before+1 && [notices.lastObject isEqual:expected],[NSString stringWithFormat:@"The list says the theme cannot be read, not that something could not be saved: %@",notices.lastObject]);
                [NSFileManager.defaultManager removeItemAtPath:badPath error:NULL];
            }
            method_setImplementation(sheet,shown);
            Check(shell.window.attachedSheet==nil,@"No sheet is attached to the Settings window");
            for(NSWindow *window in NSApp.windows)Check(!window.visible,[NSString stringWithFormat:@"No window is shown: %@",window]);
            // Colors TeXShop can use: red, green and blue numbers, with or without alpha.
            BOOL (^accepts)(NSDictionary *)=[owner themeStore].acceptsColors;
            Check(accepts(@{@"EditorText":@[@0,@0,@0]}) && accepts(@{@"EditorText":@[@0,@0,@0,@1],@"ShowRuler":@YES}) && accepts(@{}) && accepts(@{@"Title":@"Old"}) && !accepts(@{@"EditorText":@[@0.5,@0.5]}) && !accepts(@{@"EditorText":@[@"red",@"green",@"blue"]}),@"A theme has at least one color TeXShop can use, or nothing but its title");
        }
        [owner themeListDidChooseTitle:@"LiteTheme"];[list reload];
        // The picture of the manual (TS_SETTINGS_MANUAL_SHOT, English): the themes that come with TeXShop, LiteTheme being
        // edited, 710 points wide in the light appearance.
        if(getenv("TS_SETTINGS_MANUAL_SHOT") && [fixture.bundlePath.lastPathComponent isEqual:@"Base.bundle"]){
            NSString *folder=@(getenv("TS_TEST_BUNDLED_THEMES"));NSMutableArray *added=[NSMutableArray array];
            for(NSString *file in [NSFileManager.defaultManager contentsOfDirectoryAtPath:folder error:NULL]){
                NSString *target=[ColorPath stringByAppendingPathComponent:file];
                if([file hasSuffix:@".plist"] && ![NSFileManager.defaultManager fileExistsAtPath:target] && [NSFileManager.defaultManager copyItemAtPath:[folder stringByAppendingPathComponent:file] toPath:target error:NULL])[added addObject:target];
            }
            NSString *fixtureTheme=[ColorPath stringByAppendingPathComponent:@"ProfileEffectFixture.plist"];NSData *hidden=[NSData dataWithContentsOfFile:fixtureTheme];
            if(hidden)[NSFileManager.defaultManager removeItemAtPath:fixtureTheme error:NULL];
            [owner themeListDidChooseTitle:@"LiteTheme"];[list reload];
            NSView *parent=pane.superview;NSArray *constraints=parent.constraints;
            [pane removeFromSuperview];NSWindow *window=[[NSWindow alloc]initWithContentRect:NSMakeRect(0,0,710,900) styleMask:NSWindowStyleMaskBorderless backing:NSBackingStoreBuffered defer:NO];
            window.appearance=[NSAppearance appearanceNamed:NSAppearanceNameAqua];
            NSView *host=window.contentView;[host addSubview:pane];pane.translatesAutoresizingMaskIntoConstraints=NO;
            NSArray *geometry=@[[pane.widthAnchor constraintEqualToConstant:710],[pane.leadingAnchor constraintEqualToAnchor:host.leadingAnchor],[pane.topAnchor constraintEqualToAnchor:host.topAnchor]];
            [NSLayoutConstraint activateConstraints:geometry];[host layoutSubtreeIfNeeded];[list.tableView scrollRowToVisible:0];
            Save(pane,@(getenv("TS_SETTINGS_MANUAL_SHOT")));
            [NSLayoutConstraint deactivateConstraints:geometry];[pane removeFromSuperview];[parent addSubview:pane];[NSLayoutConstraint activateConstraints:constraints];
            for(NSString *path in added)[NSFileManager.defaultManager removeItemAtPath:path error:NULL];
            if(hidden)[hidden writeToFile:fixtureTheme atomically:YES];
            [list reload];
        }
    }
    puts("PASS: Edit Theme list");
}
static void CheckOwnerOpacity(TSPreferences *owner,TSSettingsWindowController *shell,NSDictionary *base) {
    NSDictionary *defaults=[TSIsolatedAppKitDefaults.values copy],*editing=[owner valueForKey:@"EditingColors"],*last=[owner valueForKey:@"lastSavedEditingColors"];
    NSDictionary *savedLite=liteColors,*savedDark=darkColors;
    NSArray *keys=@[@"SourceAlpha",@"ConsoleAlpha",@"PreviewAlpha"];
    NSArray *outlets=@[@"SourceAlphaColorWell",@"ConsoleAlphaColorWell",@"PreviewAlphaColorWell"];
    [TSIsolatedAppKitDefaults setObject:@"LiteTheme" forKey:DefaultLiteThemeKey];
    [TSIsolatedAppKitDefaults setObject:@"DarkTheme" forKey:DefaultDarkThemeKey];
    [shell selectCategoryIdentifier:TSSettingsCategoryAppearance];
    NSMutableDictionary *theme=[base mutableCopy];
    for(NSUInteger i=0;i<3;i++)theme[keys[i]]=@[@0.12,@0.34,@0.56,@(0.1234+i*0.2)];
    theme[@"Title"]=@"OpacityFixture";
    NSString *path=[ColorPath stringByAppendingPathComponent:@"OpacityFixture.plist"];
    Check([theme writeToFile:path atomically:YES],@"Opacity uses a temporary theme file");
    [owner themeListDidChooseTitle:@"OpacityFixture"];
    Method write=class_getInstanceMethod(TSThemeFileStore.class,@selector(writeColors:title:error:));opacityOriginalWrite=method_setImplementation(write,(IMP)CountOpacityWrite);
    Method changes=class_getInstanceMethod(TSThemeFileStore.class,NSSelectorFromString(@"writeChangesFrom:to:title:error:"));
    if(changes)opacityOriginalChanges=method_setImplementation(changes,(IMP)CountOpacityChanges);
    Method key=class_getInstanceMethod(NSWindow.class,@selector(isKeyWindow));IMP oldKey=method_setImplementation(key,(IMP)NavigationKey);navigationTestWindow=shell.window;navigationTestKey=YES;
    __block NSUInteger notices=0;
    id observer=[NSNotificationCenter.defaultCenter addObserverForName:SourceColorChangedNotification object:owner queue:nil usingBlock:^(NSNotification *note){
        notices++;Check([[NSDictionary dictionaryWithContentsOfFile:path]isEqual:[owner valueForKey:@"EditingColors"]],@"Opacity is saved before notifying open windows");
    }];
    for(NSUInteger i=0;i<3;i++){
        NSColorWell *well=[owner valueForKey:outlets[i]];
        NSSlider *slider=(NSSlider *)Find([shell viewForCategoryIdentifier:TSSettingsCategoryAppearance],[@"opacity." stringByAppendingString:well.identifier]);
        Check(slider && slider.minValue==0 && slider.maxValue==100 && slider.controlSize==NSControlSizeSmall && !slider.continuous && well.hidden,@"Three small opacity sliders replace the hidden color wells");
        Check(fabs(slider.doubleValue-[theme[keys[i]][3]doubleValue]*100)<1e-6,@"Loading a theme preserves fractional opacity without rounding");
        for(NSNumber *percent in @[@0,@12.34,@37,@85,@100]){
            NSUInteger writes=opacityWrites,notifications=notices;
            slider.doubleValue=percent.doubleValue;[slider sendAction:slider.action to:slider.target];
            NSArray *rgba=[owner valueForKey:@"EditingColors"][keys[i]];
            Check(fabs([rgba[0]doubleValue]-0.12)<1e-6 && fabs([rgba[1]doubleValue]-0.34)<1e-6 && fabs([rgba[2]doubleValue]-0.56)<1e-6 && fabs([rgba[3]doubleValue]-percent.doubleValue/100)<1e-6,@"Opacity action preserves RGB and changes only alpha");
            Check(opacityWrites==writes+1 && notices==notifications+1,@"One opacity action performs one theme save and one refresh");
            [owner themeListDidChooseTitle:owner.editingThemeTitle];Check(fabs(slider.doubleValue-percent.doubleValue)<1e-6,@"Saved opacity reloads without drift");
        }
        well.enabled=NO;slider.doubleValue=42;NSUInteger writes=opacityWrites;[slider sendAction:slider.action to:slider.target];
        Check(!slider.enabled && slider.doubleValue==100 && opacityWrites==writes,@"Disabled opacity cannot write and restores its displayed value");well.enabled=YES;
    }
    for(NSUInteger i=0;i<3;i++)CheckOpacityField(owner,shell,[owner valueForKey:outlets[i]],theme[keys[i]],keys[i],path);
    Method localeMethod=class_getClassMethod(NSLocale.class,@selector(currentLocale));
    IMP oldLocale=method_setImplementation(localeMethod,(IMP)OpacityLocale);
    for(NSString *localeID in @[@"de_DE",@"fr_FR",@"en_US"]){
        opacityTestLocale=[[NSLocale alloc]initWithLocaleIdentifier:localeID];
        NSColorWell *well=[owner valueForKey:outlets[0]];well.color=[well.color colorWithAlphaComponent:0.85];
        NSSlider *slider=(NSSlider *)Find([shell viewForCategoryIdentifier:TSSettingsCategoryAppearance],[@"opacity." stringByAppendingString:well.identifier]);
        NSTextField *field=[slider.superview valueForKey:@"field"];
        NSNumberFormatter *formatter=[NSNumberFormatter new];formatter.numberStyle=NSNumberFormatterPercentStyle;formatter.maximumFractionDigits=0;formatter.locale=opacityTestLocale;
        Check([field.stringValue isEqual:@"85"],@"Opacity field shows the whole percentage in every region");
        Check([slider.accessibilityValue isEqual:[formatter stringFromNumber:@0.85]],@"Opacity percentage follows the current regional format");
        if(![localeID isEqual:@"en_US"])Check([slider.accessibilityValue rangeOfCharacterFromSet:NSCharacterSet.whitespaceCharacterSet].location!=NSNotFound,@"German and French percentages include their localized spacing");
        Check([@"100" sizeWithAttributes:@{NSFontAttributeName:field.font}].width+8<=NSWidth(field.frame),@"Localized percentages fit their label width");
        CheckOpacityField(owner,shell,well,theme[keys[0]],keys[0],path);
    }
    method_setImplementation(localeMethod,oldLocale);opacityTestLocale=nil;
    NSMutableDictionary *missing=[theme mutableCopy];for(NSString *key in keys)[missing removeObjectForKey:key];
    Check([missing writeToFile:path atomically:YES],@"Missing-alpha fixture is saved only in the temporary directory");
    BOOL loaded=YES;@try { [owner themeListDidChooseTitle:owner.editingThemeTitle]; } @catch(NSException *exception){loaded=NO;}
    Check(loaded,@"Absent alpha opens without exception and displays full opacity");
    for(NSUInteger i=0;i<3;i++){
        NSColorWell *well=[owner valueForKey:outlets[i]];
        NSSlider *slider=(NSSlider *)Find([shell viewForCategoryIdentifier:TSSettingsCategoryAppearance],[@"opacity." stringByAppendingString:well.identifier]);
        Check(slider.doubleValue==100,@"Absent alpha opens without exception and displays full opacity");
        NSUInteger writes=opacityWrites;slider.doubleValue=65;[slider sendAction:slider.action to:slider.target];
        NSArray *rgba=[NSDictionary dictionaryWithContentsOfFile:path][keys[i]];
        Check(rgba.count==4 && fabs([rgba[3]doubleValue]-0.65)<1e-9 && opacityWrites==writes+1,@"Absent alpha is created and saved once on edit");
        [owner themeListDidChooseTitle:owner.editingThemeTitle];Check(fabs(slider.doubleValue-65)<1e-9,@"Created alpha survives reload");
    }
    for(NSUInteger i=0;i<3;i++)for(id invalid in @[@"bad",@{},NSNull.null,@[@0],@[@0,@0,@0,@"0.5"],@[@0,@0,@0,NSNull.null],@[@0,@0,@0,@(-0.1)],@[@0,@0,@0,@1.1],@[@0,@0,@0,@(NAN)],@[@0,@0,@0,@(INFINITY)]]){
        NSMutableDictionary *bad=[theme mutableCopy];bad[keys[i]]=invalid;
        [owner setValue:bad forKey:@"EditingColors"];
        NSUInteger writes=opacityWrites;
        BOOL loaded=YES;@try{[owner FillInColorWells];}@catch(NSException *exception){loaded=NO;}
        Check(loaded,@"Invalid theme opacity loads safely and consistently");
        NSColorWell *well=[owner valueForKey:outlets[i]];
        NSSlider *slider=(NSSlider *)Find([shell viewForCategoryIdentifier:TSSettingsCategoryAppearance],[@"opacity." stringByAppendingString:well.identifier]);
        NSTextField *field=(NSTextField *)Find([shell viewForCategoryIdentifier:TSSettingsCategoryAppearance],[@"opacity-value." stringByAppendingString:well.identifier]);
        Check(well.color.alphaComponent==1 && slider.doubleValue==100 && field.integerValue==100 && opacityWrites==writes,@"Invalid theme opacity loads safely and consistently");
    }
    method_setImplementation(write,opacityOriginalWrite);if(changes)method_setImplementation(changes,opacityOriginalChanges);method_setImplementation(key,oldKey);navigationTestWindow=nil;
    [NSNotificationCenter.defaultCenter removeObserver:observer];
    [NSFileManager.defaultManager removeItemAtPath:path error:NULL];[owner setValue:nil forKey:@"editingThemeTitle"];
    TSIsolatedAppKitDefaults.values=[defaults mutableCopy];liteColors=savedLite;darkColors=savedDark;
    [owner setValue:editing forKey:@"EditingColors"];[owner setValue:last forKey:@"lastSavedEditingColors"];[owner FillInColorWells];
    puts("PASS: opacity sliders and numeric fields, exact RGB/alpha, one save/refresh, reload and disabled state");
}
