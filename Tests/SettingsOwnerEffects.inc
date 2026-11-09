// Observe the completed transaction, not merely which notification was sent.
static void CheckOwnerEffects(TSPreferences *owner, NSDictionary *factory, NSDictionary *baseTheme) {
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
    NSFont *font = [NSFont userFontOfSize:12];
    TSPreferenceProfile *proposal = [[TSPreferenceProfile alloc] initWithProfile:values documentFont:[NSArchiver archivedDataWithRootObject:font] registeredDefaults:factory];
    Check(proposal != nil, @"Theme-changing profile validates");
    __block NSUInteger colors = 0;
    id observer = [NSNotificationCenter.defaultCenter addObserverForName:SourceColorChangedNotification object:owner queue:nil usingBlock:^(NSNotification *note) {
        colors++;
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
    puts("PASS: profile prepares new theme and Dock before notifying exactly once");
}
