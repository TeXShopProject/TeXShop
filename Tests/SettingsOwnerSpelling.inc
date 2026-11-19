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
        NSView *row=Find([shell viewForCategoryIdentifier:TSSettingsCategorySpelling],@"row.catalog.spelling.1.0");
        NSUInteger count=spellRefreshes;
        NSButton *choice=initial.boolValue?legacy:modern;choice.state=NSControlStateValueOn;
        Check([NSApp sendAction:choice.action to:choice.target from:choice],@"Both real spelling radio actions are connected");
        Check([TSIsolatedAppKitDefaults boolForKey:TSTeXAwareSpellCheckingKey]!=initial.boolValue && spellRefreshes==count+1,@"Either spelling mode updates the stored value and invalidates once");
        // The choice takes effect at once, in open documents too: it shows no warning.
        Check(row!=nil && Find(row,@"settings.change-note")==nil,@"Neither spelling action shows a note");
        Check(modern.state==!initial.boolValue && legacy.state==initial.boolValue,@"Both real radios reflect the same choice");
        for(NSUInteger i=0;i<3;i++)Check([[owner valueForKey:names[i]]isEnabled]==initial.boolValue && [TSIsolatedAppKitDefaults boolForKey:keys[i]]==(i!=1),@"Legacy child values survive switching both ways");
        Check([[owner valueForKey:@"editSpellingExclusionsButton"]isEnabled]!=initial.boolValue && ![TSIsolatedAppKitDefaults boolForKey:@"SpellCheckEnabled"],@"Rules edit follows its mode independently of continuous spelling");
        // The rules button shares the row of its choice; disabling it leaves both choices usable.
        Check(modern.isEnabled && legacy.isEnabled,@"Both spelling choices stay available whichever is chosen");
        choice=initial.boolValue?modern:legacy;choice.state=NSControlStateValueOn;[NSApp sendAction:choice.action to:choice.target from:choice];
        Check([TSIsolatedAppKitDefaults boolForKey:TSTeXAwareSpellCheckingKey]==initial.boolValue,@"Choosing the entry value again restores it");
    }
    // At the narrowest and the usual window, the rules button stays beside the first line of its choice.
    NSSize originalSize=shell.window.contentView.frame.size;[shell selectCategoryIdentifier:TSSettingsCategorySpelling];
    for(NSNumber *width in @[@900,@1040]){
        [shell.window setContentSize:NSMakeSize(width.doubleValue,780)];[shell.window.contentView layoutSubtreeIfNeeded];
        NSView *row=Find([shell viewForCategoryIdentifier:TSSettingsCategorySpelling],@"row.catalog.spelling.1.0");NSButton *rules=[owner valueForKey:@"editSpellingExclusionsButton"];
        NSRect e=[rules.superview convertRect:[rules alignmentRectForFrame:rules.frame] toView:row],m=[modern.superview convertRect:[modern alignmentRectForFrame:modern.frame] toView:row];
        CGFloat ruleBaseline=NSMaxY(e)-rules.firstBaselineOffsetFromTop,choiceBaseline=NSMaxY(m)-modern.firstBaselineOffsetFromTop;
        Check(fabs(ruleBaseline-choiceBaseline)<1 && NSMinX(e)>NSMaxX(m)+15 && fabs(NSMaxX(e)-(NSWidth(row.bounds)-12))<1,[NSString stringWithFormat:@"In a %@-point window the rules button is at the right end of the first line of its choice: %@ / %@",width,NSStringFromRect(e),NSStringFromRect(m)]);
        Check([modern.cell cellSizeForBounds:NSMakeRect(0,0,NSWidth(m),CGFLOAT_MAX)].height<=NSHeight(m)+1,@"The LaTeX-aware choice shows its whole title beside the rules button");
    }
    [shell.window setContentSize:originalSize];[shell.window.contentView layoutSubtreeIfNeeded];
    TSIsolatedAppKitDefaults.values=[saved mutableCopy];[owner updateControlsFromUserDefaults:TSIsolatedAppKitDefaults];
    puts("PASS: both real spelling mode actions, no note, invalidation and retained child values");
}
