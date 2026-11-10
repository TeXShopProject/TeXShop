@interface TSPreferences (ThemeWellRegression)
- (NSColor *)editingColorForKey:(NSString *)key;
@end
static BOOL NoSharedColorPanel(id receiver,SEL selector){return NO;}
static BOOL SameThemeColor(NSColor *a,NSColor *b){
    a=[a colorUsingColorSpace:NSColorSpace.genericRGBColorSpace];b=[b colorUsingColorSpace:NSColorSpace.genericRGBColorSpace];
    return a && b && fabs(a.redComponent-b.redComponent)<0.001 && fabs(a.greenComponent-b.greenComponent)<0.001 && fabs(a.blueComponent-b.blueComponent)<0.001;
}
static NSColor *ThemeFixtureColor(NSArray *a){return [NSColor colorWithRed:[a[0]doubleValue] green:[a[1]doubleValue] blue:[a[2]doubleValue] alpha:1];}
static void CheckOwnerThemeWells(TSPreferences *owner,TSSettingsWindowController *shell,NSDictionary *base){
    NSArray *keys=@[@"SyntaxMarkerParen",@"SyntaxMarkerCurly",@"SyntaxMarkerSquare",@"explFunction",@"explVariable",@"explIntenseFunction",@"explIntenseVariable",@"explmykey",@"explmykeyArgument",@"explmsg"];
    NSArray *outlets=@[@"markerParenColorWell",@"markerCurlyColorWell",@"markerSquareColorWell",@"explFunctionColorWell",@"explVariableColorWell",@"explIntenseFunctionColorWell",@"explIntenseVariableColorWell",@"explmykeyColorWell",@"explmykeyArgumentColorWell",@"explmsgColorWell"];
    SEL actions[]={@selector(markerParenColorChanged:),@selector(markerCurlyColorChanged:),@selector(markerSquareColorChanged:),@selector(explFunctionColorChanged:),@selector(explVariableColorChanged:),@selector(explIntenseFunctionColorChanged:),@selector(explIntenseVariableColorChanged:),@selector(explmykeyColorChanged:),@selector(explmykeyArgumentColorChanged:),@selector(explmsgColorChanged:)};
    NSDictionary *savedEditing=[owner valueForKey:@"EditingColors"],*savedLast=[owner valueForKey:@"lastSavedEditingColors"],*savedLite=liteColors,*savedDark=darkColors;
    NSAppearance *savedAppearance=shell.window.appearance;BOOL savedMojave=atLeastMojave;atLeastMojave=YES;
    NSMutableDictionary *decoy=[base mutableCopy];for(NSString *key in keys)decoy[key]=@[@0.4,@0.4,@0.9,@1];liteColors=darkColors=decoy;
    [owner setValue:nil forKey:@"lastSavedEditingColors"]; // persistence boundary is exercised by theme-store tests
    Method keyMethod=class_getInstanceMethod(NSWindow.class,@selector(isKeyWindow)),panelMethod=class_getClassMethod(NSColorPanel.class,@selector(sharedColorPanelExists));
    IMP oldKey=method_setImplementation(keyMethod,(IMP)NavigationKey),oldPanel=method_setImplementation(panelMethod,(IMP)NoSharedColorPanel);
    navigationTestWindow=shell.window;
    TSColorSupport *colors=[TSColorSupport sharedInstance];
    for(NSAppearanceName appearance in @[NSAppearanceNameAqua,NSAppearanceNameDarkAqua]){
        shell.window.appearance=[NSAppearance appearanceNamed:appearance];BOOL dark=[appearance isEqual:NSAppearanceNameDarkAqua];
        for(NSUInteger variant=0;variant<3;variant++){
            NSMutableDictionary *theme=[base mutableCopy];for(NSString *key in keys)[theme removeObjectForKey:key];
            theme[@"SyntaxMarker"]=@[@0.1,@0.6,@0.5,@1];
            if(variant==0)for(NSUInteger i=0;i<keys.count;i++)theme[keys[i]]=@[@(0.05+0.08*i),@(0.9-0.07*i),@(0.3+0.05*i),@1];
            if(variant==2)[theme removeObjectForKey:@"SyntaxMarker"];
            [owner setValue:[theme mutableCopy] forKey:@"EditingColors"];
            // A complete theme requires its base marker. The missing-marker case
            // exercises the optional-key resolver directly, as the legacy test did.
            if(variant<2)[owner FillInColorWells];
            else for(NSUInteger i=0;i<keys.count;i++)[[owner valueForKey:outlets[i]]setColor:[owner editingColorForKey:keys[i]]];
            for(NSUInteger i=0;i<keys.count;i++){
                NSString *key=keys[i];NSArray *a=theme[key] ?: (i<3?theme[@"SyntaxMarker"]:nil);
                NSColor *expected=a?ThemeFixtureColor(a):(dark?[colors darkColorWithKey:key]:[colors liteColorWithKey:key]);
                NSColorWell *well=[owner valueForKey:outlets[i]];
                Check(SameThemeColor(well.color,expected),[NSString stringWithFormat:@"Actual edited-theme well %@ variant %lu %@",key,(unsigned long)variant,appearance]);
                Check([[owner valueForKey:@"EditingColors"]isEqual:theme],@"Filling wells leaves missing keys absent");
                navigationTestKey=NO;well.color=NSColor.systemRedColor;
                Check([NSApp sendAction:actions[i] to:owner from:well],@"Actual color action exists");
                Check([[owner valueForKey:@"EditingColors"]isEqual:theme] && SameThemeColor(well.color,expected),@"Inactive color action restores its effective color without storing an override");
                navigationTestKey=YES;NSColor *pick=ThemeFixtureColor(@[@0.33,@0.77,@0.11,@1]);well.color=pick;
                [NSApp sendAction:actions[i] to:owner from:well];
                NSDictionary *changed=[owner valueForKey:@"EditingColors"];
                NSColor *savedPick=[pick colorUsingColorSpace:NSColorSpace.genericRGBColorSpace];
                NSArray *stored=changed[key];
                Check(stored.count==4 && fabs([stored[0]doubleValue]-savedPick.redComponent)<0.001 && fabs([stored[1]doubleValue]-savedPick.greenComponent)<0.001 && fabs([stored[2]doubleValue]-savedPick.blueComponent)<0.001,@"Active color action stores the selected RGB value");
                NSMutableSet *expectedKeys=[NSMutableSet setWithArray:theme.allKeys];[expectedKeys addObject:key];
                Check([[NSSet setWithArray:changed.allKeys]isEqual:expectedKeys],@"Color action only materializes the edited key");
                [owner setValue:[theme mutableCopy] forKey:@"EditingColors"];
            }
        }
        for(NSUInteger explicitCount=0;explicitCount<=3;explicitCount++){
            NSMutableDictionary *theme=[base mutableCopy];for(NSUInteger i=0;i<3;i++)[theme removeObjectForKey:keys[i]];
            theme[@"SyntaxMarker"]=@[@0.1,@0.6,@0.5,@1];
            for(NSUInteger i=0;i<explicitCount;i++)theme[keys[i]]=@[@0.2,@0.3,@0.4,@1];
            [owner setValue:[theme mutableCopy] forKey:@"EditingColors"];[owner FillInColorWells];navigationTestKey=YES;
            NSColorWell *marker=[owner valueForKey:@"SyntaxMarkerColorWell"];marker.color=ThemeFixtureColor(@[@0.7,@0.15,@0.05,@1]);[owner SyntaxMarkerColorChanged:marker];
            NSDictionary *changed=[owner valueForKey:@"EditingColors"];
            Check([[NSSet setWithArray:changed.allKeys]isEqual:[NSSet setWithArray:theme.allKeys]],@"Marker action preserves absent bracket overrides");
            for(NSUInteger i=0;i<3;i++)Check(SameThemeColor([[owner valueForKey:outlets[i]]color],ThemeFixtureColor(theme[keys[i]] ?: changed[@"SyntaxMarker"])),@"Marker action refreshes only inheriting bracket wells");
        }
    }
    // Colors drawn opaque offer no opacity; colors whose opacity is used keep it.
    {
        NSMutableDictionary *translucent=[(savedEditing ?: liteColors) mutableCopy];
        for(NSString *key in @[@"EditorBackground",@"EditorText",@"LogBackground",@"SyntaxComment",@"ImageBackground"])translucent[key]=@[@0.2,@0.4,@0.6,@0.4];
        [owner setValue:translucent forKey:@"EditingColors"];[owner FillInColorWells];
        for(NSString *outlet in @[@"SourceBackgroundColorWell",@"SourceTextColorWell",@"LogBackgroundColorWell",@"SyntaxCommentColorWell",@"markerParenColorWell",@"XMLTagColorWell",@"explFunctionColorWell"]){
            NSColorWell *well=[owner valueForKey:outlet];
            Check(well!=nil && !well.supportsAlpha && fabs(well.color.alphaComponent-1)<0.001,[NSString stringWithFormat:@"%@ shows an opaque color without opacity",outlet]);
        }
        NSColorWell *image=[owner valueForKey:@"ImageBackgroundColorWell"];
        Check(image.supportsAlpha && fabs(image.color.alphaComponent-0.4)<0.001,@"Image copy background keeps its opacity");
        for(NSString *outlet in @[@"SourceAlphaColorWell",@"PreviewDirectSyncColorWell",@"EditorFlashColorWell",@"EditorHighlightZenkakuSymbolBackgroundColorWell"])
            Check([[owner valueForKey:outlet] supportsAlpha],[NSString stringWithFormat:@"%@ keeps opacity",outlet]);
        NSColorWell *cursor=[owner valueForKey:@"BlockCursorColorWell"];
        Check(cursor==nil || !cursor.supportsAlpha,@"Block cursor color offers no opacity");
    }
    method_setImplementation(keyMethod,oldKey);method_setImplementation(panelMethod,oldPanel);navigationTestWindow=nil;
    liteColors=savedLite;darkColors=savedDark;atLeastMojave=savedMojave;shell.window.appearance=savedAppearance;
    [owner setValue:savedEditing forKey:@"EditingColors"];[owner setValue:savedLast forKey:@"lastSavedEditingColors"];[owner FillInColorWells];
    puts("PASS: real theme wells/actions, ten keys, three fallback variants, two appearances, inherited markers");
}
