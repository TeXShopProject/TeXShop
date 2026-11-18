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
    (void)factory;
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
    __block NSUInteger colors = 0;
    id observer = [NSNotificationCenter.defaultCenter addObserverForName:SourceColorChangedNotification object:owner queue:nil usingBlock:^(NSNotification *note) {
        colors++;
        Check(TSSettingsEncodingPreparations==encoding+1,@"Encoding is prepared before profile notifications");
        Check(spellRefreshes==spelling+1,@"Spelling is prepared before profile notifications");
        Check(preparation.copies==copies+1,@"PDF copy format is prepared before profile notifications");
        Check([liteColors[@"SourceBackground"] isEqual:nextTheme[@"SourceBackground"]], @"Theme notification recipients already see the new colors");
        Check([[[TSDockIconController sharedController] valueForKey:@"selection"] isEqual:@"current"], @"Dock selection is prepared before change notifications");
    }];
    [owner applyEngineProfileValues:values];
    Check(colors == 1, @"One theme notification for a changed profile");
    Check(testDockTile.contentView == nil, @"Profile restores the standard Dock icon immediately");
    [owner applyEngineProfileValues:values];
    Check(colors == 1, @"Repeated unchanged profile has no redundant theme effect");
    [NSNotificationCenter.defaultCenter removeObserver:observer];
    TSIsolatedAppKitDefaults.values = [saved mutableCopy];
    liteColors = savedLite; darkColors = savedDark;
    [[TSDockIconController sharedController] restoreSavedIcon];
    [owner updateControlsFromUserDefaults:TSIsolatedAppKitDefaults];
    NSApp.delegate=oldDelegate;
    __block NSUInteger findChanges=0;
    __block NSInteger expectedFind=1;
    id findObserver=[NSNotificationCenter.defaultCenter addObserverForName:TSFindMethodChangedNotification object:owner queue:nil usingBlock:^(NSNotification *note){findChanges++;Check([TSIsolatedAppKitDefaults integerForKey:FindMethodKey]==expectedFind,@"Find notification observes the committed method");}];
    NSMatrix *methods=[owner valueForKey:@"findMatrix"];[methods selectCellWithTag:1];
    [owner findPanelChanged:methods];
    Check(findChanges==1,@"Actual find action delivers one live-view notification");
    expectedFind=0;[methods selectCellWithTag:0];[owner findPanelChanged:methods];
    Check(findChanges==2,@"Bar to panel action delivers the reverse live-view notification");
    // The switch that keeps the Advanced Find panel on top: usable only with that panel as the find interface.
    NSButton *floats=[owner valueForKey:@"findPanelFloatsButton"];
    Check(floats!=nil && floats.action==@selector(findPanelFloatsChanged:) && !floats.enabled,@"With another find interface the Advanced Find panel switch is disabled");
    expectedFind=3;[methods selectCellWithTag:3];[owner findPanelChanged:methods];
    Check(floats.enabled,@"Choosing the Advanced Find panel enables its switch at once");
    [TSIsolatedAppKitDefaults removeObjectForKey:TSAdvancedFindPanelFloatsKey];floats.state=NSControlStateValueOff;[floats performClick:nil];
    Check([TSIsolatedAppKitDefaults boolForKey:TSAdvancedFindPanelFloatsKey],@"The switch sets the setting the Advanced Find panel reads");
    expectedFind=1;[methods selectCellWithTag:1];[owner findPanelChanged:methods];
    Check(!floats.enabled && [TSIsolatedAppKitDefaults boolForKey:TSAdvancedFindPanelFloatsKey],@"Another find interface disables the switch and keeps its value");
    [owner updateControlsFromUserDefaults:TSIsolatedAppKitDefaults];
    Check(floats.state==NSControlStateValueOn,@"The switch shows the stored value");
    expectedFind=3;[methods selectCellWithTag:3];[owner findPanelChanged:methods];[floats performClick:nil];
    Check(![TSIsolatedAppKitDefaults boolForKey:TSAdvancedFindPanelFloatsKey],@"The switch clears the setting");
    // Highlight Fullwidth Letters and Symbols: on in the factory defaults; the switch writes the setting that syntax
    // coloring reads and has every open window colored again, once for each change.
    NSButton *fullwidth=[owner valueForKey:@"highlightFullwidthSymbolsButton"];
    Check(fullwidth!=nil && fullwidth.action==@selector(highlightFullwidthSymbolsChanged:) && [fullwidth.identifier isEqual:@"settings.fullwidth-highlight-button"] && fullwidth.enabled,@"Highlight Fullwidth Letters and Symbols is a usable switch");
    Check([factory[HighlightFullwidthSymbolsKey] boolValue],@"Highlight Fullwidth Letters and Symbols is on in the factory defaults");
    [TSIsolatedAppKitDefaults setBool:NO forKey:HighlightFullwidthSymbolsKey];[owner updateControlsFromUserDefaults:TSIsolatedAppKitDefaults];
    Check(fullwidth.state==NSControlStateValueOff,@"The fullwidth switch shows a stored off");
    [TSIsolatedAppKitDefaults removeObjectForKey:HighlightFullwidthSymbolsKey];[owner updateControlsFromUserDefaults:TSIsolatedAppKitDefaults];
    Check(fullwidth.state==NSControlStateValueOn,@"Without a setting of the user's the fullwidth switch is on");
    __block NSUInteger recolors=0;
    id recolorObserver=[NSNotificationCenter.defaultCenter addObserverForName:@"NeedsForRecolorNotification" object:owner queue:nil usingBlock:^(NSNotification *note){recolors++;}];
    [fullwidth performClick:nil];
    Check(TSIsolatedAppKitDefaults.values[HighlightFullwidthSymbolsKey]!=nil && ![TSIsolatedAppKitDefaults boolForKey:HighlightFullwidthSymbolsKey] && recolors==1,@"Turning the fullwidth switch off stores it and has open windows colored again");
    [owner updateControlsFromUserDefaults:TSIsolatedAppKitDefaults];
    Check(fullwidth.state==NSControlStateValueOff,@"The fullwidth switch shows the stored value");
    [fullwidth performClick:nil];
    Check([TSIsolatedAppKitDefaults boolForKey:HighlightFullwidthSymbolsKey] && recolors==2,@"Turning it on again stores it and has open windows colored again");
    [NSNotificationCenter.defaultCenter removeObserver:recolorObserver];
    [NSNotificationCenter.defaultCenter removeObserver:findObserver];
    TSIsolatedAppKitDefaults.values=[saved mutableCopy];[owner updateControlsFromUserDefaults:TSIsolatedAppKitDefaults];
    puts("PASS: profile prepares new theme and Dock before notifying exactly once");
}
