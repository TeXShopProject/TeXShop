@interface TSPreferences (LifecycleRegression)
- (void)releasePreferencePanels;
- (void)tearDownPreferenceEditing;
- (void)setAllThemeEditingEnabled:(BOOL)enabled;
@end
@interface SettingsFontPanelBoundary:NSObject
@property NSUInteger closes;
@end
@implementation SettingsFontPanelBoundary
- (void)close { self.closes++; }
@end
@interface SettingsFontManagerBoundary:SettingsFontProbe
@property id target;
@property NSUInteger fronts;
@property SettingsFontPanelBoundary *panel;
@end
@implementation SettingsFontManagerBoundary
- (void)setSelectedFont:(NSFont *)font isMultiple:(BOOL)multiple {}
- (void)orderFrontFontPanel:(id)sender { self.fronts++; }
- (id)fontPanel:(BOOL)create { return self.panel; }
@end
static SettingsFontManagerBoundary *lifecycleFontManager;
static id LifecycleFontManager(id receiver,SEL selector){return lifecycleFontManager;}
static void CheckOwnerLifecycle(TSPreferences *owner,TSSettingsWindowController *shell) {
    NSDictionary *saved=[TSIsolatedAppKitDefaults.values copy];
    Method fontMethod=class_getClassMethod(NSFontManager.class,@selector(sharedFontManager));
    lifecycleFontManager=[SettingsFontManagerBoundary new];lifecycleFontManager.panel=[SettingsFontPanelBoundary new];
    IMP oldFont=method_setImplementation(fontMethod,(IMP)LifecycleFontManager);
    Method key=class_getInstanceMethod(NSWindow.class,@selector(isKeyWindow)),main=class_getInstanceMethod(NSWindow.class,@selector(isMainWindow));
    IMP oldKey=method_setImplementation(key,(IMP)NavigationKey),oldMain=method_setImplementation(main,(IMP)NavigationKey);
    navigationTestWindow=shell.window;navigationTestKey=YES;
    [owner setValue:@NO forKey:@"endingPreferences"];
    NSObject *documentTarget=[NSObject new];lifecycleFontManager.target=documentTarget;
    [owner changeDocumentFont:nil];Check([[owner valueForKey:@"fontEditingContext"]integerValue]==1,@"Document font button selects its explicit destination");
    [owner changeConsoleFont:nil];Check([[owner valueForKey:@"fontEditingContext"]integerValue]==2,@"Console font button selects its explicit destination");
    Check(lifecycleFontManager.fronts==2 && lifecycleFontManager.target==documentTarget,@"Font entry buttons preserve the document's global font target");
    [owner releasePreferencePanels];Check(lifecycleFontManager.panel.closes==0,@"A document-owned font panel remains open");
    lifecycleFontManager.target=nil;navigationTestKey=NO;[owner setValue:@YES forKey:@"ownsFontPanel"];
    [owner releasePreferencePanels];Check(lifecycleFontManager.panel.closes==0,@"Inactive settings do not close the document font panel");
    navigationTestKey=YES;[owner setValue:@YES forKey:@"ownsFontPanel"];[owner releasePreferencePanels];
    Check(lifecycleFontManager.panel.closes==1 && ![[owner valueForKey:@"ownsFontPanel"]boolValue],@"Only the active owned font session closes");
    [owner releasePreferencePanels];Check(lifecycleFontManager.panel.closes==1,@"Repeated release is idempotent");
    [owner setValue:@YES forKey:@"ownsFontPanel"];[owner setValue:@YES forKey:@"endingPreferences"];
    [owner setValue:@2 forKey:@"fontEditingContext"];
    NSDictionary *before=[TSIsolatedAppKitDefaults dictionaryRepresentation];lifecycleFontManager.converted=[NSFont userFontOfSize:29];
    [owner changeFont:lifecycleFontManager];Check([[TSIsolatedAppKitDefaults dictionaryRepresentation]isEqual:before],@"Ending sessions reject late font actions");
    [owner setValue:@NO forKey:@"endingPreferences"];
    Method alert=class_getInstanceMethod(NSAlert.class,@selector(beginSheetModalForWindow:completionHandler:));
    IMP oldAlert=method_setImplementation(alert,(IMP)CaptureOwnerAlert);
    [shell selectCategoryIdentifier:TSSettingsCategoryEditor];
    NSTextField *tabs=[owner valueForKey:@"tabIndentField"];
    EditOwnerField(owner,tabs,@"invalid");NSUInteger count=ownerAlertCount;
    id original=[TSIsolatedAppKitDefaults objectForKey:tabsKey];
    [owner finishPreferencesForTermination];
    Check(ownerAlertCount==count && [[TSIsolatedAppKitDefaults objectForKey:tabsKey]isEqual:original] && tabs.currentEditor==nil,@"Termination discards invalid editing without warning or persistence");
    [owner setValue:@NO forKey:@"endingPreferences"];[owner setValue:@NO forKey:@"inputErrorPresented"];[shell beginSession];[shell selectCategoryIdentifier:TSSettingsCategoryEditor];
    EditOwnerField(owner,tabs,@"23");[owner finishPreferencesForTermination];
    Check(ownerAlertCount==count && [TSIsolatedAppKitDefaults integerForKey:tabsKey]==23 && tabs.currentEditor==nil,@"Termination commits valid editing without showing a warning");
    method_setImplementation(alert,oldAlert);method_setImplementation(fontMethod,oldFont);
    method_setImplementation(key,oldKey);method_setImplementation(main,oldMain);navigationTestWindow=nil;lifecycleFontManager=nil;
    TSIsolatedAppKitDefaults.values=[saved mutableCopy];[owner setValue:@NO forKey:@"endingPreferences"];[owner updateControlsFromUserDefaults:TSIsolatedAppKitDefaults];[shell beginSession];
    puts("PASS: actual font entry/ownership, idempotent release and valid/invalid termination");
}
