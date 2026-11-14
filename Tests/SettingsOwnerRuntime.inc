@interface TSPreferences (RuntimeRegression)
- (void)refreshRuntimePreferences;
@end
@interface SettingsRuntimeDelegate : NSObject <NSApplicationDelegate>
@property NSUInteger xmlUpdates, copyUpdates;
@property (copy) NSDictionary *xmlValues;
- (void)updateXMLTabs;
- (void)syncImageCopyTypeMenu;
@end
@implementation SettingsRuntimeDelegate
- (void)updateXMLTabs {
    self.xmlUpdates++;
    NSMutableDictionary *values=[NSMutableDictionary dictionary];
    for (NSString *name in @[@"Chapter",@"Section",@"Subsection",@"Subsubsection",@"Introduction",@"Conclusion",@"Exercises",@"Project",@"Figure",@"Table",@"Mark"]) {
        NSString *key=[NSString stringWithFormat:@"XML%@Tag",name];values[key]=@([TSIsolatedAppKitDefaults boolForKey:key]);
    }
    self.xmlValues=values;
}
- (void)syncImageCopyTypeMenu { self.copyUpdates++; }
@end
static void CheckOwnerRuntime(TSPreferences *owner) {
    NSDictionary *saved=[TSIsolatedAppKitDefaults.values copy];
    id<NSApplicationDelegate> previous=NSApp.delegate;
    SettingsRuntimeDelegate *delegate=[SettingsRuntimeDelegate new];NSApp.delegate=delegate;
    BOOL savedAuto=doAutoSave,savedWatch=activateBauerPatch,savedBrackets=editorCanAddBrackets;
    doAutoSave=YES;activateBauerPatch=YES;
    NSButton *autoSave=[owner valueForKey:@"autoSaveEnabledButton"];
    NSButton *control=[NSButton checkboxWithTitle:@"fixture" target:nil action:NULL];
    NSMenuItem *tags=[[NSMenuItem alloc]initWithTitle:NSLocalizedString(@"Tags",@"") action:NULL keyEquivalent:@""];[NSApp.mainMenu addItem:tags];
    NSArray *names=@[@"Chapter",@"Section",@"Subsection",@"Subsubsection",@"Introduction",@"Conclusion",@"Exercises",@"Project",@"Figure",@"Table",@"Mark"];
    SEL actions[]={@selector(XMLChapterButtonChanged:),@selector(XMLSectionButtonChanged:),@selector(XMLSubsectionButtonChanged:),@selector(XMLSubsubsectionButtonChanged:),@selector(XMLIntroductionButtonChanged:),@selector(XMLConclusionButtonChanged:),@selector(XMLExercisesButtonChanged:),@selector(XMLProjectButtonChanged:),@selector(XMLFigureButtonChanged:),@selector(XMLTableButtonChanged:),@selector(XMLMarkButtonChanged:)};
    for (NSNumber *value in @[@YES,@NO,@YES]) {
        autoSave.state=value.boolValue;[owner autoSaveEnabledPressed:autoSave];
        Check([TSIsolatedAppKitDefaults boolForKey:AutoSaveEnabledKey]==value.boolValue && doAutoSave && activateBauerPatch, @"Autosave saves its next-launch choice without changing running document behavior");
        control.state=value.boolValue;[owner editorAddBracketsPressed:control];
        Check([TSIsolatedAppKitDefaults boolForKey:EditorCanAddBracketsKey]==value.boolValue && editorCanAddBrackets==value.boolValue, @"Bracket action updates stored and process values immediately");
        for(NSUInteger i=0;i<names.count;i++) {
            NSUInteger count=delegate.xmlUpdates;
            Check([NSApp sendAction:actions[i] to:owner from:control],@"Each real XML action can be sent");
            NSString *key=[NSString stringWithFormat:@"XML%@Tag",names[i]];
            Check(delegate.xmlUpdates==count+1 && [TSIsolatedAppKitDefaults boolForKey:key]==value.boolValue && [delegate.xmlValues[key] boolValue]==value.boolValue,@"XML value is saved before one menu refresh");
        }
    }
    for(NSNumber *value in @[@NO,@YES]) {
        [TSIsolatedAppKitDefaults setBool:value.boolValue forKey:EditorCanAddBracketsKey];
        [TSIsolatedAppKitDefaults setBool:value.boolValue forKey:AutoSaveEnabledKey];
        [TSIsolatedAppKitDefaults setBool:value.boolValue forKey:TagMenuInMenuBarKey];
        for(NSString *name in names)[TSIsolatedAppKitDefaults setBool:value.boolValue forKey:[NSString stringWithFormat:@"XML%@Tag",name]];
        NSUInteger count=delegate.xmlUpdates;[owner refreshRuntimePreferences];
        Check(editorCanAddBrackets==value.boolValue && doAutoSave && activateBauerPatch,@"Bulk refresh respects restart-only runtime copies");
        Check(tags.hidden==!value.boolValue,@"Bulk refresh updates Tags visibility");
        Check(delegate.xmlUpdates==count+1,@"Bulk refresh calls the XML menu once");
        for(NSString *name in names)Check([delegate.xmlValues[[NSString stringWithFormat:@"XML%@Tag",name]] boolValue]==value.boolValue,@"Every XML value reaches the menu refresh");
    }
    NSMutableDictionary *profileValues=[[TSIsolatedAppKitDefaults dictionaryRepresentation]mutableCopy];
    NSInteger previousCopy=[TSIsolatedAppKitDefaults integerForKey:PdfCopyTypeKey];
    profileValues[PdfCopyTypeKey]=@(previousCopy==1?2:1);
    NSDictionary *factory=[NSDictionary dictionaryWithContentsOfURL:[fixture URLForResource:@"FactoryDefaults" withExtension:@"plist" subdirectory:@"Defaults"]];
    NSFont *font=[NSFont userFontOfSize:12];
    TSPreferenceProfile *profile=[[TSPreferenceProfile alloc]initWithProfile:profileValues documentFont:[NSArchiver archivedDataWithRootObject:font] registeredDefaults:factory];
    Check(profile!=nil,@"PDF copy format profile validates");
    NSUInteger copies=delegate.copyUpdates;[owner applyPreferenceProfile:profile font:font];
    Check(delegate.copyUpdates==copies+1 && [TSIsolatedAppKitDefaults integerForKey:PdfCopyTypeKey]!=previousCopy,@"Profile refreshes the PDF copy menu once with the new value");
    [owner applyPreferenceProfile:profile font:font];Check(delegate.copyUpdates==copies+1,@"Unchanged profile does not refresh PDF copy menu twice");
    [NSApp.mainMenu removeItem:tags];NSApp.delegate=previous;
    doAutoSave=savedAuto;activateBauerPatch=savedWatch;editorCanAddBrackets=savedBrackets;
    TSIsolatedAppKitDefaults.values=[saved mutableCopy];[owner updateControlsFromUserDefaults:TSIsolatedAppKitDefaults];
    puts("PASS: real owner runtime copies and eleven XML actions before menu refresh");
}
