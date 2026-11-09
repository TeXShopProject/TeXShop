#import "TSThemeFileStore.h"
@interface TSPreferences (OpacityRegression)
- (IBAction)NewStyleFromPrefs:(id)sender;
- (IBAction)EditingStyleChoice:(id)sender;
- (void)requestNameForThemeColors:(NSDictionary *)colors;
@end
static NSLocale *opacityTestLocale;
static id OpacityLocale(id cls, SEL cmd) { return opacityTestLocale; }
static NSUInteger opacityWrites;
static IMP opacityOriginalWrite;
static NSDictionary *opacityMigrated;
static BOOL CountOpacityWrite(id store,SEL selector,NSDictionary *colors,NSString *title,NSError **error){
    opacityWrites++;return ((BOOL(*)(id,SEL,id,id,NSError **))opacityOriginalWrite)(store,selector,colors,title,error);
}
static void CaptureOpacityMigration(id owner,SEL selector,NSDictionary *colors){opacityMigrated=[colors copy];}
static NSUInteger opacityRejections;
static void TypeOpacity(NSTextField *field,NSString *text){
    [field selectText:nil];NSTextView *editor=(NSTextView *)field.currentEditor;
    Check(editor!=nil,@"Opacity field uses the AppKit field editor");
    [editor selectAll:nil];[editor insertText:text replacementRange:editor.selectedRange];
}
static void EndOpacity(NSTextField *field){[field.window makeFirstResponder:nil];}
static double StoredOpacity(TSPreferences *owner,NSString *key){return [[owner valueForKey:@"EditingColors"][key][3]doubleValue];}
static void CheckOpacityField(TSPreferences *owner,TSSettingsWindowController *shell,NSColorWell *well,NSArray *rgb,NSString *key,NSString *path){
    NSView *pane=[shell viewForCategoryIdentifier:TSSettingsCategoryAppearance];
    NSSlider *slider=(NSSlider *)Find(pane,[@"opacity." stringByAppendingString:well.identifier]);
    NSTextField *field=(NSTextField *)Find(pane,[@"opacity-value." stringByAppendingString:well.identifier]);
    Check(field!=nil && field.editable && [field.formatter isKindOfClass:TSOpacityFormatter.class] && field.controlSize==NSControlSizeSmall && [field.accessibilityLabel isEqual:slider.accessibilityLabel],@"Opacity has an editable whole-percentage field");
    TSOpacityFormatter *formatter=(TSOpacityFormatter *)field.formatter;
    formatter.rejectionHandler=^{opacityRejections++;};
    id value=nil;
    Check([formatter getObjectValue:&value forString:@"150" errorDescription:NULL] && [value integerValue]==100,@"Opacity entry above 100 is clamped to 100");
    Check([formatter getObjectValue:&value forString:@"\uFF16\uFF15" errorDescription:NULL] && [value integerValue]==65,@"Full-width opacity digits are accepted");
    for(NSString *bad in @[@"abc",@"-5",@"65.5",@"+3",@"6a"])Check(![formatter getObjectValue:&value forString:bad errorDescription:NULL],@"Opacity entry refuses letters, signs and decimals");
    // Start from a known fractional alpha, then exercise typed entry through the real field editor.
    well.color=[NSColor colorWithSRGBRed:[rgb[0]doubleValue] green:[rgb[1]doubleValue] blue:[rgb[2]doubleValue] alpha:0.1234];
    NSUInteger writes=opacityWrites;
    [field selectText:nil];EndOpacity(field);
    Check(opacityWrites==writes && fabs(StoredOpacity(owner,key)-[[owner valueForKey:@"EditingColors"][key][3]doubleValue])<1e-12 && fabs(well.color.alphaComponent-0.1234)<1e-9,@"Passing through the opacity field keeps the stored fractional alpha");
    struct {__unsafe_unretained NSString *text; double expected; BOOL rejected;} cases[]={
        {@"65",65,NO},{@"150",100,NO},{@" 42 ",42,NO},{@"\uFF16\uFF15",65,NO},{@"7",7,NO},{@"0",0,NO},
        {@"abc",-1,YES},{@"-5",-1,YES},{@"65.5",-1,YES},{@"9999",-1,YES},
    };
    for(NSUInteger i=0;i<sizeof(cases)/sizeof(cases[0]);i++){
        double before=slider.doubleValue;NSUInteger w=opacityWrites,r=opacityRejections;
        TypeOpacity(field,cases[i].text);EndOpacity(field);
        if(cases[i].rejected){
            Check(opacityRejections>r && opacityWrites==w && slider.doubleValue==before,@"Opacity entry refuses letters, signs and decimals");
            Check([field.stringValue isEqual:[NSString stringWithFormat:@"%ld",lround(before)]],@"Refused opacity entry shows the stored value again");
        } else {
            BOOL changed=lround(cases[i].expected)!=lround(before);
            NSArray *rgba=[owner valueForKey:@"EditingColors"][key];
            Check(fabs(slider.doubleValue-cases[i].expected)<1e-9 && [field.stringValue isEqual:[NSString stringWithFormat:@"%ld",lround(cases[i].expected)]],@"Typed opacity moves the slider and saves once");
            Check(opacityWrites==w+(changed?1:0) && fabs([rgba[3]doubleValue]-cases[i].expected/100)<1e-9,@"Typed opacity moves the slider and saves once");
            Check(fabs([rgba[0]doubleValue]-[rgb[0]doubleValue])<1e-6 && fabs([rgba[1]doubleValue]-[rgb[1]doubleValue])<1e-6 && fabs([rgba[2]doubleValue]-[rgb[2]doubleValue])<1e-6,@"Opacity action preserves RGB and changes only alpha");
            if(cases[i].expected==100)Check(opacityWrites==w+(changed?1:0),@"Opacity entry above 100 is clamped to 100");
        }
    }
    double before=slider.doubleValue;NSUInteger w=opacityWrites,r=opacityRejections;
    TypeOpacity(field,@"");EndOpacity(field);
    Check(opacityRejections>r && opacityWrites==w && slider.doubleValue==before && [field.stringValue isEqual:[NSString stringWithFormat:@"%ld",lround(before)]],@"Empty opacity entry is refused and shows the stored value");
    slider.doubleValue=30;[slider sendAction:slider.action to:slider.target];
    Check([field.stringValue isEqual:@"30"],@"Slider changes update the opacity field");
    well.enabled=NO;Check(!field.enabled && !slider.enabled,@"Disabled opacity disables its numeric field");
    w=opacityWrites;field.stringValue=@"80";[field sendAction:field.action to:field.target];
    Check(opacityWrites==w && [field.stringValue isEqual:@"30"],@"Disabled opacity disables its numeric field");well.enabled=YES;
    formatter.rejectionHandler=^{NSBeep();};
}
static void CheckOwnerOpacity(TSPreferences *owner,TSSettingsWindowController *shell,NSDictionary *base) {
    NSDictionary *defaults=[TSIsolatedAppKitDefaults.values copy],*editing=[owner valueForKey:@"EditingColors"],*last=[owner valueForKey:@"lastSavedEditingColors"];
    NSDictionary *savedLite=liteColors,*savedDark=darkColors;
    NSArray *keys=@[@"SourceAlpha",@"ConsoleAlpha",@"PreviewAlpha"];
    NSArray *outlets=@[@"SourceAlphaColorWell",@"ConsoleAlphaColorWell",@"PreviewAlphaColorWell"];
    [TSIsolatedAppKitDefaults setObject:@"LiteTheme" forKey:DefaultLiteThemeKey];
    [TSIsolatedAppKitDefaults setObject:@"DarkTheme" forKey:DefaultDarkThemeKey];
    [shell selectCategoryIdentifier:TSSettingsCategoryAppearance];
    NSMutableDictionary *theme=[base mutableCopy];
    for(NSUInteger i=0;i<3;i++)theme[keys[i]]=@[@0.12,@0.34,@0.56,@(0.1234+i*0.2)];
    theme[@"Title"]=@"OpacityFixture";
    NSString *path=[ColorPath stringByAppendingPathComponent:@"OpacityFixture.plist"];
    Check([theme writeToFile:path atomically:YES],@"Opacity uses a temporary theme file");
    NSPopUpButton *choice=[owner valueForKey:@"EditingStyle"];[choice addItemWithTitle:@"OpacityFixture"];[choice selectItemWithTitle:@"OpacityFixture"];
    [owner EditingStyleChoice:nil];
    Method write=class_getInstanceMethod(TSThemeFileStore.class,@selector(writeColors:title:error:));opacityOriginalWrite=method_setImplementation(write,(IMP)CountOpacityWrite);
    Method key=class_getInstanceMethod(NSWindow.class,@selector(isKeyWindow));IMP oldKey=method_setImplementation(key,(IMP)NavigationKey);navigationTestWindow=shell.window;navigationTestKey=YES;
    __block NSUInteger notices=0;
    id observer=[NSNotificationCenter.defaultCenter addObserverForName:SourceColorChangedNotification object:owner queue:nil usingBlock:^(NSNotification *note){
        notices++;Check([[NSDictionary dictionaryWithContentsOfFile:path]isEqual:[owner valueForKey:@"EditingColors"]],@"Opacity is saved before notifying open windows");
    }];
    for(NSUInteger i=0;i<3;i++){
        NSColorWell *well=[owner valueForKey:outlets[i]];
        NSSlider *slider=(NSSlider *)Find([shell viewForCategoryIdentifier:TSSettingsCategoryAppearance],[@"opacity." stringByAppendingString:well.identifier]);
        Check(slider && slider.minValue==0 && slider.maxValue==100 && slider.controlSize==NSControlSizeSmall && !slider.continuous && well.hidden,@"Three small opacity sliders replace the hidden color wells");
        Check(fabs(slider.doubleValue-[theme[keys[i]][3]doubleValue]*100)<1e-6,@"Loading a theme preserves fractional opacity without rounding");
        for(NSNumber *percent in @[@0,@12.34,@37,@85,@100]){
            NSUInteger writes=opacityWrites,notifications=notices;
            slider.doubleValue=percent.doubleValue;[slider sendAction:slider.action to:slider.target];
            NSArray *rgba=[owner valueForKey:@"EditingColors"][keys[i]];
            Check(fabs([rgba[0]doubleValue]-0.12)<1e-6 && fabs([rgba[1]doubleValue]-0.34)<1e-6 && fabs([rgba[2]doubleValue]-0.56)<1e-6 && fabs([rgba[3]doubleValue]-percent.doubleValue/100)<1e-6,@"Opacity action preserves RGB and changes only alpha");
            Check(opacityWrites==writes+1 && notices==notifications+1,@"One opacity action performs one theme save and one refresh");
            [owner EditingStyleChoice:nil];Check(fabs(slider.doubleValue-percent.doubleValue)<1e-6,@"Saved opacity reloads without drift");
        }
        well.enabled=NO;slider.doubleValue=42;NSUInteger writes=opacityWrites;[slider sendAction:slider.action to:slider.target];
        Check(!slider.enabled && slider.doubleValue==100 && opacityWrites==writes,@"Disabled opacity cannot write and restores its displayed value");well.enabled=YES;
    }
    CheckOpacityField(owner,shell,[owner valueForKey:outlets[0]],theme[keys[0]],keys[0],path);
    Method localeMethod=class_getClassMethod(NSLocale.class,@selector(currentLocale));
    IMP oldLocale=method_setImplementation(localeMethod,(IMP)OpacityLocale);
    for(NSString *localeID in @[@"de_DE",@"fr_FR",@"en_US"]){
        opacityTestLocale=[[NSLocale alloc]initWithLocaleIdentifier:localeID];
        NSColorWell *well=[owner valueForKey:outlets[0]];well.color=[well.color colorWithAlphaComponent:0.85];
        NSSlider *slider=(NSSlider *)Find([shell viewForCategoryIdentifier:TSSettingsCategoryAppearance],[@"opacity." stringByAppendingString:well.identifier]);
        NSTextField *field=[slider.superview valueForKey:@"field"];
        NSNumberFormatter *formatter=[NSNumberFormatter new];formatter.numberStyle=NSNumberFormatterPercentStyle;formatter.maximumFractionDigits=0;formatter.locale=opacityTestLocale;
        Check([field.stringValue isEqual:@"85"],@"Opacity field shows the whole percentage in every region");
        Check([slider.accessibilityValue isEqual:[formatter stringFromNumber:@0.85]],@"Opacity percentage follows the current regional format");
        if(![localeID isEqual:@"en_US"])Check([slider.accessibilityValue rangeOfCharacterFromSet:NSCharacterSet.whitespaceCharacterSet].location!=NSNotFound,@"German and French percentages include their localized spacing");
        Check([@"100" sizeWithAttributes:@{NSFontAttributeName:field.font}].width+8<=NSWidth(field.frame),@"Localized percentages fit their label width");
    }
    method_setImplementation(localeMethod,oldLocale);opacityTestLocale=nil;
    NSMutableDictionary *missing=[theme mutableCopy];for(NSString *key in keys)[missing removeObjectForKey:key];
    Check([missing writeToFile:path atomically:YES],@"Missing-alpha fixture is saved only in the temporary directory");
    BOOL loaded=YES;@try { [owner EditingStyleChoice:nil]; } @catch(NSException *exception){loaded=NO;}
    Check(loaded,@"Absent alpha opens without exception and displays full opacity");
    for(NSUInteger i=0;i<3;i++){
        NSColorWell *well=[owner valueForKey:outlets[i]];
        NSSlider *slider=(NSSlider *)Find([shell viewForCategoryIdentifier:TSSettingsCategoryAppearance],[@"opacity." stringByAppendingString:well.identifier]);
        Check(slider.doubleValue==100,@"Absent alpha opens without exception and displays full opacity");
        NSUInteger writes=opacityWrites;slider.doubleValue=65;[slider sendAction:slider.action to:slider.target];
        NSArray *rgba=[NSDictionary dictionaryWithContentsOfFile:path][keys[i]];
        Check(rgba.count==4 && fabs([rgba[3]doubleValue]-0.65)<1e-9 && opacityWrites==writes+1,@"Absent alpha is created and saved once on edit");
        [owner EditingStyleChoice:nil];Check(fabs(slider.doubleValue-65)<1e-9,@"Created alpha survives reload");
    }
    method_setImplementation(write,opacityOriginalWrite);method_setImplementation(key,oldKey);navigationTestWindow=nil;
    [NSNotificationCenter.defaultCenter removeObserver:observer];
    NSArray *legacy=@[SourceWindowAlphaKey,ConsoleWindowAlphaKey,PreviewWindowAlphaKey];
    for(NSUInteger i=0;i<3;i++)[TSIsolatedAppKitDefaults setDouble:0.17+0.22*i forKey:legacy[i]];
    Method migrate=class_getInstanceMethod(TSPreferences.class,@selector(requestNameForThemeColors:));IMP oldMigrate=method_setImplementation(migrate,(IMP)CaptureOpacityMigration);
    [owner NewStyleFromPrefs:nil];
    for(NSUInteger i=0;i<3;i++)Check(fabs([opacityMigrated[keys[i]][3]doubleValue]-(0.17+0.22*i))<1e-9,@"Legacy defaults migration preserves each window alpha");
    method_setImplementation(migrate,oldMigrate);opacityMigrated=nil;
    [choice selectItemAtIndex:0];[choice removeItemWithTitle:@"OpacityFixture"];
    TSIsolatedAppKitDefaults.values=[defaults mutableCopy];liteColors=savedLite;darkColors=savedDark;
    [owner setValue:editing forKey:@"EditingColors"];[owner setValue:last forKey:@"lastSavedEditingColors"];[owner FillInColorWells];
    puts("PASS: opacity sliders and numeric fields, exact RGB/alpha, one save/refresh, reload, disabled state and legacy migration");
}
