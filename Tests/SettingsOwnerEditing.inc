// Regression sequences use the real owner and AppKit field editor. Only the
// alert presentation boundary is replaced, so no sheet can reach the screen.
@interface TSPreferences (EditingRegression)
- (BOOL)windowShouldClose:(NSWindow *)window;
- (BOOL)finishPreferenceEditing:(BOOL)showError;
- (void)refreshTypesettingSettingsFromDefaults:(NSUserDefaults *)defaults;
- (void)menuNeedsUpdate:(NSMenu *)menu;
@end
static NSUInteger ownerAlertCount;
static NSAlert *capturedOwnerAlert;
static void (^ownerAlertCompletion)(NSModalResponse);
static void CaptureOwnerAlert(NSAlert *alert, SEL selector, NSWindow *window, void (^completion)(NSModalResponse)) {
    ownerAlertCount++;capturedOwnerAlert=alert;
    Check(ownerAlertCompletion == nil, @"One outstanding validation warning");
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
    Check([[command.cells valueForKey:@"tag"] isEqual:@[@1,@0,@2]] && [[command.cells.firstObject title] length]>0,@"LaTeX comes first, then plain TeX, then the engine file");
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
    NSArray *contract=[NSJSONSerialization JSONObjectWithData:[NSData dataWithContentsOfURL:[fixture URLForResource:@"SettingsInputRules" withExtension:@"json"]] options:0 error:NULL];
    NSMapTable *rules=[owner valueForKey:@"inputRules"];
    Check(contract.count==20 && rules.count==contract.count,@"All twenty independent input rules are installed");
    for(NSDictionary *entry in contract){
        NSTextField *field=[owner valueForKey:entry[@"outlet"]];TSPreferenceInput *rule=[rules objectForKey:field];
        Check(rule && [rule.key isEqual:entry[@"key"]] && rule.kind==[entry[@"kind"]integerValue] && rule.minimum==[entry[@"minimum"]doubleValue] && rule.maximum==[entry[@"maximum"]doubleValue] && rule.allowsEmpty==[entry[@"allowsEmpty"]boolValue],[NSString stringWithFormat:@"Independent rule contract for %@",entry[@"outlet"]]);
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
    EditOwnerField(owner,tabs,@"22");alerts=ownerAlertCount;chooseProfile(TSEngineProfileUpLaTeXDvipdfmx);
    Check([TSIsolatedAppKitDefaults integerForKey:tabsKey]==22 && ownerAlertCount==alerts+1 && ![[owner valueForKey:@"inputErrorPresented"]boolValue],@"Valid edit commits before profile confirmation");
    Check([capturedOwnerAlert.messageText containsString:@"upLaTeX + dvipdfmx"] && capturedOwnerAlert.informativeText.length==0,@"Profile confirmation names the profile and shows no paths");
    Check([capturedOwnerAlert.buttons.firstObject.keyEquivalent isEqual:@"\r"] && [capturedOwnerAlert.buttons.lastObject.keyEquivalent isEqual:@"\e"],@"Profile confirmation applies on Return and reserves Escape for Cancel");
    NSButton *(^sheetLatexmk)(void)=^NSButton *{return (NSButton *)Find(capturedOwnerAlert.accessoryView,@"settings.engine-profile-latexmk");};
    NSButton *latexmk=sheetLatexmk();
    Check([latexmk isKindOfClass:NSButton.class] && latexmk.enabled && latexmk.state==(TSEngineProfileSettingsUseLatexmk(TSIsolatedAppKitDefaults)?NSControlStateValueOn:NSControlStateValueOff),@"The latexmk choice starts from the commands in use");
    Check(profileChoice.selectedTag==TSEngineProfileUpLaTeXDvipdfmx,@"While the sheet asks, the menu shows the profile chosen");
    NSString *commandBefore=[TSIsolatedAppKitDefaults stringForKey:LatexGSCommandKey];
    NSDictionary *valuesBefore=[TSIsolatedAppKitDefaults.values copy];
    FinishOwnerAlert(NSAlertSecondButtonReturn);
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
    sheetLatexmk().state=NSControlStateValueOn;
    FinishOwnerAlert(NSAlertFirstButtonReturn);
    NSString *profileCommand=TSEngineProfileValues(TSEngineProfileUpLaTeXDvipdfmx,YES)[LatexGSCommandKey];
    Check([[TSIsolatedAppKitDefaults stringForKey:LatexGSCommandKey] isEqual:profileCommand] && latexGS.currentEditor==nil && [latexGS.stringValue isEqual:profileCommand],@"Profile application releases the pre-application editor");
    Check([[TSIsolatedAppKitDefaults stringForKey:TetexBinPath] ?: @"" isEqual:texPath ?: @""] && [[TSIsolatedAppKitDefaults stringForKey:GSBinPath] ?: @"" isEqual:gsPath ?: @""],@"Applying a profile leaves the paths to Detect Paths");
    Check(profileChoice.selectedTag==TSEngineProfileUpLaTeXDvipdfmx && [TSIsolatedAppKitDefaults integerForKey:tabsKey]==22,@"The applied profile is shown and other settings stay");
    [shell selectCategoryIdentifier:TSSettingsCategoryGeneral];
    Check([[TSIsolatedAppKitDefaults stringForKey:LatexGSCommandKey] isEqual:profileCommand],@"Later navigation cannot restore the pre-profile text");
    CheckOwnerEngineFile(owner,shell);
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
    TSIsolatedAppKitDefaults.values = [saved mutableCopy];
    [owner updateControlsFromUserDefaults:TSIsolatedAppKitDefaults];
    [shell beginSession];
    method_setImplementation(alertMethod, originalAlert);
    puts("PASS: owner field-editor navigation, restore, validation and close");
}
