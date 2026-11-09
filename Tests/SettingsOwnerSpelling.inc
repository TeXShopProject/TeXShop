static void CheckOwnerSpelling(TSPreferences *owner,TSSettingsWindowController *shell) {
    NSDictionary *saved=[TSIsolatedAppKitDefaults.values copy];
    [TSIsolatedAppKitDefaults setBool:NO forKey:@"SpellCheckEnabled"];
    NSArray *keys=@[@"TurnOffCommandSpellCheck",@"TurnOffParameterSpellCheck",@"TurnOffCommentSpellCheck"];
    NSArray *names=@[@"spellCheckCommands",@"spellCheckParameters",@"spellCheckComments"];
    for(NSUInteger i=0;i<3;i++)[TSIsolatedAppKitDefaults setBool:i!=1 forKey:keys[i]];
    NSButton *modern=[owner valueForKey:@"texAwareSpellCheckButton"],*legacy=[owner valueForKey:@"legacySpellCheckButton"];
    for(NSNumber *initial in @[@YES,@NO]) {
        [TSIsolatedAppKitDefaults setBool:initial.boolValue forKey:TSTeXAwareSpellCheckingKey];
        [owner updateSettingsCategory:TSSettingsCategorySpelling fromDefaults:TSIsolatedAppKitDefaults];
        [shell endSession];[shell beginSession];[shell selectCategoryIdentifier:TSSettingsCategorySpelling];
        NSView *note=Find(Find([shell viewForCategoryIdentifier:TSSettingsCategorySpelling],@"row.catalog.spelling.1.0"),@"settings.change-note");
        Check(note.hidden,@"Spelling note starts hidden for this category visit");
        NSUInteger count=spellRefreshes;
        NSButton *choice=initial.boolValue?legacy:modern;choice.state=NSControlStateValueOn;
        Check([NSApp sendAction:choice.action to:choice.target from:choice],@"Both real spelling radio actions are connected");
        Check([TSIsolatedAppKitDefaults boolForKey:TSTeXAwareSpellCheckingKey]!=initial.boolValue && spellRefreshes==count+1,@"Either spelling mode updates the stored value and invalidates once");
        Check(!note.hidden,@"Both spelling actions show the transient note");
        Check(modern.state==!initial.boolValue && legacy.state==initial.boolValue,@"Both real radios reflect the same choice");
        for(NSUInteger i=0;i<3;i++)Check([[owner valueForKey:names[i]]isEnabled]==initial.boolValue && [TSIsolatedAppKitDefaults boolForKey:keys[i]]==(i!=1),@"Legacy child values survive switching both ways");
        Check([[owner valueForKey:@"editSpellingExclusionsButton"]isEnabled]!=initial.boolValue && ![TSIsolatedAppKitDefaults boolForKey:@"SpellCheckEnabled"],@"Rules edit follows its mode independently of continuous spelling");
        choice=initial.boolValue?modern:legacy;choice.state=NSControlStateValueOn;[NSApp sendAction:choice.action to:choice.target from:choice];
        Check(note.hidden,@"Returning to the entry value clears the spelling note");
    }
    TSIsolatedAppKitDefaults.values=[saved mutableCopy];[owner updateControlsFromUserDefaults:TSIsolatedAppKitDefaults];
    puts("PASS: both real spelling mode actions, transient notes, invalidation and retained child values");
}
