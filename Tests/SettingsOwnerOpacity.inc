#import "TSThemeFileStore.h"
@interface TSPreferences (OpacityRegression)
- (IBAction)NewStyleFromPrefs:(id)sender;
- (IBAction)EditingStyleChoice:(id)sender;
- (void)requestNameForThemeColors:(NSDictionary *)colors;
@end
static NSUInteger opacityWrites;
static IMP opacityOriginalWrite;
static NSDictionary *opacityMigrated;
static BOOL CountOpacityWrite(id store,SEL selector,NSDictionary *colors,NSString *title,NSError **error){
    opacityWrites++;return ((BOOL(*)(id,SEL,id,id,NSError **))opacityOriginalWrite)(store,selector,colors,title,error);
}
static void CaptureOpacityMigration(id owner,SEL selector,NSDictionary *colors){opacityMigrated=[colors copy];}
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
    puts("PASS: opacity sliders, exact RGB/alpha, one save/refresh, reload, disabled state and legacy migration");
}
