// Regression sequences use the real owner and AppKit field editor. Only the
// alert presentation boundary is replaced, so no sheet can reach the screen.
@interface TSPreferences (EditingRegression)
- (BOOL)windowShouldClose:(NSWindow *)window;
- (BOOL)finishPreferenceEditing:(BOOL)showError;
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
static void CheckOwnerEditing(TSPreferences *owner, TSSettingsWindowController *shell) {
    Method alertMethod = class_getInstanceMethod(NSAlert.class, @selector(beginSheetModalForWindow:completionHandler:));
    IMP originalAlert = method_setImplementation(alertMethod, (IMP)CaptureOwnerAlert);
    NSArray *contract=[NSJSONSerialization JSONObjectWithData:[NSData dataWithContentsOfURL:[fixture URLForResource:@"SettingsInputRules" withExtension:@"json"]] options:0 error:NULL];
    NSMapTable *rules=[owner valueForKey:@"inputRules"];
    Check(contract.count==19 && rules.count==contract.count,@"All nineteen independent input rules are installed");
    for(NSDictionary *entry in contract){
        NSTextField *field=[owner valueForKey:entry[@"outlet"]];TSPreferenceInput *rule=[rules objectForKey:field];
        Check(rule && [rule.key isEqual:entry[@"key"]] && rule.kind==[entry[@"kind"]integerValue] && rule.minimum==[entry[@"minimum"]doubleValue] && rule.maximum==[entry[@"maximum"]doubleValue] && rule.allowsEmpty==[entry[@"allowsEmpty"]boolValue],[NSString stringWithFormat:@"Independent rule contract for %@",entry[@"outlet"]]);
        Check((entry[@"notification"]==NSNull.null && rule.notification==nil) || [rule.notification isEqual:entry[@"notification"]], [NSString stringWithFormat:@"Input notification contract for %@",entry[@"outlet"]]);
        Check(field.delegate==owner && field.formatter==nil,@"Original formatters cannot bypass the unified input validator");
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
    NSMenuItem *profileChoice=[[NSMenuItem alloc]initWithTitle:@"Factory" action:NULL keyEquivalent:@""];profileChoice.tag=1;
    alerts=ownerAlertCount;[owner setDefaults:profileChoice];
    Check(ownerAlertCount==alerts+1 && [[owner valueForKey:@"inputErrorPresented"]boolValue],@"Profile selection validates an edit before showing its confirmation");
    FinishOwnerAlert(NSAlertSecondButtonReturn);
    EditOwnerField(owner,tabs,@"22");alerts=ownerAlertCount;[owner setDefaults:profileChoice];
    Check([TSIsolatedAppKitDefaults integerForKey:tabsKey]==22 && ownerAlertCount==alerts+1 && ![[owner valueForKey:@"inputErrorPresented"]boolValue],@"Valid edit commits before profile confirmation");
    NSString *expectedPath=[NSDictionary dictionaryWithContentsOfURL:[fixture URLForResource:@"FactoryDefaults" withExtension:@"plist" subdirectory:@"Defaults"]][@"TetexBinPath"];
    Check(expectedPath.length && [capturedOwnerAlert.informativeText containsString:expectedPath],@"Profile confirmation displays the proposed TeX engine path");
    Check(![capturedOwnerAlert.buttons.firstObject.keyEquivalent isEqual:@"\r"] && [capturedOwnerAlert.buttons.lastObject.keyEquivalent isEqual:@"\e"],@"Profile confirmation reserves Escape for Cancel and never applies on Return");
    FinishOwnerAlert(NSAlertSecondButtonReturn);
    Check([TSIsolatedAppKitDefaults integerForKey:tabsKey]==22,@"Cancelling the profile preserves the committed edit");
    // Applying a confirmed profile ends the field editor; a later focus change
    // cannot write its prior text over the profile's value.
    EditOwnerField(owner,tabs,@"31");[owner setDefaults:profileChoice];
    FinishOwnerAlert(NSAlertFirstButtonReturn);
    NSInteger profileTabs=[TSIsolatedAppKitDefaults integerForKey:tabsKey];
    Check(profileTabs!=31 && tabs.currentEditor==nil,@"Profile application releases the pre-application editor");
    [shell selectCategoryIdentifier:TSSettingsCategoryGeneral];
    Check([TSIsolatedAppKitDefaults integerForKey:tabsKey]==profileTabs,@"Later navigation cannot restore the pre-profile text");
    TSIsolatedAppKitDefaults.values = [saved mutableCopy];
    [owner updateControlsFromUserDefaults:TSIsolatedAppKitDefaults];
    [shell beginSession];
    method_setImplementation(alertMethod, originalAlert);
    puts("PASS: owner field-editor navigation, restore, validation and close");
}
