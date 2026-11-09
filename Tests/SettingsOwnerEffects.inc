extern NSUInteger TSSettingsEncodingPreparations;
@interface SettingsPreparationDelegate:NSObject <NSApplicationDelegate>
@property NSUInteger copies;
@end
@implementation SettingsPreparationDelegate
- (void)syncImageCopyTypeMenu {self.copies++;}
- (void)updateXMLTabs {}
@end
// Observe the completed transaction, not merely which notification was sent.
static void CheckOwnerEffects(TSPreferences *owner, NSDictionary *factory, NSDictionary *baseTheme) {
    id<NSApplicationDelegate> oldDelegate=NSApp.delegate;SettingsPreparationDelegate *preparation=[SettingsPreparationDelegate new];NSApp.delegate=preparation;
    NSDictionary *saved = [TSIsolatedAppKitDefaults.values copy];
    NSDictionary *savedLite = liteColors, *savedDark = darkColors;
    NSMutableDictionary *nextTheme = [baseTheme mutableCopy];
    nextTheme[@"SourceBackground"] = @[@0.12,@0.34,@0.56,@1];
    nextTheme[@"Title"] = @"ProfileEffectFixture";
    Check([nextTheme writeToFile:[ColorPath stringByAppendingPathComponent:@"ProfileEffectFixture.plist"] atomically:YES], @"Temporary distinct profile theme is available");
    [TSIsolatedAppKitDefaults setObject:@"LiteTheme" forKey:DefaultLiteThemeKey];
    [TSIsolatedAppKitDefaults setObject:@"DarkTheme" forKey:DefaultDarkThemeKey];
    [TSIsolatedAppKitDefaults setObject:@"round" forKey:TSDockIconKey];
    [[TSColorSupport sharedInstance] initializeColors];
    [[TSDockIconController sharedController] restoreSavedIcon];
    NSMutableDictionary *values = [[TSIsolatedAppKitDefaults dictionaryRepresentation] mutableCopy];
    values[DefaultLiteThemeKey] = @"ProfileEffectFixture";
    values[TSDockIconKey] = @"current";
    values[EncodingKey]=[[TSIsolatedAppKitDefaults stringForKey:EncodingKey]isEqual:@"MacOSRoman"]?@"UTF-8 Unicode":@"MacOSRoman";
    values[TSTeXAwareSpellCheckingKey]=@(![TSIsolatedAppKitDefaults boolForKey:TSTeXAwareSpellCheckingKey]);
    values[PdfCopyTypeKey]=@([TSIsolatedAppKitDefaults integerForKey:PdfCopyTypeKey]==1?2:1);
    NSUInteger encoding=TSSettingsEncodingPreparations,spelling=spellRefreshes,copies=preparation.copies;
    NSFont *font = [NSFont userFontOfSize:12];
    TSPreferenceProfile *proposal = [[TSPreferenceProfile alloc] initWithProfile:values documentFont:[NSArchiver archivedDataWithRootObject:font] registeredDefaults:factory];
    Check(proposal != nil, @"Theme-changing profile validates");
    __block NSUInteger colors = 0;
    id observer = [NSNotificationCenter.defaultCenter addObserverForName:SourceColorChangedNotification object:owner queue:nil usingBlock:^(NSNotification *note) {
        colors++;
        Check(TSSettingsEncodingPreparations==encoding+1,@"Encoding is prepared before profile notifications");
        Check(spellRefreshes==spelling+1,@"Spelling is prepared before profile notifications");
        Check(preparation.copies==copies+1,@"PDF copy format is prepared before profile notifications");
        Check([liteColors[@"SourceBackground"] isEqual:nextTheme[@"SourceBackground"]], @"Theme notification recipients already see the new colors");
        Check([[[TSDockIconController sharedController] valueForKey:@"selection"] isEqual:@"current"], @"Dock selection is prepared before change notifications");
    }];
    [owner applyPreferenceProfile:proposal font:font];
    Check(colors == 1, @"One theme notification for a changed profile");
    Check(testDockTile.contentView == nil, @"Profile restores the standard Dock icon immediately");
    [owner applyPreferenceProfile:proposal font:font];
    Check(colors == 1, @"Repeated unchanged profile has no redundant theme effect");
    [NSNotificationCenter.defaultCenter removeObserver:observer];
    TSIsolatedAppKitDefaults.values = [saved mutableCopy];
    liteColors = savedLite; darkColors = savedDark;
    [[TSDockIconController sharedController] restoreSavedIcon];
    [owner updateControlsFromUserDefaults:TSIsolatedAppKitDefaults];
    NSApp.delegate=oldDelegate;
    __block NSUInteger findChanges=0;
    id findObserver=[NSNotificationCenter.defaultCenter addObserverForName:TSFindMethodChangedNotification object:owner queue:nil usingBlock:^(NSNotification *note){findChanges++;Check([TSIsolatedAppKitDefaults integerForKey:FindMethodKey]==1,@"Find notification observes the committed method");}];
    NSMatrix *methods=[owner valueForKey:@"findMatrix"];[methods selectCellWithTag:1];
    [owner findPanelChanged:methods];
    Check(findChanges==1,@"Actual find action delivers one live-view notification");
    [NSNotificationCenter.defaultCenter removeObserver:findObserver];
    TSIsolatedAppKitDefaults.values=[saved mutableCopy];[owner updateControlsFromUserDefaults:TSIsolatedAppKitDefaults];
    puts("PASS: profile prepares new theme and Dock before notifying exactly once");
}
