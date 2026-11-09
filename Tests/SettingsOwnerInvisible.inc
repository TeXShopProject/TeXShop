#import "TSInvisibleCharacters.h"
@interface TSPreferences (InvisibleRegression)
- (void)updateInvisibleCharacterControls:(NSUserDefaults *)defaults;
@end
static void CheckOwnerInvisible(TSPreferences *owner, TSSettingsWindowController *shell) {
    NSDictionary *saved = [TSIsolatedAppKitDefaults.values copy];
    NSUserDefaults *settings = TSIsolatedAppKitDefaults;
    [shell selectCategoryIdentifier:TSSettingsCategoryEditor];
    NSArray *keys = @[@"SpaceCharacterKind",@"FullwidthSpaceCharacterKind",@"NewLineCharacterKind",@"TabCharacterKind"];
    NSArray *show = @[@"ShowSpaceCharacter",@"ShowFullwidthSpaceCharacter",@"ShowNewLineCharacter",@"ShowTabCharacter"];
    NSArray *names = @[@"Space",@"FullwidthSpace",@"NewLine",@"Tab"];
    NSArray *expected = @[@[@"␣",@"·"],@[@"□",@"■"],@[@"↵",@"¶",@"↩",@"⏎"],@[@"‣",@"▹",@"⇥"]];
    for (NSUInteger i=0;i<4;i++) {
        [settings setBool:YES forKey:show[i]];[settings setInteger:1 forKey:keys[i]];
    }
    [owner updateSettingsCategory:TSSettingsCategoryEditor fromDefaults:settings];
    for (NSUInteger i=0;i<4;i++) {
        NSPopUpButton *popup=[owner valueForKey:[names[i] stringByAppendingString:@"CharacterKindPopup"]];
        NSButton *toggle=[owner valueForKey:[NSString stringWithFormat:@"show%@CharacterButton",names[i]]];
        Check([popup.itemTitles isEqual:expected[i]] && [TSInvisibleMarkers(keys[i]) isEqual:expected[i]], @"Independent marker order agrees with actual UI and renderer");
        Check(popup.selectedTag==1 && popup.enabled, @"Historical second marker survives refresh");
        Check(popup.action==@selector(invisibleCharacterChanged:) && popup.target!=nil, @"Actual marker action remains wired");
        for (NSUInteger j=0;j<[expected[i] count];j++) {
            [popup selectItemAtIndex:j];[NSApp sendAction:popup.action to:popup.target from:popup];
            Check(TSInvisibleStoredIndex(settings,keys[i])==j, @"Each marker saves through the real owner");
            Check([settings integerForKey:keys[i]]>=0 && [settings integerForKey:keys[i]]<2, @"Legacy marker domain stays in its supported range");
            [owner updateSettingsCategory:TSSettingsCategoryEditor fromDefaults:settings];
            Check(popup.selectedTag==j && [popup.title isEqual:expected[i][j]], @"Marker label and stored value survive refresh");
        }
        for (NSUInteger added=2;added<[expected[i] count];added++) for (NSUInteger legacy=0;legacy<2;legacy++) {
            [popup selectItemAtIndex:added];[NSApp sendAction:popup.action to:popup.target from:popup];
            [popup selectItemAtIndex:legacy];[NSApp sendAction:popup.action to:popup.target from:popup];
            Check([settings objectForKey:TSInvisibleExtendedKey(keys[i])]==nil, @"Returning to either historical marker removes the extended override");
            [owner updateSettingsCategory:TSSettingsCategoryEditor fromDefaults:settings];
            Check(popup.selectedTag==legacy, @"Historical marker remains selected after reload");
        }
        [popup selectItemAtIndex:1];[owner invisibleCharacterChanged:popup];
        toggle.state=NSControlStateValueOff;[NSApp sendAction:toggle.action to:toggle.target from:toggle];
        Check(!popup.enabled && popup.selectedTag==1, @"Turning marker display off preserves the chosen glyph");
        toggle.state=NSControlStateValueOn;[NSApp sendAction:toggle.action to:toggle.target from:toggle];
        Check(popup.enabled && popup.selectedTag==1, @"Turning marker display on restores the same choice");
        for (id bad in @[@(-1),@99,@"junk"]) {
            [settings setObject:bad forKey:keys[i]];[owner updateInvisibleCharacterControls:settings];
            Check(popup.indexOfSelectedItem==0, @"Malformed marker values fall back safely");
            Check([TSInvisibleMarker(TSInvisibleMarkers(keys[i]),[bad integerValue]) isEqual:expected[i][0]], @"Malformed rendering indices use the same safe marker");
        }
    }
    NSPopUpButton *tab=[owner valueForKey:@"TabCharacterKindPopup"];
    [tab itemAtIndex:0].title=@"wrong";[owner updateInvisibleCharacterControls:settings];
    Check([tab.itemTitles isEqual:expected[3]], @"Damaged menu is repaired even when item count matches");
    for (NSUInteger i=0;i<4;i++) { [settings setObject:@"0" forKey:keys[i]];[settings setObject:@"NO" forKey:show[i]];[settings removeObjectForKey:TSInvisibleExtendedKey(keys[i])]; }
    [owner updateSettingsCategory:TSSettingsCategoryEditor fromDefaults:settings];
    for (NSUInteger i=0;i<4;i++) {
        NSPopUpButton *popup=[owner valueForKey:[names[i] stringByAppendingString:@"CharacterKindPopup"]];
        NSButton *toggle=[owner valueForKey:[NSString stringWithFormat:@"show%@CharacterButton",names[i]]];
        Check(popup.selectedTag==0 && !popup.enabled && toggle.state==NSControlStateValueOff, @"Replaced settings refresh glyph and disabled state together");
    }
    [settings setBool:YES forKey:show[3]];[owner updateSettingsCategory:TSSettingsCategoryEditor fromDefaults:settings];
    [tab selectItemAtIndex:2];[owner invisibleCharacterChanged:tab];
    Check([settings integerForKey:keys[3]]==0 && [settings integerForKey:TSInvisibleExtendedKey(keys[3])]==2, @"Extended marker uses a separate key");
    [owner updateInvisibleCharacterControls:settings];Check(tab.selectedTag==2,@"Extended marker survives reopening");
    [settings setInteger:1 forKey:keys[3]];[owner updateInvisibleCharacterControls:settings];
    Check(tab.selectedTag==1, @"Historical second marker wins over a stale extended override");
    TSIsolatedAppKitDefaults.values=[saved mutableCopy];[owner updateControlsFromUserDefaults:settings];
    puts("PASS: real owner invisible marker choices, retention, legacy compatibility and invalid values");
}
