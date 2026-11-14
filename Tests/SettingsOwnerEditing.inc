// Regression sequences use the real owner and AppKit field editor. Only the
// alert presentation boundary is replaced, so no sheet can reach the screen.
@interface TSPreferences (EditingRegression)
- (BOOL)windowShouldClose:(NSWindow *)window;
- (BOOL)finishPreferenceEditing:(BOOL)showError;
- (void)refreshTypesettingSettingsFromDefaults:(NSUserDefaults *)defaults;
- (void)menuNeedsUpdate:(NSMenu *)menu;
- (void)refreshAlternateEngineFromDefaults:(NSUserDefaults *)defaults;
- (NSViewController *)alternateEngineInfoController;
@end
NSArray<NSArray<NSString *> *> *TSAlternateEnginePrograms(void);
NSArray<NSString *> *TSAlternateEngineInfoLines(NSMenu *mainMenu);
static NSUInteger ownerAlertCount;
static NSAlert *capturedOwnerAlert;
static void (^ownerAlertCompletion)(NSModalResponse);
static void CaptureOwnerAlert(NSAlert *alert, SEL selector, NSWindow *window, void (^completion)(NSModalResponse)) {
    ownerAlertCount++;capturedOwnerAlert=alert;
    Check(ownerAlertCompletion == nil, @"One outstanding validation warning");
    ownerAlertCompletion = [completion copy];
}
// The engine profile sheet is a window of its own: it is captured where Settings begins it.
static NSWindow *capturedOwnerSheet, *capturedOwnerSheetParent;
static void CaptureOwnerSheet(NSWindow *parent, SEL selector, NSWindow *sheet, void (^completion)(NSModalResponse)) {
    ownerAlertCount++;capturedOwnerSheet=sheet;capturedOwnerSheetParent=parent;
    Check(ownerAlertCompletion == nil, @"One outstanding sheet");
    ownerAlertCompletion = [completion copy];
}
static void FinishOwnerAlert(NSModalResponse response) {
    void (^completion)(NSModalResponse) = ownerAlertCompletion;
    ownerAlertCompletion = nil;
    Check(completion != nil, @"The actual validation path supplied a completion");
    completion(response);
}
static void EditOwnerField(TSPreferences *owner, NSTextField *field, NSString *text) {
    [field selectText:nil];
    NSText *editor = field.currentEditor;
    Check(editor != nil, @"Actual AppKit field editor is attached");
    editor.string = text;
    [owner controlTextDidChange:[NSNotification notificationWithName:NSControlTextDidChangeNotification object:field]];
}
static NSURL *ownerOpenedURL;
static BOOL OwnerOpenURL(id receiver, SEL selector, NSURL *url) { ownerOpenedURL=url; return YES; }
// Engine File lists the engine files of the Engines folder, as a document's toolbar does,
// and follows the folder while Settings is open.
// The Alternate Engine is chosen like the engine file, from the built-in programs and the engine
// files, and its info button tells where the command is and its key as the menu has it now.
static void CheckOwnerAlternateEngine(TSPreferences *owner, TSSettingsWindowController *shell) {
    NSFileManager *files=NSFileManager.defaultManager;
    NSString *savedEnginePath=EnginePath;
    NSString *engines=[NSTemporaryDirectory() stringByAppendingPathComponent:[NSString stringWithFormat:@"texshop-alternate-engines-%d",getpid()]];
    [files removeItemAtPath:engines error:NULL];[files createDirectoryAtPath:engines withIntermediateDirectories:YES attributes:nil error:NULL];
    for(NSString *file in @[@"pdflatexmk.engine",@"LuaLaTeX.engine"])[@"" writeToFile:[engines stringByAppendingPathComponent:file] atomically:YES encoding:NSUTF8StringEncoding error:NULL];
    EnginePath=engines;
    [TSIsolatedAppKitDefaults removeObjectForKey:AlternateEngineKey];
    [shell selectCategoryIdentifier:TSSettingsCategoryTypesetting];
    [owner refreshTypesettingSettingsFromDefaults:TSIsolatedAppKitDefaults];
    NSPopUpButton *alternate=[owner valueForKey:@"alternateEnginePopup"];
    NSArray *(^names)(void)=^NSArray *{NSMutableArray *list=[NSMutableArray array];for(NSMenuItem *item in alternate.itemArray)[list addObject:item.isSeparatorItem?@"-":item.representedObject];return list;};
    NSArray *programs=@[@"pdftex",@"pdflatex",@"tex",@"latex",@"personaltex",@"personallatex"];
    Check([names() isEqual:[programs arrayByAddingObjectsFromArray:@[@"-",@"LuaLaTeX",@"pdflatexmk"]]],@"Alternate Engine lists the built-in programs, plain TeX first, then the engine files");
    Check([[TSIsolatedAppKitDefaults stringForKey:AlternateEngineKey] isEqual:@"pdflatexmk"] && [alternate.selectedItem.representedObject isEqual:@"pdflatexmk"],@"The factory Alternate Engine is shown");
    NSArray *builtIn=TSAlternateEnginePrograms();
    BOOL titled=builtIn.count==programs.count;for(NSUInteger i=0;titled && i<programs.count;i++)titled=[builtIn[i][0] isEqual:programs[i]] && [[alternate itemAtIndex:(NSInteger)i].title isEqual:builtIn[i][1]] && [builtIn[i][1] hasPrefix:i%2==0?@"plain TeX":@"LaTeX"] && [builtIn[i][1] length]>9;
    Check(titled,@"Each built-in program is named with its method");
    [TSIsolatedAppKitDefaults setObject:@"PDFLaTeX" forKey:AlternateEngineKey];[owner refreshAlternateEngineFromDefaults:TSIsolatedAppKitDefaults];
    Check([alternate.selectedItem.representedObject isEqual:@"pdflatex"] && [alternate.itemArray.firstObject.representedObject isEqual:@"pdftex"],@"A built-in program is found in any case, as the typesetting does");
    [TSIsolatedAppKitDefaults setObject:@"luaLATEX" forKey:AlternateEngineKey];[owner refreshAlternateEngineFromDefaults:TSIsolatedAppKitDefaults];
    Check([alternate.selectedItem.representedObject isEqual:@"LuaLaTeX"],@"An engine file is found in any case");
    // As the typesetting does, a stored name is trimmed, and bibtex, makeindex and metapost are understood.
    [TSIsolatedAppKitDefaults setObject:@" PDFLaTeX \n" forKey:AlternateEngineKey];[owner refreshAlternateEngineFromDefaults:TSIsolatedAppKitDefaults];
    Check([alternate.selectedItem.representedObject isEqual:@"pdflatex"] && [[TSIsolatedAppKitDefaults stringForKey:AlternateEngineKey] isEqual:@" PDFLaTeX \n"],@"A built-in program with spaces around it is found, and the stored value stays");
    [TSIsolatedAppKitDefaults setObject:@" luaLaTeX\t" forKey:AlternateEngineKey];[owner refreshAlternateEngineFromDefaults:TSIsolatedAppKitDefaults];
    Check([alternate.selectedItem.representedObject isEqual:@"LuaLaTeX"],@"An engine file with spaces around it is found");
    for(NSString *old in @[@"bibtex",@" MakeIndex ",@"metapost"]){
        [TSIsolatedAppKitDefaults setObject:old forKey:AlternateEngineKey];[owner refreshAlternateEngineFromDefaults:TSIsolatedAppKitDefaults];
        NSString *shown=[old stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        Check(alternate.indexOfSelectedItem==0 && [alternate.titleOfSelectedItem isEqual:shown] && [alternate.selectedItem.representedObject isEqual:old] && [alternate itemAtIndex:1].isSeparatorItem,[NSString stringWithFormat:@"%@, which the typesetting understands, is shown as itself",shown]);
    }
    [TSIsolatedAppKitDefaults setObject:@"Gone" forKey:AlternateEngineKey];[owner refreshAlternateEngineFromDefaults:TSIsolatedAppKitDefaults];
    NSString *missing=[NSString stringWithFormat:NSLocalizedString(@"%@ (Not Found)",nil),@"Gone"];
    Check([alternate.titleOfSelectedItem isEqual:missing] && alternate.indexOfSelectedItem==0 && [alternate itemAtIndex:1].isSeparatorItem,@"An Alternate Engine that is nowhere stays shown as not found");
    [TSIsolatedAppKitDefaults setObject:@"" forKey:AlternateEngineKey];[owner refreshAlternateEngineFromDefaults:TSIsolatedAppKitDefaults];
    Check([alternate.titleOfSelectedItem isEqual:NSLocalizedString(@"None",nil)] && alternate.indexOfSelectedItem==0,@"An empty Alternate Engine is shown as None");
    [alternate selectItemAtIndex:[names() indexOfObject:@"latex"]];[alternate sendAction:alternate.action to:alternate.target];
    Check([[TSIsolatedAppKitDefaults stringForKey:AlternateEngineKey] isEqual:@"latex"] && alternate.numberOfItems==9,@"Choosing a built-in program stores the name the typesetting understands");
    [@"" writeToFile:[engines stringByAppendingPathComponent:@"Added.engine"] atomically:YES encoding:NSUTF8StringEncoding error:NULL];
    [owner menuNeedsUpdate:alternate.menu];
    [alternate selectItemAtIndex:[names() indexOfObject:@"Added"]];[alternate sendAction:alternate.action to:alternate.target];
    Check([[TSIsolatedAppKitDefaults stringForKey:AlternateEngineKey] isEqual:@"Added"],@"The Alternate Engine menu follows the folder and stores an engine file by its name");
    NSButton *edit=[owner valueForKey:@"editAlternateEnginesButton"];
    Check(edit.enabled && [edit.identifier isEqual:@"settings.alternate-engine-edit"] && edit.action==@selector(openEnginesFolder:) && edit.superview==alternate.superview && [edit.title isEqual:[[NSBundle mainBundle] localizedStringForKey:@"catalog.typesetting.0.1.button" value:nil table:@"SettingsCategories"]],@"Edit Engine List is beside the Alternate Engine too");
    NSButton *info=[owner valueForKey:@"alternateEngineInfoButton"];
    NSView *row=info.superview;while(row && ![row.identifier hasPrefix:@"row."])row=row.superview;
    NSTextField *name=(NSTextField *)Find(row,@"label.catalog-row");
    [shell.window.contentView layoutSubtreeIfNeeded];
    NSRect infoFrame=[row convertRect:info.bounds fromView:info],nameFrame=[row convertRect:name.bounds fromView:name];
    CGFloat textEnd=NSMinX(nameFrame)+[name.attributedStringValue size].width;
    Check([row.identifier isEqual:@"row.catalog.typesetting.0.3"] && info.action==@selector(showAlternateEngineInfo:) && info.accessibilityLabel.length>0 && NSMinX(infoFrame)>=textEnd && NSMinX(infoFrame)<textEnd+16 && NSMidY(infoFrame)>NSMinY(nameFrame) && NSMidY(infoFrame)<NSMaxY(nameFrame) && NSMaxX(infoFrame)<NSMinX([row convertRect:alternate.bounds fromView:alternate]),@"The info button follows the name of the Alternate Engine");
    // The info names the menu, the item it replaces, the modifiers and the key as the menu has them now.
    NSMenu *main=[NSMenu new],*typeset=[[NSMenu alloc] initWithTitle:@"Typeset"];
    [main addItemWithTitle:@"Typeset" action:NULL keyEquivalent:@""].submenu=typeset;
    NSMenuItem *base=[typeset addItemWithTitle:@"Typeset" action:@selector(doTypeset:) keyEquivalent:@"t"];base.keyEquivalentModifierMask=NSEventModifierFlagCommand;
    NSMenuItem *trash=[typeset addItemWithTitle:@"Trash Aux & Typeset" action:@selector(doTypeset:) keyEquivalent:@"t"];trash.keyEquivalentModifierMask=NSEventModifierFlagCommand|NSEventModifierFlagOption;trash.alternate=YES;
    NSMenuItem *item=[typeset addItemWithTitle:@"Typeset with Alternate Engine" action:@selector(doAlternateTypeset:) keyEquivalent:@"t"];item.keyEquivalentModifierMask=NSEventModifierFlagCommand|NSEventModifierFlagOption|NSEventModifierFlagControl;item.alternate=YES;
    NSArray *lines=TSAlternateEngineInfoLines(main);
    NSString *where=[NSString stringWithFormat:NSLocalizedString(@"In the %1$@ menu, this item appears in place of %2$@ while you hold %3$@.",nil),@"Typeset",@"Typeset",@"⌃⌥"];
    NSString *key=[NSString stringWithFormat:NSLocalizedString(@"Key: %@",nil),@"⌃⌥⌘T"];
    Check(lines.count==5 && [lines[0] isEqual:@"Typeset with Alternate Engine"] && [lines[1] isEqual:where] && [lines[2] isEqual:key] && [lines[4] containsString:@"% !TEX TS-program"] && ![[lines componentsJoinedByString:@" "] containsString:@"pdflatexmk"],@"The info tells where the item is, its key and what it does");
    item.alternate=NO;item.keyEquivalent=@"y";item.keyEquivalentModifierMask=NSEventModifierFlagCommand|NSEventModifierFlagShift;
    lines=TSAlternateEngineInfoLines(main);
    Check([lines[1] isEqual:[NSString stringWithFormat:NSLocalizedString(@"This item is in the %@ menu.",nil),@"Typeset"]] && [lines[2] isEqual:[NSString stringWithFormat:NSLocalizedString(@"Key: %@",nil),@"⇧⌘Y"]],@"A changed shortcut is told as the menu has it");
    item.keyEquivalent=@"";lines=TSAlternateEngineInfoLines(main);
    Check([lines[2] isEqual:NSLocalizedString(@"No key is assigned.",nil)],@"An item without a key says so");
    Check(TSAlternateEngineInfoLines(nil).count==3,@"Without the menu item the info still says what the engine does");
    NSStackView *content=(NSStackView *)[owner alternateEngineInfoController].view;
    Check([content isKindOfClass:NSStackView.class] && content.arrangedSubviews.count==TSAlternateEngineInfoLines(NSApp.mainMenu).count,@"The popover shows each line of the info");
    [TSIsolatedAppKitDefaults removeObjectForKey:AlternateEngineKey];[owner refreshAlternateEngineFromDefaults:TSIsolatedAppKitDefaults];
    [files removeItemAtPath:engines error:NULL];
    EnginePath=savedEnginePath;
}
static void CheckOwnerEngineFile(TSPreferences *owner, TSSettingsWindowController *shell) {
    NSFileManager *files=NSFileManager.defaultManager;
    NSString *savedEnginePath=EnginePath;
    NSString *engines=[NSTemporaryDirectory() stringByAppendingPathComponent:[NSString stringWithFormat:@"texshop-engine-files-%d",getpid()]];
    [files removeItemAtPath:engines error:NULL];
    [files createDirectoryAtPath:[engines stringByAppendingPathComponent:@"Folder.engine"] withIntermediateDirectories:YES attributes:nil error:NULL];
    for(NSString *file in @[@"XeLaTeX.engine",@"lualatex.ENGINE",@"pdflatexmk.engine",@"notes.txt"])
        [@"" writeToFile:[engines stringByAppendingPathComponent:file] atomically:YES encoding:NSUTF8StringEncoding error:NULL];
    EnginePath=engines;
    [TSIsolatedAppKitDefaults removeObjectForKey:DefaultEngineKey];
    [TSIsolatedAppKitDefaults setInteger:1 forKey:DefaultCommandKey];
    [shell selectCategoryIdentifier:TSSettingsCategoryTypesetting];
    [owner refreshTypesettingSettingsFromDefaults:TSIsolatedAppKitDefaults];
    NSPopUpButton *engineFile=[owner valueForKey:@"defaultEnginePopup"];
    NSArray *(^titles)(void)=^NSArray *{NSMutableArray *list=[NSMutableArray array];for(NSMenuItem *item in engineFile.itemArray)[list addObject:item.isSeparatorItem?@"-":item.title];return list;};
    Check([titles() isEqual:@[@"lualatex",@"pdflatexmk",@"XeLaTeX"]],@"Engine File lists the engine files of the folder in the toolbar's order");
    Check([[TSIsolatedAppKitDefaults stringForKey:DefaultEngineKey] isEqual:@"LuaLaTeX"] && [engineFile.titleOfSelectedItem isEqual:@"lualatex"],@"The factory engine file is LuaLaTeX, found in any case");
    Check(!engineFile.enabled,@"Engine File is dimmed unless the engine file is chosen above");
    NSButton *edit=[owner valueForKey:@"editEnginesButton"];
    Check(edit.enabled && [edit.identifier isEqual:@"settings.default-engine-edit"] && edit.action==@selector(openEnginesFolder:) && edit.superview==engineFile.superview,@"Edit Engine List stays available beside Engine File");
    NSMatrix *command=[owner valueForKey:@"defaultCommandMatrix"];
    Check([[command.cells valueForKey:@"tag"] isEqual:@[@0,@1,@2]] && [[command.cells.firstObject title] isEqual:@"plain TeX"],@"plain TeX comes first, then LaTeX, then the engine file");
    // The menu shows the choices in that order and keeps each stored value with its choice.
    NSPopUpButton *choice=(NSPopUpButton *)Find([shell viewForCategoryIdentifier:TSSettingsCategoryTypesetting],@"choice.settings.181");
    NSArray *choiceTitles=[command.cells valueForKey:@"title"];
    Check([choice isKindOfClass:NSPopUpButton.class] && [[choice.itemArray valueForKey:@"title"] isEqual:choiceTitles] && [[choice.itemArray valueForKey:@"tag"] isEqual:@[@0,@1,@2]],@"The menu lists plain TeX, LaTeX and the engine file with their stored values");
    [TSIsolatedAppKitDefaults removeObjectForKey:DefaultCommandKey];
    [owner refreshTypesettingSettingsFromDefaults:TSIsolatedAppKitDefaults];
    Check([TSIsolatedAppKitDefaults integerForKey:DefaultCommandKey]==1 && choice.selectedTag==1 && [choice.titleOfSelectedItem isEqual:choiceTitles[1]],@"New documents are typeset with LaTeX by default");
    for(NSInteger stored=0;stored<3;stored++){
        [TSIsolatedAppKitDefaults setInteger:stored forKey:DefaultCommandKey];
        [owner refreshTypesettingSettingsFromDefaults:TSIsolatedAppKitDefaults];
        Check(choice.selectedTag==stored && [choice.titleOfSelectedItem isEqual:choiceTitles[(NSUInteger)stored]] && command.selectedCell.tag==stored,[NSString stringWithFormat:@"A stored %ld shows its own choice",(long)stored]);
    }
    for(NSInteger index=2;index>=0;index--){
        [choice selectItemAtIndex:index];[choice sendAction:choice.action to:choice.target];
        Check([TSIsolatedAppKitDefaults integerForKey:DefaultCommandKey]==[choice itemAtIndex:index].tag,[NSString stringWithFormat:@"Choosing %@ stores its value",[choice itemAtIndex:index].title]);
    }
    [TSIsolatedAppKitDefaults setInteger:1 forKey:DefaultCommandKey];
    [owner refreshTypesettingSettingsFromDefaults:TSIsolatedAppKitDefaults];
    [command selectCellWithTag:2];[owner defaultProgramChanged:command];
    Check(engineFile.enabled && [TSIsolatedAppKitDefaults integerForKey:DefaultCommandKey]==2,@"Choosing the engine file enables Engine File");
    Check([[TSIsolatedAppKitDefaults objectForKey:DefaultEngineKey] isEqual:@"lualatex"],@"Choosing the engine file stores the engine file shown");
    [engineFile selectItemWithTitle:@"XeLaTeX"];[owner defaultEngineChosen:engineFile];
    Check([[TSIsolatedAppKitDefaults stringForKey:DefaultEngineKey] isEqual:@"XeLaTeX"],@"Choosing in Engine File stores the file name");
    [files removeItemAtPath:[engines stringByAppendingPathComponent:@"XeLaTeX.engine"] error:NULL];
    [@"" writeToFile:[engines stringByAppendingPathComponent:@"Added.engine"] atomically:YES encoding:NSUTF8StringEncoding error:NULL];
    [owner menuNeedsUpdate:engineFile.menu];
    NSString *missing=[NSString stringWithFormat:NSLocalizedString(@"%@ (Not Found)",nil),@"XeLaTeX"];
    Check([titles() isEqual:@[missing,@"-",@"Added",@"lualatex",@"pdflatexmk"]] && [engineFile.titleOfSelectedItem isEqual:missing],@"The list follows the folder, and a missing engine file stays shown");
    Check([[TSIsolatedAppKitDefaults stringForKey:DefaultEngineKey] isEqual:@"XeLaTeX"],@"Refreshing the list does not change the setting");
    [engineFile selectItemWithTitle:@"Added"];[owner defaultEngineChosen:engineFile];
    Check([[TSIsolatedAppKitDefaults stringForKey:DefaultEngineKey] isEqual:@"Added"] && [titles() isEqual:@[@"Added",@"lualatex",@"pdflatexmk"]],@"Choosing another engine file drops the missing one");
    Method open=class_getInstanceMethod(NSWorkspace.class,@selector(openURL:));
    IMP original=method_setImplementation(open,(IMP)OwnerOpenURL);
    [files removeItemAtPath:engines error:NULL];ownerOpenedURL=nil;
    [owner openEnginesFolder:edit];
    method_setImplementation(open,original);
    BOOL isFolder=NO;
    Check([ownerOpenedURL.path isEqual:engines] && [files fileExistsAtPath:engines isDirectory:&isFolder] && isFolder,@"Edit Engine List opens the Engines folder, made again if it was removed");
    [command selectCellWithTag:1];[owner defaultProgramChanged:command];
    Check(!engineFile.enabled && [[TSIsolatedAppKitDefaults stringForKey:DefaultEngineKey] isEqual:@"Added"],@"Going back to LaTeX dims Engine File and keeps its choice");
    [files removeItemAtPath:engines error:NULL];
    EnginePath=savedEnginePath;
}
static void CheckOwnerEditing(TSPreferences *owner, TSSettingsWindowController *shell) {
    Method alertMethod = class_getInstanceMethod(NSAlert.class, @selector(beginSheetModalForWindow:completionHandler:));
    IMP originalAlert = method_setImplementation(alertMethod, (IMP)CaptureOwnerAlert);
    Method sheetMethod = class_getInstanceMethod(NSWindow.class, @selector(beginSheet:completionHandler:));
    IMP originalSheet = method_setImplementation(sheetMethod, (IMP)CaptureOwnerSheet);
    NSArray *contract=[NSJSONSerialization JSONObjectWithData:[NSData dataWithContentsOfURL:[fixture URLForResource:@"SettingsInputRules" withExtension:@"json"]] options:0 error:NULL];
    NSMapTable *rules=[owner valueForKey:@"inputRules"];
    Check(contract.count==19 && rules.count==contract.count,@"All nineteen independent input rules are installed");
    for(NSDictionary *entry in contract){
        NSTextField *field=[owner valueForKey:entry[@"outlet"]];TSPreferenceInput *rule=[rules objectForKey:field];
        Check(rule && [rule.key isEqual:entry[@"key"]] && rule.kind==[entry[@"kind"]integerValue] && rule.minimum==[entry[@"minimum"]doubleValue] && rule.maximum==[entry[@"maximum"]doubleValue] && rule.allowsEmpty==[entry[@"allowsEmpty"]boolValue] && rule.restoresDefaultWhenEmpty==[entry[@"restoresDefault"]boolValue],[NSString stringWithFormat:@"Independent rule contract for %@",entry[@"outlet"]]);
        Check((entry[@"notification"]==NSNull.null && rule.notification==nil) || [rule.notification isEqual:entry[@"notification"]], [NSString stringWithFormat:@"Input notification contract for %@",entry[@"outlet"]]);
        if(rule.kind==TSPreferenceInputInteger){
            NSNumberFormatter *formatter=(NSNumberFormatter *)field.formatter;
            Check(field.delegate==owner && [formatter isKindOfClass:TSIntegerInputFormatter.class] && formatter.minimum.doubleValue==rule.minimum && formatter.maximum.doubleValue==rule.maximum,[NSString stringWithFormat:@"%@ keeps typing to digits and carries its range",entry[@"outlet"]]);
        }else Check(field.delegate==owner && field.formatter==nil,@"Original formatters cannot bypass the unified input validator");
    }
    NSDictionary *saved = [TSIsolatedAppKitDefaults.values copy];
    [shell beginSession];
    [shell selectCategoryIdentifier:TSSettingsCategoryEditor];
    NSTextField *tabs = [owner valueForKey:@"tabIndentField"];
    NSTextField *gs = [owner valueForKey:@"gsBinPathField"];
    [TSIsolatedAppKitDefaults setObject:@"" forKey:GSBinPath];
    __block NSUInteger tabNotifications=0;
    id tabObserver=[NSNotificationCenter.defaultCenter addObserverForName:DocumentFontChangedNotification object:owner queue:nil usingBlock:^(NSNotification *n){tabNotifications++;Check([TSIsolatedAppKitDefaults integerForKey:tabsKey]==20,@"Tab width is stored before notifying documents");}];
    EditOwnerField(owner, tabs, @"20");
    Check([shell selectCategoryIdentifier:TSSettingsCategoryTypesetting], @"Navigation commits tab width through the field editor");
    Check([TSIsolatedAppKitDefaults integerForKey:tabsKey] == 20 && tabNotifications==1, @"Tab width commits and notifies documents once");
    [NSNotificationCenter.defaultCenter removeObserver:tabObserver];
    [gs selectText:nil];
    Check(gs.currentEditor != nil && [gs.currentEditor.string isEqual:@""], @"Focus enters the untouched empty GS field");
    NSDictionary *beforeFocus = [TSIsolatedAppKitDefaults dictionaryRepresentation];
    NSUInteger alerts = ownerAlertCount;
    Check([shell selectCategoryIdentifier:TSSettingsCategoryGeneral], @"Untouched GS focus permits navigation");
    NSMutableDictionary *actual = [[TSIsolatedAppKitDefaults dictionaryRepresentation] mutableCopy];
    NSMutableDictionary *expected = [beforeFocus mutableCopy];
    [actual removeObjectForKey:TSSettingsSelectedCategoryKey]; [expected removeObjectForKey:TSSettingsSelectedCategoryKey];
    Check(ownerAlertCount == alerts && [actual isEqual:expected], @"Untouched focus causes no warning or value write");
    [shell selectCategoryIdentifier:TSSettingsCategoryTypesetting];
    EditOwnerField(owner, gs, @"");
    Check(![shell selectCategoryIdentifier:TSSettingsCategoryGeneral], @"Edited empty GS blocks navigation");
    Check(ownerAlertCount == alerts + 1, @"Invalid edit presents exactly one warning");
    Check(![shell selectCategoryIdentifier:TSSettingsCategoryGeneral] && ownerAlertCount == alerts + 1, @"Repeated navigation does not stack warnings");
    FinishOwnerAlert(NSAlertSecondButtonReturn);
    Check([gs.stringValue isEqual:@""] && [gs.currentEditor.string isEqual:@""], @"Restore uses this field's empty value, never the prior tab width");
    Check([shell selectCategoryIdentifier:TSSettingsCategoryGeneral], @"Navigation succeeds after restoring the field");
    [shell selectCategoryIdentifier:TSSettingsCategoryEditor];
    EditOwnerField(owner, tabs, @"99");
    Check([owner windowShouldClose:shell.window], @"Closing validates the current field");
    Check([TSIsolatedAppKitDefaults integerForKey:tabsKey] == 50 && [tabs.stringValue isEqual:@"50"], @"Close clamps 99 to 50");
    EditOwnerField(owner, tabs, @"invalid");
    alerts = ownerAlertCount;
    Check(![owner windowShouldClose:shell.window] && ownerAlertCount == alerts + 1, @"Invalid text prevents close and warns once");
    FinishOwnerAlert(NSAlertFirstButtonReturn);
    Check(tabs.currentEditor != nil && [tabs.currentEditor.string isEqual:@"invalid"], @"Continue Editing preserves the invalid input");
    Check(![owner windowShouldClose:shell.window], @"Continue Editing does not make invalid input valid");
    FinishOwnerAlert(NSAlertSecondButtonReturn);
    Check([owner windowShouldClose:shell.window], @"Restored input permits close");
    [shell selectCategoryIdentifier:TSSettingsCategoryEditor];
    EditOwnerField(owner,tabs,@"nonsense");
    // Choosing a profile in the menu asks at once, through the menu's own action; there is no Apply button.
    NSPopUpButton *profileChoice=[owner valueForKey:@"engineProfilePopup"];
    Check(profileChoice.target==owner && profileChoice.action==@selector(applyEngineProfile:),@"The profile menu asks when a profile is chosen");
    void (^chooseProfile)(TSEngineProfile)=^(TSEngineProfile profile){[profileChoice selectItemWithTag:profile];[profileChoice sendAction:profileChoice.action to:profileChoice.target];};
    alerts=ownerAlertCount;chooseProfile(TSEngineProfileUpLaTeXDvipdfmx);
    Check(ownerAlertCount==alerts+1 && [[owner valueForKey:@"inputErrorPresented"]boolValue],@"Profile selection validates an edit before showing its confirmation");
    FinishOwnerAlert(NSAlertSecondButtonReturn);
    TSEngineProfile shownBefore=TSEngineProfileMatchingSettings(TSIsolatedAppKitDefaults,NULL);
    Check(profileChoice.selectedTag==shownBefore && shownBefore!=TSEngineProfileUpLaTeXDvipdfmx,@"An edit that cannot be committed puts the menu back");
    // A setting in use that already has the profile's value, though the factory one does not: its row is not marked.
    NSString *metaPostBefore=[TSIsolatedAppKitDefaults.values[MetaPostEngineKey] copy];
    [TSIsolatedAppKitDefaults setObject:@" upmpost" forKey:MetaPostEngineKey];
    EditOwnerField(owner,tabs,@"22");alerts=ownerAlertCount;chooseProfile(TSEngineProfileUpLaTeXDvipdfmx);
    Check([TSIsolatedAppKitDefaults integerForKey:tabsKey]==22 && ownerAlertCount==alerts+1 && ![[owner valueForKey:@"inputErrorPresented"]boolValue],@"Valid edit commits before profile confirmation");
    // The sheet is a window of its own on the Settings window, with the list, the latexmk choice, OK and Cancel.
    NSView *(^sheetView)(NSString *)=^NSView *(NSString *identifier){return Find(capturedOwnerSheet.contentView,identifier);};
    NSButton *(^sheetOK)(void)=^NSButton *{return (NSButton *)sheetView(@"settings.engine-profile-ok");};
    NSSegmentedControl *(^sheetLatexmk)(void)=^NSSegmentedControl *{return (NSSegmentedControl *)sheetView(@"settings.engine-profile-latexmk");};
    void (^chooseLatexmk)(NSInteger)=^(NSInteger segment){NSSegmentedControl *c=sheetLatexmk();c.selectedSegment=segment;[c sendAction:c.action to:c.target];};
    Check(capturedOwnerSheetParent==shell.window && [[(NSTextField *)sheetView(@"settings.engine-profile-question") stringValue] containsString:@"upLaTeX + dvipdfmx"],@"Profile confirmation is a sheet on Settings that names the profile");
    Check([sheetOK().keyEquivalent isEqual:@"\r"] && capturedOwnerSheet.defaultButtonCell==sheetOK().cell && [[(NSButton *)sheetView(@"settings.engine-profile-cancel") keyEquivalent] isEqual:@"\e"],@"Profile confirmation applies on Return and reserves Escape for Cancel");
    NSSegmentedControl *latexmk=sheetLatexmk();
    Check([latexmk isKindOfClass:NSSegmentedControl.class] && latexmk.enabled && latexmk.selectedSegment==(TSEngineProfileSettingsUseLatexmk(TSIsolatedAppKitDefaults)?1:0),@"The latexmk choice starts from the commands in use");
    Check(profileChoice.selectedTag==TSEngineProfileUpLaTeXDvipdfmx,@"While the sheet asks, the menu shows the profile chosen");
    // The sheet lists what the profile sets, compared with the settings in use, and follows latexmk at once.
    NSView *profileList=sheetView(@"settings.engine-profile-list");
    NSGridView *(^listRows)(void)=^NSGridView *{return (NSGridView *)Find(profileList,@"settings.engine-profile-list.rows");};
    NSString *(^listValue)(NSInteger)=^NSString *(NSInteger row){return [[(NSTextField *)[listRows() cellAtColumnIndex:3 rowIndex:row].contentView stringValue] stringByReplacingOccurrencesOfString:@"\u2060" withString:@""];};
    BOOL (^listMarked)(NSInteger)=^BOOL(NSInteger row){return [[listRows() cellAtColumnIndex:2 rowIndex:row].contentView.identifier isEqual:@"settings.engine-profile-list.changes"] && [[listRows() cellAtColumnIndex:0 rowIndex:row].contentView isKindOfClass:NSButton.class];};
    NSDictionary *upValues=TSEngineProfileValues(TSEngineProfileUpLaTeXDvipdfmx,latexmk.selectedSegment==1);
    Check(profileList!=nil && latexmk.target==profileList && listRows().numberOfRows==10,@"The sheet lists the ten settings a Japanese profile sets, and latexmk belongs to the list");
    Check([listValue(2) isEqual:upValues[LatexGSCommandKey]] && [listValue(5) isEqual:@"upmpost"] && !listMarked(5) && listMarked(4)==![[TSIsolatedAppKitDefaults stringForKey:MakeIndexEngineKey] isEqual:@"upmendex"],
          @"The list shows the profile's values and marks those that differ from the settings in use, not from the factory settings");
    NSInteger firstForm=latexmk.selectedSegment;
    chooseLatexmk(1-firstForm);
    Check([listValue(2) isEqual:TSEngineProfileValues(TSEngineProfileUpLaTeXDvipdfmx,firstForm==0)[LatexGSCommandKey]] && ![listValue(2) isEqual:upValues[LatexGSCommandKey]],@"Choosing latexmk the other way replaces the LaTeX command in the list at once");
    chooseLatexmk(firstForm);
    Check([listValue(2) isEqual:upValues[LatexGSCommandKey]],@"Choosing latexmk back shows the first command again");
    if(metaPostBefore)[TSIsolatedAppKitDefaults setObject:metaPostBefore forKey:MetaPostEngineKey];else [TSIsolatedAppKitDefaults removeObjectForKey:MetaPostEngineKey];
    NSString *commandBefore=[TSIsolatedAppKitDefaults stringForKey:LatexGSCommandKey];
    NSDictionary *valuesBefore=[TSIsolatedAppKitDefaults.values copy];
    FinishOwnerAlert(NSModalResponseCancel);
    Check([TSIsolatedAppKitDefaults integerForKey:tabsKey]==22 && [[TSIsolatedAppKitDefaults stringForKey:LatexGSCommandKey] isEqual:commandBefore],@"Cancelling the profile preserves the committed edit");
    Check([TSIsolatedAppKitDefaults.values isEqual:valuesBefore],@"Cancel changes no setting");
    Check(profileChoice.selectedTag==shownBefore && [profileChoice.titleOfSelectedItem isEqual:(shownBefore==TSEngineProfileNone?NSLocalizedString(@"Custom",@""):TSEngineProfileTitle(shownBefore))],[NSString stringWithFormat:@"Cancel shows the earlier choice again: %@",profileChoice.titleOfSelectedItem]);
    // Applying a confirmed profile ends the field editor; a later focus change
    // cannot write its prior text over the profile's value.
    [shell selectCategoryIdentifier:TSSettingsCategoryTypesetting];
    NSTextField *latexGS=[owner valueForKey:@"latexGSCommandTextField"];
    NSString *texPath=[TSIsolatedAppKitDefaults stringForKey:TetexBinPath],*gsPath=[TSIsolatedAppKitDefaults stringForKey:GSBinPath];
    EditOwnerField(owner,latexGS,@"typed-command");alerts=ownerAlertCount;chooseProfile(TSEngineProfileUpLaTeXDvipdfmx);
    Check(ownerAlertCount==alerts+1,@"The profile sheet comes after the commit");
    // While the sheet waits, the change notices of the commit, and of an owned setting changed elsewhere, leave the
    // chosen profile in the menu.
    for(int i=0;i<5;i++)[NSRunLoop.mainRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
    Check(profileChoice.selectedTag==TSEngineProfileUpLaTeXDvipdfmx,[NSString stringWithFormat:@"While the sheet waits, the menu keeps the profile chosen after the commit: %@",profileChoice.titleOfSelectedItem]);
    NSString *indexBefore=[TSIsolatedAppKitDefaults stringForKey:MakeIndexEngineKey];
    [TSIsolatedAppKitDefaults setObject:@"elsewhere" forKey:MakeIndexEngineKey];
    for(int i=0;i<5;i++)[NSRunLoop.mainRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
    Check(profileChoice.selectedTag==TSEngineProfileUpLaTeXDvipdfmx,@"While the sheet waits, a setting changed elsewhere leaves the profile chosen in the menu");
    if(indexBefore)[TSIsolatedAppKitDefaults setObject:indexBefore forKey:MakeIndexEngineKey];else [TSIsolatedAppKitDefaults removeObjectForKey:MakeIndexEngineKey];
    // Chosen as the user chooses it, so that the list follows.
    chooseLatexmk(1);
    FinishOwnerAlert(NSModalResponseOK);
    NSString *profileCommand=TSEngineProfileValues(TSEngineProfileUpLaTeXDvipdfmx,YES)[LatexGSCommandKey];
    Check([[TSIsolatedAppKitDefaults stringForKey:LatexGSCommandKey] isEqual:profileCommand] && latexGS.currentEditor==nil && [latexGS.stringValue isEqual:profileCommand],@"Profile application releases the pre-application editor");
    Check([[TSIsolatedAppKitDefaults stringForKey:TetexBinPath] ?: @"" isEqual:texPath ?: @""] && [[TSIsolatedAppKitDefaults stringForKey:GSBinPath] ?: @"" isEqual:gsPath ?: @""],@"Applying a profile leaves the paths to Detect Paths");
    Check(profileChoice.selectedTag==TSEngineProfileUpLaTeXDvipdfmx && [TSIsolatedAppKitDefaults integerForKey:tabsKey]==22,@"The applied profile is shown and other settings stay");
    [shell selectCategoryIdentifier:TSSettingsCategoryGeneral];
    Check([[TSIsolatedAppKitDefaults stringForKey:LatexGSCommandKey] isEqual:profileCommand],@"Later navigation cannot restore the pre-profile text");
    // A value turned off in the list keeps the setting in use; the others are written, and the menu shows Custom at once.
    alerts=ownerAlertCount;chooseProfile(TSEngineProfilePLaTeXDvipdfmx);
    Check(ownerAlertCount==alerts+1,@"Choosing pLaTeX + dvipdfmx asks");
    NSGridView *pRows=(NSGridView *)Find(sheetView(@"settings.engine-profile-list"),@"settings.engine-profile-list.rows");
    NSButton *indexBox=(NSButton *)[pRows cellAtColumnIndex:0 rowIndex:4].contentView;
    Check([indexBox isKindOfClass:NSButton.class] && indexBox.state==NSControlStateValueOn && [indexBox.accessibilityLabel length]>0,@"The index command, which changes, has its checkbox, on, named for VoiceOver");
    [indexBox performClick:nil];
    Check(sheetOK().enabled,@"OK stays available while some value is set");
    FinishOwnerAlert(NSModalResponseOK);
    Check([[TSIsolatedAppKitDefaults stringForKey:MakeIndexEngineKey] isEqual:@"upmendex"] && [[TSIsolatedAppKitDefaults stringForKey:BibTeXengineKey] isEqual:@"pbibtex"] && [TSIsolatedAppKitDefaults boolForKey:ptexUtfOutputEnabledKey],
          @"OK writes the values that are on and keeps the one turned off");
    Check(profileChoice.selectedTag==TSEngineProfileNone && [profileChoice.titleOfSelectedItem isEqual:NSLocalizedString(@"Custom",@"")],[NSString stringWithFormat:@"With a value turned off, the menu shows Custom at once: %@",profileChoice.titleOfSelectedItem]);
    // With every value that changes turned off, OK cannot be chosen; one turned on again brings it back.
    alerts=ownerAlertCount;chooseProfile(TSEngineProfileUpLaTeXDvipdfmx);
    NSGridView *uRows=(NSGridView *)Find(sheetView(@"settings.engine-profile-list"),@"settings.engine-profile-list.rows");
    NSButton *lastBox=nil;
    for(NSInteger r=0;r<uRows.numberOfRows;r++){NSView *box=[uRows cellAtColumnIndex:0 rowIndex:r].contentView;if([box isKindOfClass:NSButton.class]){lastBox=(NSButton *)box;[lastBox performClick:nil];}}
    Check(lastBox!=nil && !sheetOK().enabled,@"OK cannot be chosen with every value turned off");
    [lastBox performClick:nil];
    Check(sheetOK().enabled,@"OK comes back when a value is turned on again");
    FinishOwnerAlert(NSModalResponseCancel);
    // Back to upLaTeX + dvipdfmx with latexmk, in full.
    alerts=ownerAlertCount;chooseProfile(TSEngineProfileUpLaTeXDvipdfmx);
    chooseLatexmk(1);
    FinishOwnerAlert(NSModalResponseOK);
    Check(profileChoice.selectedTag==TSEngineProfileUpLaTeXDvipdfmx && [[TSIsolatedAppKitDefaults stringForKey:LatexGSCommandKey] isEqual:profileCommand],@"Applying in full shows the profile again");
    // With a value turned off, the menu shows Custom even when the settings left happen to be those of another profile:
    // LuaLaTeX (Japanese), then a MetaPost command of one's own, then LuaLaTeX keeping the BibTeX engine and the index
    // program leaves exactly the settings of LuaLaTeX (Japanese).
    void (^spin)(void)=^{for(int i=0;i<5;i++)[NSRunLoop.mainRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];};
    chooseProfile(TSEngineProfileLuaLaTeXJapanese);chooseLatexmk(0);FinishOwnerAlert(NSModalResponseOK);spin();
    [TSIsolatedAppKitDefaults setObject:@"custom-metapost" forKey:MetaPostEngineKey];spin();
    chooseProfile(TSEngineProfileLuaLaTeX);chooseLatexmk(0);
    NSGridView *lRows=(NSGridView *)Find(sheetView(@"settings.engine-profile-list"),@"settings.engine-profile-list.rows");
    for(NSInteger r=3;r<5;r++){NSButton *box=(NSButton *)[lRows cellAtColumnIndex:0 rowIndex:r].contentView;Check([box isKindOfClass:NSButton.class],@"The BibTeX engine and the index program change, each with its checkbox");[box performClick:nil];}
    FinishOwnerAlert(NSModalResponseOK);
    Check([[TSIsolatedAppKitDefaults stringForKey:MetaPostEngineKey] isEqual:@"mpost"] && [[TSIsolatedAppKitDefaults stringForKey:MakeIndexEngineKey] isEqual:@"upmendex"] && TSEngineProfileMatchingSettings(TSIsolatedAppKitDefaults,NULL)==TSEngineProfileLuaLaTeXJapanese,
          @"The settings left are those of LuaLaTeX (Japanese)");
    Check(profileChoice.selectedTag==TSEngineProfileNone && [profileChoice.titleOfSelectedItem isEqual:NSLocalizedString(@"Custom",@"")],[NSString stringWithFormat:@"With a value turned off, the menu shows Custom, not another profile: %@",profileChoice.titleOfSelectedItem]);
    spin();
    Check(profileChoice.selectedTag==TSEngineProfileNone,@"The change notices of the profile leave Custom in the menu");
    [TSIsolatedAppKitDefaults setObject:@"other" forKey:MetaPostEngineKey];spin();
    [TSIsolatedAppKitDefaults setObject:@"mpost" forKey:MetaPostEngineKey];spin();
    Check(profileChoice.selectedTag==TSEngineProfileLuaLaTeXJapanese,[NSString stringWithFormat:@"Once a setting changes again, the menu follows the settings: %@",profileChoice.titleOfSelectedItem]);
    chooseProfile(TSEngineProfileUpLaTeXDvipdfmx);chooseLatexmk(1);FinishOwnerAlert(NSModalResponseOK);
    Check(profileChoice.selectedTag==TSEngineProfileUpLaTeXDvipdfmx,@"Applying in full shows the profile again");
    CheckOwnerEngineFile(owner,shell);
    CheckOwnerAlternateEngine(owner,shell);
    // Whole-number fields: digits only while typing, and a stepper beside each.
    [shell selectCategoryIdentifier:TSSettingsCategoryEditor];
    [shell.window.contentView layoutSubtreeIfNeeded];
    NSView *editorPane=[shell viewForCategoryIdentifier:TSSettingsCategoryEditor];
    for(NSString *outlet in @[@"tabIndentField",@"firstParagraphIndentField",@"remainingParagraphIndentField",@"interlineSpacingField"]){
        NSTextField *field=[owner valueForKey:outlet];
        NSStepper *stepper=(NSStepper *)Find(editorPane,[field.identifier stringByAppendingString:@".stepper"]);
        Check([stepper isKindOfClass:NSStepper.class] && stepper.superview==field.superview && !stepper.hiddenOrHasHiddenAncestor && NSWidth(stepper.frame)>0 && NSMinX(stepper.frame)>=NSMaxX(field.frame) && [stepper.accessibilityLabel isEqual:field.accessibilityLabel],[NSString stringWithFormat:@"%@ has a stepper right beside it",outlet]);
    }
    for(NSString *outlet in @[@"magTextField",@"gsBinPathField"]){
        NSTextField *field=[owner valueForKey:outlet];
        Check(Find(field.superview,[field.identifier stringByAppendingString:@".stepper"])==nil,[NSString stringWithFormat:@"%@ has no stepper",outlet]);
    }
    NSFormatter *digits=tabs.formatter;NSString *partial=@"12";NSRange selection=NSMakeRange(2,0);
    Check([digits isPartialStringValid:&partial proposedSelectedRange:&selection originalString:@"1" originalSelectedRange:NSMakeRange(1,0) errorDescription:NULL] && [partial isEqual:@"12"],@"Digits can be typed");
    partial=@"";Check([digits isPartialStringValid:&partial proposedSelectedRange:&selection originalString:@"1" originalSelectedRange:NSMakeRange(1,0) errorDescription:NULL],@"The field can be emptied while typing");
    for(NSString *bad in @[@"1.5",@"1,5",@"-1",@"+1",@"a",@"1 ",@"\u0661"]){
        partial=bad;
        Check(![digits isPartialStringValid:&partial proposedSelectedRange:&selection originalString:@"1" originalSelectedRange:NSMakeRange(1,0) errorDescription:NULL] && [partial isEqual:bad],[NSString stringWithFormat:@"Typing %@ is refused without changing the entry",bad]);
    }
    partial=@"\uFF11\uFF12";
    Check(![digits isPartialStringValid:&partial proposedSelectedRange:&selection originalString:@"" originalSelectedRange:NSMakeRange(0,0) errorDescription:NULL] && [partial isEqual:@"12"] && selection.location==2,@"Full-width digits become ASCII digits");
    id object=nil;
    Check([digits getObjectValue:&object forString:@"bad" errorDescription:NULL] && [object isEqual:@"bad"],@"Text at the end of editing is left to the common validator");
    NSStepper *tabStepper=(NSStepper *)Find(editorPane,[tabs.identifier stringByAppendingString:@".stepper"]);
    __block NSUInteger stepNotes=0;
    id stepObserver=[NSNotificationCenter.defaultCenter addObserverForName:DocumentFontChangedNotification object:owner queue:nil usingBlock:^(NSNotification *n){stepNotes++;}];
    void (^step)(NSInteger)=^(NSInteger direction){tabStepper.integerValue=1+direction;[tabStepper sendAction:tabStepper.action to:tabStepper.target];};
    [TSIsolatedAppKitDefaults setInteger:10 forKey:tabsKey];[owner updateControlsFromUserDefaults:TSIsolatedAppKitDefaults];
    step(1);
    Check([TSIsolatedAppKitDefaults integerForKey:tabsKey]==11 && [tabs.stringValue isEqual:@"11"] && stepNotes==1 && tabStepper.integerValue==1,@"Stepper up stores one more, shows it and notifies documents once");
    step(-1);
    Check([TSIsolatedAppKitDefaults integerForKey:tabsKey]==10 && [tabs.stringValue isEqual:@"10"] && stepNotes==2,@"Stepper down stores one less");
    [TSIsolatedAppKitDefaults setInteger:50 forKey:tabsKey];[owner updateControlsFromUserDefaults:TSIsolatedAppKitDefaults];stepNotes=0;
    step(1);
    Check([TSIsolatedAppKitDefaults integerForKey:tabsKey]==50 && stepNotes==0,@"Stepper stops at the maximum");
    [TSIsolatedAppKitDefaults setInteger:2 forKey:tabsKey];[owner updateControlsFromUserDefaults:TSIsolatedAppKitDefaults];
    step(-1);
    Check([TSIsolatedAppKitDefaults integerForKey:tabsKey]==2 && stepNotes==0,@"Stepper stops at the minimum");
    EditOwnerField(owner,tabs,@"7");step(1);
    Check([TSIsolatedAppKitDefaults integerForKey:tabsKey]==8 && [tabs.stringValue isEqual:@"8"] && tabs.currentEditor==nil,@"Stepper continues from the number being typed");
    EditOwnerField(owner,tabs,@"bad");alerts=ownerAlertCount;step(1);
    Check(ownerAlertCount==alerts+1 && [TSIsolatedAppKitDefaults integerForKey:tabsKey]==8,@"Stepper keeps the warning for an invalid entry");
    FinishOwnerAlert(NSAlertSecondButtonReturn);
    [shell.window makeFirstResponder:nil];
    [NSNotificationCenter.defaultCenter removeObserver:stepObserver];
    // Stored values outside the ranges are shown as the source windows apply them.
    NSTextField *spacing=[owner valueForKey:@"interlineSpacingField"];
    [TSIsolatedAppKitDefaults setDouble:45 forKey:SourceInterlineSpaceKey];
    [TSIsolatedAppKitDefaults setDouble:150 forKey:SourceHeadIndentKey];
    [TSIsolatedAppKitDefaults setDouble:2.7 forKey:SourceFirstLineHeadIndentKey];
    [TSIsolatedAppKitDefaults setInteger:0 forKey:tabsKey];
    [owner updateControlsFromUserDefaults:TSIsolatedAppKitDefaults];
    Check([spacing.stringValue isEqual:@"20"] && [[[owner valueForKey:@"remainingParagraphIndentField"] stringValue] isEqual:@"100"] && [[[owner valueForKey:@"firstParagraphIndentField"] stringValue] isEqual:@"2"] && [tabs.stringValue isEqual:@"2"],@"Out-of-range stored values are shown inside the ranges");
    Check([TSIsolatedAppKitDefaults doubleForKey:SourceInterlineSpaceKey]==45 && [TSIsolatedAppKitDefaults doubleForKey:SourceFirstLineHeadIndentKey]==2.7,@"Showing a stored value does not rewrite it");
    EditOwnerField(owner,spacing,@"");alerts=ownerAlertCount;
    Check(![owner windowShouldClose:shell.window] && ownerAlertCount==alerts+1,@"An empty interline spacing warns");
    FinishOwnerAlert(NSAlertSecondButtonReturn);
    Check([spacing.stringValue isEqual:@"20"] && [TSIsolatedAppKitDefaults doubleForKey:SourceInterlineSpaceKey]==45,@"Restoring an entry shows the stored value inside the range");
    [shell.window makeFirstResponder:nil];
    Check(TSStoredIntegerInRange(TSIsolatedAppKitDefaults,SourceInterlineSpaceKey,TSInterlineSpaceRange)==20 && TSStoredIntegerInRange(TSIsolatedAppKitDefaults,SourceFirstLineHeadIndentKey,TSParagraphIndentRange)==2 && TSIntegerInRange(45,TSInterlineSpaceRange)==20 && TSIntegerInRange(0,TSInterlineSpaceRange)==1 && TSIntegerInRange(-3,TSParagraphIndentRange)==0 && TSIntegerInRange(1,TSTabWidthRange)==2 && TSIntegerInRange(NAN,TSTabWidthRange)==2,@"Source windows use the same ranges as the fields");
    TSPreferenceInput *spacingRule=[rules objectForKey:[owner valueForKey:@"interlineSpacingField"]];
    Check(spacingRule.minimum==TSInterlineSpaceRange.minimum && spacingRule.maximum==TSInterlineSpaceRange.maximum,@"The interline field takes its range from the shared ranges");
    // kpsewhich and the HTML home page: emptying the field restores the default, which the empty field shows as its
    // placeholder; the default typed out is not stored either.
    for(NSArray *entry in @[@[@"kpsetoolField",KpsetoolKey,TSSettingsCategoryTypesetting],@[@"HtmlHomeField",HtmlHomeKey,TSSettingsCategoryPreview]]){
        NSTextField *field=[owner valueForKey:entry[0]];NSString *key=entry[1],*factoryValue=TSIsolatedAppKitDefaults.fallbacks[key];
        BOOL (^unset)(void)=^BOOL{return TSIsolatedAppKitDefaults.values[key]==nil && [TSIsolatedAppKitDefaults persistentDomainForName:[TSIsolatedAppKitDefaults applicationDomainName]][key]==nil;};
        [shell selectCategoryIdentifier:entry[2]];
        [TSIsolatedAppKitDefaults setObject:@"custom value" forKey:key];[owner updateControlsFromUserDefaults:TSIsolatedAppKitDefaults];
        Check(factoryValue.length>0 && [field.placeholderString isEqual:factoryValue] && [field.stringValue isEqual:@"custom value"],[NSString stringWithFormat:@"%@ shows the value set, with the default as its placeholder",key]);
        EditOwnerField(owner,field,@"  ");alerts=ownerAlertCount;[shell.window makeFirstResponder:nil];
        Check(ownerAlertCount==alerts && unset() && [[TSIsolatedAppKitDefaults stringForKey:key] isEqual:factoryValue] && field.stringValue.length==0 && field.currentEditor==nil,[NSString stringWithFormat:@"Emptying %@ restores its default without a warning and leaves the field empty",key]);
        [owner updateControlsFromUserDefaults:TSIsolatedAppKitDefaults];
        Check(field.stringValue.length==0 && [field.placeholderString isEqual:factoryValue],[NSString stringWithFormat:@"%@ stays empty, with its placeholder, when shown again",key]);
        EditOwnerField(owner,field,@"another value");[shell.window makeFirstResponder:nil];
        Check([TSIsolatedAppKitDefaults.values[key] isEqual:@"another value"] && [field.stringValue isEqual:@"another value"],[NSString stringWithFormat:@"%@ stores a value typed",key]);
        EditOwnerField(owner,field,factoryValue);[shell.window makeFirstResponder:nil];
        Check(unset() && field.stringValue.length==0,[NSString stringWithFormat:@"%@ does not store its default typed out",key]);
        for(NSString *stored in @[factoryValue,@""]){
            [TSIsolatedAppKitDefaults setObject:stored forKey:key];[owner updateControlsFromUserDefaults:TSIsolatedAppKitDefaults];
            Check(field.stringValue.length==0,[NSString stringWithFormat:@"%@ stored as %@ shows the empty field and its placeholder",key,stored]);
        }
        [TSIsolatedAppKitDefaults removeObjectForKey:key];
    }
    TSIsolatedAppKitDefaults.values = [saved mutableCopy];
    [owner updateControlsFromUserDefaults:TSIsolatedAppKitDefaults];
    [shell beginSession];
    method_setImplementation(alertMethod, originalAlert);
    method_setImplementation(sheetMethod, originalSheet);
    puts("PASS: owner field-editor navigation, restore, validation and close");
}
