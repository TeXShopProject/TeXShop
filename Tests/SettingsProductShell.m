// SPDX-License-Identifier: GPL-2.0-or-later
// Real TSPreferences, its localized nibs, shell and lazy shortcut provider.
#import "TestAppKitIsolation.h"
#import "TSPreferences.h"
#import "TSPreferences+Panes.h"
#import "TSSettingsWindowController.h"
#import "TSShortcutPaneController.h"
#import "TSKeyboardShortcuts.h"
#import "TSDockIconController.h"
#import "TSDockIcon.h"
#import "globals.h"
#import "TSPreferenceProfile.h"
#import "TSPreferenceInput.h"
#import "TSSourceFormatRanges.h"
#import "TSColorSupport.h"
#import "TSSettingsChangeNote.h"
#import "TSPrefPaneLayout.h"
#import "TSPreferenceKey.h"
#import "TSSpellingLanguage.h"
@interface TSPreferences (Probe)
- (BOOL)prepareSettingsWindow;
- (void)FillInColorWells;
- (void)configurePreferenceInputs;
- (void)updateControlsFromUserDefaults:(NSUserDefaults *)defaults;
- (void)applyPreferenceProfile:(TSPreferenceProfile *)proposal font:(NSFont *)font;
- (void)finishPreferencesForTermination;
- (void)showPreferences:(id)sender;
- (BOOL)commitPreferenceField:(NSControl *)field showError:(BOOL)show reflect:(BOOL)reflect;
- (void)controlTextDidChange:(NSNotification *)note;
- (BOOL)control:(NSControl *)control textShouldEndEditing:(NSText *)editor;
- (void)refreshInheritedBracketColorWells;
@property(strong) TSSettingsWindowController *settingsController;
@end
@interface HelpDocuments:NSObject @end
@implementation HelpDocuments @end
static NSUInteger spellRefreshes;
@interface TSSpellSupport:NSObject @end
@implementation TSSpellSupport
+ (void)preferencesDidChange { spellRefreshes++; }
@end
@interface TSSettingsWindowController (Probe)
- (CGFloat)tableView:(NSTableView *)table heightOfRow:(NSInteger)row;
- (NSView *)tableView:(NSTableView *)table viewForTableColumn:(NSTableColumn *)column row:(NSInteger)row;
@property(readonly) NSSplitViewController *splitController;
@property(readonly) NSTableView *categoryTable;
@property(readonly) NSScrollView *contentScroll;
@property(readonly) NSSearchField *settingsSearchField;
@end
@interface ProductDockTile:NSObject
@property NSSize size;
@property(strong) NSView *contentView;
@property(copy) NSString *badgeLabel;
@end
@implementation ProductDockTile
- (void)display {}
@end
static ProductDockTile *testDockTile;
static id IsolatedProductDock(id object,SEL selector){return testDockTile;}
static NSBundle *fixture;
static id MainBundle(id object,SEL selector){return fixture;}
static void Check(BOOL yes,NSString *reason){if(!yes){fprintf(stderr,"FAIL: %s\n",reason.UTF8String);exit(1);}}
void TSTestUnexpectedCriticalSheet(NSString *title,NSString *defaultButton,NSString *alternateButton,NSString *otherButton,NSWindow *window,id delegate,SEL didEnd,SEL didDismiss,void *context,NSString *format,...) { Check(NO,@"Encoding change must not present a critical alert sheet"); }
// Dictionary choices: language names for the checker's identifiers, identifiers
// stored, automatic detection in every localization, and stored values from
// earlier versions selected. The checker's language itself is never changed.
static void CheckSpellingDictionary(TSPreferences *owner,NSPopUpButton *dictionary) {
 NSDictionary *saved=[TSIsolatedAppKitDefaults.values copy];
 NSArray<NSString *> *languages=NSSpellChecker.sharedSpellChecker.availableLanguages;
 NSString *before=NSSpellChecker.sharedSpellChecker.language;
 [TSIsolatedAppKitDefaults setBool:YES forKey:spellingAutomaticDefaultKey];
 [owner updateSettingsCategory:TSSettingsCategorySpelling fromDefaults:TSIsolatedAppKitDefaults];
 Check(languages.count>0 && dictionary.numberOfItems==(NSInteger)languages.count+1 && [dictionary itemAtIndex:0].representedObject==nil && dictionary.indexOfSelectedItem==0,@"Dictionary lists the automatic choice and every checker language");
 for(NSUInteger i=0;i<languages.count;i++){
  NSMenuItem *item=[dictionary itemAtIndex:(NSInteger)i+1];
  Check([item.representedObject isEqual:languages[i]] && [item.toolTip isEqual:languages[i]],@"Each dictionary choice keeps the checker's identifier");
  Check([item.title hasPrefix:TSSpellingLanguageDisplayName(languages[i])] && ![item.title isEqual:languages[i]],@"Each dictionary choice shows the language's name");
 }
 NSString *english=TSSpellingLanguageMatching(@"en",languages);
 if(english){
  Check([[dictionary itemAtIndex:[dictionary indexOfItemWithRepresentedObject:english]].title isEqual:@"English (United States)"],@"The checker's en is shown as U.S. English");
 }
 __block NSUInteger posted=0;
 id observer=[NSNotificationCenter.defaultCenter addObserverForName:TSSpellingLanguageChangedNotification object:owner queue:nil usingBlock:^(NSNotification *note){posted++;}];
 NSString *chosen=english ?: languages.firstObject;
 [dictionary selectItemAtIndex:[dictionary indexOfItemWithRepresentedObject:chosen]];
 Check([NSApp sendAction:dictionary.action to:dictionary.target from:dictionary],@"Dictionary popup action is connected");
 Check(![TSIsolatedAppKitDefaults boolForKey:spellingAutomaticDefaultKey] && [[TSIsolatedAppKitDefaults stringForKey:spellingLanguageDefaultKey] isEqual:chosen] && posted==1,@"A dictionary choice stores its identifier and tells open documents once");
 [dictionary selectItemAtIndex:0];[NSApp sendAction:dictionary.action to:dictionary.target from:dictionary];
 Check([TSIsolatedAppKitDefaults boolForKey:spellingAutomaticDefaultKey] && posted==2,@"The automatic choice chooses automatic detection in this localization");
 [NSNotificationCenter.defaultCenter removeObserver:observer];
 [TSIsolatedAppKitDefaults setBool:NO forKey:spellingAutomaticDefaultKey];
 NSMutableDictionary *expected=[NSMutableDictionary dictionary];
 if(english){expected[@"en_US"]=english;expected[@"en-US"]=english;expected[@"English"]=english;}
 expected[chosen]=chosen;
 for(NSString *stored in expected){
  [TSIsolatedAppKitDefaults setObject:stored forKey:spellingLanguageDefaultKey];
  [owner updateSettingsCategory:TSSettingsCategorySpelling fromDefaults:TSIsolatedAppKitDefaults];
  Check([dictionary.selectedItem.representedObject isEqual:expected[stored]] && dictionary.numberOfItems==(NSInteger)languages.count+1,@"A stored identifier selects the checker's language");
 }
 [TSIsolatedAppKitDefaults setObject:NSLocalizedString(@"Automatic Language",@"") forKey:spellingLanguageDefaultKey];
 [owner updateSettingsCategory:TSSettingsCategorySpelling fromDefaults:TSIsolatedAppKitDefaults];
 Check(dictionary.indexOfSelectedItem==0,@"A stored automatic title from an earlier beta is automatic detection");
 for(NSUInteger pass=0;pass<2;pass++){
  [TSIsolatedAppKitDefaults setObject:@"tlh_XX" forKey:spellingLanguageDefaultKey];
  [owner updateSettingsCategory:TSSettingsCategorySpelling fromDefaults:TSIsolatedAppKitDefaults];
  Check(dictionary.numberOfItems==(NSInteger)languages.count+2 && [dictionary.selectedItem.representedObject isEqual:@"tlh_XX"] && dictionary.indexOfSelectedItem==dictionary.numberOfItems-1,@"A dictionary that is not installed stays the visible choice once");
 }
 [NSApp sendAction:dictionary.action to:dictionary.target from:dictionary];
 Check([[TSIsolatedAppKitDefaults stringForKey:spellingLanguageDefaultKey] isEqual:@"tlh_XX"] && ![TSIsolatedAppKitDefaults boolForKey:spellingAutomaticDefaultKey],@"Choosing the missing dictionary again keeps it");
 Check([NSSpellChecker.sharedSpellChecker.language isEqual:before],@"Settings never change the checker's language");
 TSIsolatedAppKitDefaults.values=[saved mutableCopy];
 [owner updateSettingsCategory:TSSettingsCategorySpelling fromDefaults:TSIsolatedAppKitDefaults];
 puts("PASS: dictionary language names, stored identifiers, automatic choice, earlier stored values and missing dictionaries");
}
static NSView *Find(NSView *view,NSString *identifier){if([view.identifier isEqual:identifier])return view;for(NSView *child in view.subviews){NSView *found=Find(child,identifier);if(found)return found;}return nil;}
static void Save(NSView *v,NSString *path){[v layoutSubtreeIfNeeded];[v display];NSBitmapImageRep *rep=[v bitmapImageRepForCachingDisplayInRect:v.bounds];[v cacheDisplayInRect:v.bounds toBitmapImageRep:rep];NSImage *image=[[NSImage alloc]initWithSize:v.bounds.size];[image lockFocus];[v.effectiveAppearance performAsCurrentDrawingAppearance:^{[NSColor.windowBackgroundColor setFill];NSRectFill(NSMakeRect(0,0,v.bounds.size.width,v.bounds.size.height));}];NSImage *capture=[[NSImage alloc]initWithSize:v.bounds.size];[capture addRepresentation:rep];[capture drawInRect:NSMakeRect(0,0,v.bounds.size.width,v.bounds.size.height) fromRect:NSZeroRect operation:NSCompositingOperationSourceOver fraction:1];[image unlockFocus];NSData *tiff=image.TIFFRepresentation;if(tiff==nil)abort();NSBitmapImageRep *opaque=[[NSBitmapImageRep alloc]initWithData:tiff];[[opaque representationUsingType:NSBitmapImageFileTypePNG properties:@{}]writeToFile:path atomically:YES];}
static void SaveNote(TSSettingsWindowController *shell,NSView *row,NSString *directory,NSString *name) {
 if(!directory)return;
 for(NSString *appearance in @[NSAppearanceNameAqua,NSAppearanceNameDarkAqua]){
  shell.window.appearance=[NSAppearance appearanceNamed:appearance];[shell.window.contentView layoutSubtreeIfNeeded];
  Save(row,[directory stringByAppendingPathComponent:[NSString stringWithFormat:@"notice-%@-%@.png",name,appearance]]);
 }
}
#include "SettingsOwnerEditing.inc"
#include "SettingsOwnerEffects.inc"
#include "SettingsOwnerPresentation.inc"
#include "SettingsOwnerInvisible.inc"
#include "SettingsOwnerRuntime.inc"
#include "SettingsOwnerSpelling.inc"
#include "SettingsSidebar.m"
#include "SettingsOwnerLifecycle.inc"
#include "SettingsOwnerSearch.inc"
#include "SettingsOwnerThemeWells.inc"
#include "SettingsOwnerOpacity.inc"
#include "SettingsVisibleText.inc"
int main(int argc,char **argv){@autoreleasepool{
 TSInstallAppKitIsolation();[NSApplication sharedApplication];[NSApp setActivationPolicy:NSApplicationActivationPolicyProhibited];
 testDockTile=[ProductDockTile new];testDockTile.size=NSMakeSize(128,128);testDockTile.badgeLabel=@"7";
 TSReplaceTestMethod(class_getInstanceMethod(NSApplication.class,@selector(dockTile)),(IMP)IsolatedProductDock);
 fixture=[NSBundle bundleWithPath:@(argv[1])];
 ColorPath=[fixture.resourcePath stringByAppendingPathComponent:@"Themes"];[NSFileManager.defaultManager createDirectoryAtPath:ColorPath withIntermediateDirectories:YES attributes:nil error:NULL];
 for(NSString *name in @[@"LiteTheme",@"DarkTheme"])[NSFileManager.defaultManager copyItemAtPath:[fixture pathForResource:name ofType:@"plist" inDirectory:@"Themes"] toPath:[ColorPath stringByAppendingPathComponent:[name stringByAppendingString:@".plist"]] error:NULL];Check(fixture!=nil,@"Localized product fixture loads");
 method_setImplementation(class_getClassMethod(NSBundle.class,@selector(mainBundle)),(IMP)MainBundle);
 NSMenu *main=[NSMenu new],*commands=[NSMenu new];NSMenuItem *top=[[NSMenuItem alloc]initWithTitle:@"Commands" action:NULL keyEquivalent:@""];top.submenu=commands;[main addItem:top];
 for(NSString *title in @[@"Typeset",@"Save",@"Print"]){NSMenuItem *item=[[NSMenuItem alloc]initWithTitle:title action:@selector(description) keyEquivalent:@""];item.identifier=[@"TSShortcut.test." stringByAppendingString:title];[commands addItem:item];}NSApp.mainMenu=main;
 [[TSKeyboardShortcuts sharedController]startObservingMenu];
 NSDictionary *factory=[NSDictionary dictionaryWithContentsOfURL:[fixture URLForResource:@"FactoryDefaults" withExtension:@"plist" subdirectory:@"Defaults"]];Check(factory.count>100,@"Factory defaults fixture is complete");[TSIsolatedAppKitDefaults registerDefaults:factory];
 [TSIsolatedAppKitDefaults setObject:[NSArchiver archivedDataWithRootObject:[NSFont userFontOfSize:12]] forKey:DocumentFontKey];
 TSSettingsRememberLaunchValue(AutoSaveEnabledKey,@([TSIsolatedAppKitDefaults boolForKey:AutoSaveEnabledKey]));TSSettingsRememberLaunchValue(FindMethodKey,@([TSIsolatedAppKitDefaults integerForKey:FindMethodKey]));
 TSPreferences *owner=[TSPreferences new];Check([owner prepareSettingsWindow],@"Production preference owner prepares its own window");[owner configurePreferenceInputs];[owner updateControlsFromUserDefaults:TSIsolatedAppKitDefaults];
 // Populate the production theme wells from a bundled theme; user theme files
 // and settings are neither read nor written for the comparison screenshots.
 NSDictionary *theme=[NSDictionary dictionaryWithContentsOfURL:[fixture URLForResource:@"LiteTheme" withExtension:@"plist" subdirectory:@"Themes"]];Check(theme.count>10,@"Bundled theme fixture loads");[owner setValue:[theme mutableCopy] forKey:@"EditingColors"];
 for(NSString *name in @[@"LiteStyle",@"DarkStyle",@"EditingStyle"]){NSPopUpButton *menu=[owner valueForKey:name];[menu removeAllItems];[menu addItemsWithTitles:@[@"LiteTheme",@"DarkTheme"]];[menu selectItemAtIndex:[name isEqual:@"DarkStyle"]?1:0];}
 [owner FillInColorWells];
 Check([factory[AutoSaveEnabledKey] isEqual:@"YES"] && ![[owner valueForKey:@"keepBackupButton"]isEnabled],@"Factory string YES disables backup at first opening");
 TSSettingsWindowController *shell=owner.settingsController;Check(shell.categoryIdentifiers.count==10,@"Ten approved categories");
 // Each category refresh is independent; repeated refresh cannot persist values.
 NSArray<NSArray<NSString *> *> *refreshCases=@[
  @[@"general",@"MakeEmptyDocument",@"openEmptyButton"],
  @[@"documents",@"AutomaticUTF8MACtoUTF8Conversion",@"convertUTFButton"],
  @[@"editor",@"LineNumberEnabled",@"lineNumberButton"],
  @[@"spelling",@"AutomaticSpellingCorrectionEnabled",@"autoSpellCorrectButton"],
  @[@"preview",@"NoScrollPageTurn",@"scrollPageTurnButton"],
  @[@"typesetting",@"SavePSEnabled",@"savePSButton"],
  @[@"console",@"SameFontForMacro",@"macroButton"],
  @[@"keyboard",@"AutoCompleteEnabled",@"autoCompleteButton"],
  @[@"updates",@"SUScheduledCheckInterval",@"sparkleAutomaticButton"]
 ];
 // Sparkle's Boolean key is independent of its interval key.
 NSMutableArray *reviewedCases=[refreshCases mutableCopy];reviewedCases[8]=@[@"updates",SparkleAutomaticUpdateKey,@"sparkleAutomaticButton"];
 for(NSArray<NSString *> *entry in reviewedCases){
  NSString *category=entry[0],*key=entry[1];id cell=[owner valueForKey:entry[2]];Check(cell!=nil,@"Refresh fixture names a real outlet");
  id original=[TSIsolatedAppKitDefaults objectForKey:key];BOOL wanted=![[cell valueForKey:@"state"] boolValue];
  [TSIsolatedAppKitDefaults setBool:wanted forKey:key];NSDictionary *baseline=[TSIsolatedAppKitDefaults dictionaryRepresentation];
  [owner updateSettingsCategory:[category isEqual:@"general"]?@"documents":@"general" fromDefaults:TSIsolatedAppKitDefaults];
  Check([[cell valueForKey:@"state"]boolValue]!=wanted,@"Unrelated category refresh preserves this category's controls");
  [owner updateSettingsCategory:category fromDefaults:TSIsolatedAppKitDefaults];
  Check([[cell valueForKey:@"state"]boolValue]==wanted,@"Category refresh reads its effective defaults");
  Check([[TSIsolatedAppKitDefaults dictionaryRepresentation]isEqual:baseline],@"Refreshing a category writes no settings");
  if(original)[TSIsolatedAppKitDefaults setObject:original forKey:key];else[TSIsolatedAppKitDefaults removeObjectForKey:key];
  [owner updateSettingsCategory:category fromDefaults:TSIsolatedAppKitDefaults];
 }
 // Prerelease updates are refreshed from defaults and do not depend on automatic checks.
 {
  NSButton *prerelease=[owner valueForKey:@"sparklePrereleaseButton"];Check(prerelease!=nil,@"The prerelease switch has its owner");
  id originalPrerelease=[TSIsolatedAppKitDefaults objectForKey:SparklePrereleaseUpdatesKey],originalAutomatic=[TSIsolatedAppKitDefaults objectForKey:SparkleAutomaticUpdateKey];
  for(NSNumber *on in @[@YES,@NO])for(NSNumber *automatic in @[@YES,@NO]){
   [TSIsolatedAppKitDefaults setBool:on.boolValue forKey:SparklePrereleaseUpdatesKey];[TSIsolatedAppKitDefaults setBool:automatic.boolValue forKey:SparkleAutomaticUpdateKey];
   [owner updateSettingsCategory:TSSettingsCategoryUpdates fromDefaults:TSIsolatedAppKitDefaults];
   Check((prerelease.state==NSControlStateValueOn)==on.boolValue && prerelease.enabled,[NSString stringWithFormat:@"Prerelease switch shows %@ and stays enabled with automatic checks %@",on,automatic]);
  }
  if(originalPrerelease)[TSIsolatedAppKitDefaults setObject:originalPrerelease forKey:SparklePrereleaseUpdatesKey];else[TSIsolatedAppKitDefaults removeObjectForKey:SparklePrereleaseUpdatesKey];
  if(originalAutomatic)[TSIsolatedAppKitDefaults setObject:originalAutomatic forKey:SparkleAutomaticUpdateKey];else[TSIsolatedAppKitDefaults removeObjectForKey:SparkleAutomaticUpdateKey];
  [owner updateSettingsCategory:TSSettingsCategoryUpdates fromDefaults:TSIsolatedAppKitDefaults];
 }
 NSPopUpButton *dictionary=[owner valueForKey:@"dictionaryPopup"];
 NSArray *dictionaryTitles=dictionary.itemTitles;
 [dictionary addItemWithTitle:@"Unavailable dictionary fixture"];
 for(NSUInteger pass=0;pass<3;pass++)[owner updateSettingsCategory:TSSettingsCategorySpelling fromDefaults:TSIsolatedAppKitDefaults];
 Check([dictionary.itemTitles isEqual:dictionaryTitles],@"Repeated refresh does not append duplicate dictionary choices");
 Check([dictionary.itemTitles.firstObject isEqual:NSLocalizedString(@"Automatic Language",@"")],@"Dictionary automatic choice uses the current language");
 CheckSpellingDictionary(owner,dictionary);
 for(NSNumber *value in @[@NO,@YES]){
  [TSIsolatedAppKitDefaults setBool:value.boolValue forKey:SourceAndPreviewInSameWindowKey];
  [TSIsolatedAppKitDefaults setBool:value.boolValue forKey:SwitchSidesKey];
  [owner updateSettingsCategory:TSSettingsCategoryGeneral fromDefaults:TSIsolatedAppKitDefaults];
  Check([[owner valueForKey:@"useOneWindowButton"]state]==value.boolValue && [[owner valueForKey:@"useTwoWindowsButton"]state]!=value.boolValue,@"Both detached window-style radio cells refresh");
  Check([[owner valueForKey:@"useRightSourceButton"]state]==value.boolValue && [[owner valueForKey:@"useLeftSourceButton"]state]!=value.boolValue,@"Both detached source-side radio cells refresh");
 }
 [TSIsolatedAppKitDefaults setObject:factory[SourceAndPreviewInSameWindowKey] ?: @NO forKey:SourceAndPreviewInSameWindowKey];
 [TSIsolatedAppKitDefaults setObject:factory[SwitchSidesKey] ?: @NO forKey:SwitchSidesKey];
 [owner updateControlsFromUserDefaults:TSIsolatedAppKitDefaults];
 NSData *dependencyData=[NSData dataWithContentsOfURL:[fixture URLForResource:@"SettingsDependencies" withExtension:@"json"]];
 NSDictionary *dependencyLedger=[NSJSONSerialization JSONObjectWithData:dependencyData options:0 error:NULL];Check([dependencyLedger[@"rules"]count]==14,@"Independent dependency ledger loads");
 for(NSDictionary *rule in dependencyLedger[@"rules"]){
  NSString *key=rule[@"key"],*category=rule[@"category"];id original=[TSIsolatedAppKitDefaults objectForKey:key];
  for(NSNumber *value in rule[@"values"]){
   [TSIsolatedAppKitDefaults setObject:value forKey:key];[owner updateSettingsCategory:category fromDefaults:TSIsolatedAppKitDefaults];
   id normalized=[rule[@"value_kind"]isEqual:@"boolean"]?@([value boolValue]):@([value integerValue]);
   BOOL enabled=[rule[@"enabled_values"]containsObject:normalized];
   for(NSString *outlet in rule[@"outlets"]){NSControl *control=[owner valueForKey:outlet];Check(control!=nil && control.enabled==enabled,[NSString stringWithFormat:@"Ledger dependency %@=%@ -> %@",key,value,outlet]);}
   NSArray *labelRows=rule[@"label_rows"] ?: ([rule[@"label_row"]isKindOfClass:NSString.class]?@[rule[@"label_row"]]:@[]);
   for(NSString *labelRow in labelRows){
    NSView *row=Find([shell viewForCategoryIdentifier:category],labelRow);NSTextField *label=(NSTextField *)Find(row,@"label.catalog-row");
    Check(label!=nil && label.enabled==enabled,[NSString stringWithFormat:@"Dependent row %@ follows %@=%@",labelRow,key,value]);
    Check([label.textColor isEqual:enabled?NSColor.labelColor:NSColor.disabledControlTextColor],@"Dependent name uses the actual enabled or disabled text color");
    if(argc>2){
     [shell selectCategoryIdentifier:category];
     SaveNote(shell,row,@(argv[2]),[NSString stringWithFormat:@"dependency-%@-%@-%@",key,value,labelRow]);
    }
   }
  }
  if(original)[TSIsolatedAppKitDefaults setObject:original forKey:key];else[TSIsolatedAppKitDefaults removeObjectForKey:key];
  [owner updateSettingsCategory:category fromDefaults:TSIsolatedAppKitDefaults];
 }

 [[TSDockIconController sharedController]installInPreferencesPane:[shell viewForCategoryIdentifier:TSSettingsCategoryAppearance]];
 [shell beginSession];NSDictionary *saved=[TSIsolatedAppKitDefaults dictionaryRepresentation];
 for(NSNumber *windowWidth in @[@900,@1040])for(NSNumber *sidebarWidth in @[@190,@330,@190,@260]){
  [shell.window setContentSize:NSMakeSize(windowWidth.doubleValue,780)];[shell.splitController.splitView setPosition:sidebarWidth.doubleValue ofDividerAtIndex:0];[shell.window.contentView layoutSubtreeIfNeeded];
  NSSplitViewItem *sidebar=shell.splitController.splitViewItems.firstObject;
  Check(sidebar.minimumThickness==190 && sidebar.maximumThickness==330 && !sidebar.canCollapse,@"Sidebar limits preserve the approved usable width");
  CGFloat feasible=MIN(sidebarWidth.doubleValue,windowWidth.doubleValue-700);
  Check(fabs(NSWidth(sidebar.viewController.view.frame)-feasible)<2,[NSString stringWithFormat:@"Sidebar width %.1f requested %@, window %@",NSWidth(sidebar.viewController.view.frame),sidebarWidth,windowWidth]);
  Check(NSMinX(shell.settingsSearchField.frame)>=0 && NSMaxX(shell.settingsSearchField.frame)<=NSWidth(sidebar.viewController.view.bounds),@"Search field fits narrow sidebar");
  Check(shell.categoryTable.rowHeight==30 && shell.categoryTable.headerView==nil,@"Sidebar uses compact rows with no table heading");
  NSScrollView *listScroll=shell.categoryTable.enclosingScrollView;NSClipView *listClip=listScroll.contentView;
  Check(NSWidth(shell.categoryTable.frame)<=NSWidth(listClip.bounds)+0.5,[NSString stringWithFormat:@"Sidebar list %.1f fits its %.1f-point column, sidebar %@, window %@",NSWidth(shell.categoryTable.frame),NSWidth(listClip.bounds),sidebarWidth,windowWidth]);
  Check(!listScroll.hasHorizontalScroller && listScroll.horizontalScrollElasticity==NSScrollElasticityNone,@"Sidebar list has no horizontal scroller or horizontal bounce");
  NSRect shifted=listClip.bounds;shifted.origin.x=60;
  Check(fabs([listClip constrainBoundsRect:shifted].origin.x)<0.5,[NSString stringWithFormat:@"Sidebar list cannot be scrolled sideways (%.1f), sidebar %@, window %@",[listClip constrainBoundsRect:shifted].origin.x,sidebarWidth,windowWidth]);
  for(NSInteger row=0;row<shell.categoryTable.numberOfRows;row++){CGFloat height=[shell tableView:shell.categoryTable heightOfRow:row];Check(height==8 || (height>=30 && height<=42),@"Category spacing uses compact one-line or necessary two-line rows");}
 }
 [shell.window setContentSize:NSMakeSize(1040,780)];[shell.splitController.splitView setPosition:220 ofDividerAtIndex:0];
 NSMutableArray *visibleText=[NSMutableArray array];
 for(NSString *category in shell.categoryIdentifiers){
  Check([shell selectCategoryIdentifier:category],@"Production delegate permits category navigation");[shell.window.contentView layoutSubtreeIfNeeded];
  NSView *pane=[category isEqual:TSSettingsCategoryKeyboard]?[[shell valueForKey:@"keyboardPane"] view]:[shell viewForCategoryIdentifier:category];
  Check(Find(pane,@"category.header")!=nil,@"Real pane preserves its overview card");
  if([category isEqual:TSSettingsCategoryKeyboard]){
   for(NSString *group in @[@"group.bindings",@"group.completion",@"group.shortcuts"]){NSView *section=Find(pane,group);Check(section!=nil && !section.hidden,@"Real keyboard provider keeps all three sections visible");}
   NSView *shortcuts=Find(pane,@"group.shortcuts");
   Check(Find(shortcuts,@"shortcut.commands")!=nil && Find(shortcuts,@"shortcut.restore-all")!=nil,@"Real menu shortcut table and actions are installed inside the third card");
  }
  for(NSString *appearance in @[NSAppearanceNameAqua,NSAppearanceNameDarkAqua]){
   shell.window.appearance=[NSAppearance appearanceNamed:appearance];[shell.window.contentView layoutSubtreeIfNeeded];
   if(argc>2){NSString *directory=@(argv[2]);Save(shell.window.contentView,[directory stringByAppendingPathComponent:[NSString stringWithFormat:@"shell-%@-%@.png",category,appearance]]);Save(pane,[directory stringByAppendingPathComponent:[NSString stringWithFormat:@"full-%@-%@.png",category,appearance]]);}
   Check(!shell.window.visible,@"No test window is ordered");
  }
  CollectSettingsVisibleText(pane,category,visibleText);
  printf("PANE %s %.1f %.1f\n",category.UTF8String,NSWidth(pane.frame),NSHeight(pane.frame));
  if(argc>2 || [fixture.bundlePath.lastPathComponent isEqual:@"ja.bundle"]){
   NSView *originalParent=pane.superview;NSArray *originalConstraints=[originalParent.constraints filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(NSLayoutConstraint *c,NSDictionary *bindings){return c.firstItem==pane || c.secondItem==pane;}]];
   [pane removeFromSuperview];NSWindow *comparison=[[NSWindow alloc]initWithContentRect:NSMakeRect(0,0,570,900) styleMask:NSWindowStyleMaskBorderless backing:NSBackingStoreBuffered defer:NO];
   NSView *host=comparison.contentView;[host addSubview:pane];pane.translatesAutoresizingMaskIntoConstraints=NO;
   NSArray *geometry=@[[pane.widthAnchor constraintEqualToConstant:570],[pane.leadingAnchor constraintEqualToAnchor:host.leadingAnchor],[pane.topAnchor constraintEqualToAnchor:host.topAnchor]];[NSLayoutConstraint activateConstraints:geometry];
   for(NSString *appearance in @[NSAppearanceNameAqua,NSAppearanceNameDarkAqua]){
    comparison.appearance=[NSAppearance appearanceNamed:appearance];[host layoutSubtreeIfNeeded];
    if(argc>2)Save(pane,[@(argv[2]) stringByAppendingPathComponent:[NSString stringWithFormat:@"comparison-%@-%@.png",category,appearance]]);
   }
   printf("COMPARISON %s %.1f %.1f\n",category.UTF8String,NSWidth(pane.frame),NSHeight(pane.frame));
   if([fixture.bundlePath.lastPathComponent isEqual:@"ja.bundle"]){
    NSDictionary *heights=[NSJSONSerialization JSONObjectWithData:[NSData dataWithContentsOfURL:[fixture URLForResource:@"SettingsHeightReference" withExtension:@"json"]] options:0 error:NULL];
    double reference=[heights[@"categories"][category][@"height"]doubleValue];
    Check(reference>0 && NSHeight(pane.frame)<=reference*[heights[@"maximum_ratio"]doubleValue],@"Content height is within 1.15 of the independent approved mockup");
   }

   [NSLayoutConstraint deactivateConstraints:geometry];[pane removeFromSuperview];[originalParent addSubview:pane];[NSLayoutConstraint activateConstraints:originalConstraints];[shell.window.contentView layoutSubtreeIfNeeded];
  }

 }
 NSString *visiblePath=NSProcessInfo.processInfo.environment[@"TS_SETTINGS_VISIBLE_TEXT_PATH"];
 if(visiblePath.length){
  Check([[NSJSONSerialization dataWithJSONObject:visibleText options:NSJSONWritingPrettyPrinted error:NULL] writeToFile:visiblePath atomically:YES],@"Visible wording inventory is written");
 }
 if(argc>2){
  [shell.splitController.splitView setPosition:190 ofDividerAtIndex:0];[shell.window.contentView layoutSubtreeIfNeeded];
  NSUInteger queryIndex=0;
  for(NSString *query in @[@"utf",@"自動",@"Dock",[fixture localizedStringForKey:@"appearance" value:nil table:@"SettingsCategories"]]){
   Check([shell setSettingsSearchQuery:query],@"Audit search query is accepted");
   shell.settingsSearchField.stringValue=query;
   NSMutableArray *items=[NSMutableArray array];for(TSSettingsSearchResult *result in shell.searchResults)[items addObject:@{@"category":result.category,@"target":result.targetIdentifier ?: @"",@"title":result.title}];
   [[NSJSONSerialization dataWithJSONObject:items options:NSJSONWritingPrettyPrinted error:NULL]writeToFile:[@(argv[2]) stringByAppendingPathComponent:[NSString stringWithFormat:@"search-%lu.json",(unsigned long)queryIndex]] atomically:YES];
   for(NSString *appearance in @[NSAppearanceNameAqua,NSAppearanceNameDarkAqua]){
    shell.window.appearance=[NSAppearance appearanceNamed:appearance];[shell.window.contentView layoutSubtreeIfNeeded];
    Save(shell.window.contentView,[@(argv[2]) stringByAppendingPathComponent:[NSString stringWithFormat:@"search-%lu-%@.png",(unsigned long)queryIndex,appearance]]);
   }
   queryIndex++;
  }
  NSArray *colorTargets=@[@"settings.L8Q-Ov-EVr",@"settings.Kx3-n3-dsv",@"settings.FoL-zy-obh",@"settings.hCM-4U-XkM"];
  for(NSUInteger index=0;index<colorTargets.count;index++){
   NSString *name=[fixture localizedStringForKey:[NSString stringWithFormat:@"catalog.appearance.2.0.item.%lu",(unsigned long)index] value:nil table:@"SettingsCategories"];
   [shell setSettingsSearchQuery:name];shell.settingsSearchField.stringValue=name;ChooseOwnerResult(shell,colorTargets[index]);
   for(NSString *appearance in @[NSAppearanceNameAqua,NSAppearanceNameDarkAqua]){
    shell.window.appearance=[NSAppearance appearanceNamed:appearance];[shell.window.contentView layoutSubtreeIfNeeded];
    Save(shell.window.contentView,[@(argv[2]) stringByAppendingPathComponent:[NSString stringWithFormat:@"color-result-%lu-%@.png",(unsigned long)index,appearance]]);
   }
  }
  [shell setSettingsSearchQuery:@""];
 }
 NSMutableDictionary *current=[[TSIsolatedAppKitDefaults dictionaryRepresentation]mutableCopy];[current removeObjectForKey:TSSettingsSelectedCategoryKey];NSMutableDictionary *before=[saved mutableCopy];[before removeObjectForKey:TSSettingsSelectedCategoryKey];Check([current isEqual:before],@"Opening and navigating changes only remembered category");
 [shell selectCategoryIdentifier:TSSettingsCategoryDocuments];
 id windowManager=[NSClassFromString(@"TSWindowManager") performSelector:@selector(sharedInstance)];
 NSWindow *sourceWindow=[[NSWindow alloc]initWithContentRect:NSMakeRect(0,0,200,200) styleMask:NSWindowStyleMaskBorderless backing:NSBackingStoreBuffered defer:NO];
 sourceWindow.releasedWhenClosed=NO;
 [windowManager setValue:sourceWindow forKey:@"activeTextWindow"];
 NSPopUpButton *encoding=[owner valueForKey:@"defaultEncodeMatrix"];
 [encoding selectItemWithTag:NSMacOSRomanStringEncoding];[owner encodingChanged:encoding];
 Check(!Find(Find([shell viewForCategoryIdentifier:TSSettingsCategoryDocuments],@"row.catalog.documents.0.0"),@"settings.change-note").hidden,@"Real encoding action shows an inline note with an open source");
 SaveNote(shell,Find([shell viewForCategoryIdentifier:TSSettingsCategoryDocuments],@"row.catalog.documents.0.0"),argc>2?@(argv[2]):nil,@"encoding");
 [windowManager setValue:nil forKey:@"activeTextWindow"];
 TSDockIconController *dock=[TSDockIconController sharedController];
 [dock installInPreferencesPane:[shell viewForCategoryIdentifier:TSSettingsCategoryAppearance]];
 Check([[dock valueForKey:@"buttons"] count]==0,@"Themes has no Dock group");
 [dock installInPreferencesPane:[shell viewForCategoryIdentifier:TSSettingsCategoryGeneral]];
 NSArray<NSButton *> *dockButtons=[dock valueForKey:@"buttons"];Check(dockButtons.count==5,@"General installs exactly five Dock choices once");
 if(argc>2){[shell selectCategoryIdentifier:TSSettingsCategoryGeneral];Save([shell viewForCategoryIdentifier:TSSettingsCategoryGeneral],[@(argv[2]) stringByAppendingPathComponent:@"general-with-dock.png"]);}
 NSArray *expectedDockYears=@[@"2000–2001",@"2001–2013",@"2013–2014",@"2014–2026",@"2026–"];
 for(NSUInteger index=0;index<dockButtons.count;index++){
  NSTextField *caption=(NSTextField *)Find(dockButtons[index].superview,@"dock.years");
  Check(dockButtons[index].superview.subviews.count==2 && dockButtons[index].accessibilityLabel.length>0 && [caption.stringValue isEqual:expectedDockYears[index]],@"Dock options have an accessible image and the approved year-only caption");
  Check(TSDockIconImage(fixture,TSDockIconNames()[index])!=nil,@"Dock artwork exists");[dockButtons[index]performClick:nil];
  Check([[TSIsolatedAppKitDefaults stringForKey:TSDockIconKey]isEqual:TSDockIconNames()[index]],@"Actual Dock action saves only in memory");
  Check((testDockTile.contentView!=nil)==(index!=4)&&[testDockTile.badgeLabel isEqual:@"7"],@"Actual Dock drawing preserves the badge on the isolated tile");
  [sourceWindow close];Check([[dock valueForKey:@"selection"]isEqual:TSDockIconNames()[index]],@"Closing a document window preserves the running Dock selection");
  TSDockIconController *fresh=[[TSDockIconController alloc]initWithBundle:fixture defaults:TSIsolatedAppKitDefaults];[fresh restoreSavedIcon];
  Check([[fresh valueForKey:@"selection"]isEqual:TSDockIconNames()[index]],@"A new controller restores the saved choice");
 }
 [TSIsolatedAppKitDefaults setObject:@"invalid" forKey:TSDockIconKey];[dock restoreSavedIcon];Check(testDockTile.contentView==nil,@"Unknown Dock selection falls back to the standard icon");
 // The real profile application path must clear transient warnings and retain
 // restart warnings; no confirmation sheet is presented by this test.
 [shell selectCategoryIdentifier:TSSettingsCategorySpelling];
 NSButton *spellingButton=[owner valueForKey:@"texAwareSpellCheckButton"];
 spellingButton.state=[TSIsolatedAppKitDefaults boolForKey:@"TeXAwareSpellChecking"]?NSControlStateValueOff:NSControlStateValueOn;
 [owner texAwareSpellCheckPressed:spellingButton];
 NSView *spellingNote=Find(Find([shell viewForCategoryIdentifier:TSSettingsCategorySpelling],@"row.catalog.spelling.1.0"),@"settings.change-note");
 Check(!spellingNote.hidden,@"Actual spelling action shows its warning before profile replacement");
 SaveNote(shell,spellingNote.superview.superview,argc>2?@(argv[2]):nil,@"spelling");
 NSMutableDictionary *replacement=[[TSIsolatedAppKitDefaults dictionaryRepresentation]mutableCopy];
 replacement[AutoSaveEnabledKey]=@(![TSIsolatedAppKitDefaults boolForKey:AutoSaveEnabledKey]);
 NSInteger findMethodBefore=[TSIsolatedAppKitDefaults integerForKey:FindMethodKey];
 replacement[FindMethodKey]=@(findMethodBefore==2?0:2); // a profile keeps the find method (plan §5), whatever the file says
 replacement[EncodingKey]=@"MacOSRoman";replacement[PdfMagnificationKey]=@1.75;
 NSFont *profileFont=[NSFont userFontOfSize:12];
 TSPreferenceProfile *profile=[[TSPreferenceProfile alloc]initWithProfile:replacement documentFont:[NSArchiver archivedDataWithRootObject:profileFont] registeredDefaults:factory];
 Check(profile!=nil,@"Actual profile proposal is valid");[owner applyPreferenceProfile:profile font:profileFont];
 Check(spellingNote.hidden,@"Actual profile replacement clears a visible transient warning");
 for(NSArray *entry in @[@[TSSettingsCategoryPreview,@"row.catalog.preview.0.2"],@[TSSettingsCategoryDocuments,@"row.catalog.documents.0.0"]])Check(Find(Find([shell viewForCategoryIdentifier:entry[0]],entry[1]),@"settings.change-note").hidden,@"Profile application never creates transient zoom or encoding warnings");
 Check([TSIsolatedAppKitDefaults integerForKey:FindMethodKey]==findMethodBefore,@"A profile keeps the find method");
 Check(Find(Find([shell viewForCategoryIdentifier:TSSettingsCategoryEditor],@"row.catalog.editor.7.0"),@"settings.change-note").hidden,@"A profile never shows the find method's restart warning");
 NSArray *restartRows=@[@[TSSettingsCategoryDocuments,@"row.catalog.documents.1.0"]];
 for(NSArray *entry in restartRows)Check(!Find(Find([shell viewForCategoryIdentifier:entry[0]],entry[1]),@"settings.change-note").hidden,@"Actual profile differences show restart warnings");
 for(NSArray *entry in restartRows){[shell selectCategoryIdentifier:entry[0]];SaveNote(shell,Find([shell viewForCategoryIdentifier:entry[0]],entry[1]),argc>2?@(argv[2]):nil,@"autosave-restart");}
 [shell selectCategoryIdentifier:TSSettingsCategoryGeneral];[shell endSession];[shell beginSession];
 for(NSArray *entry in restartRows)Check(!Find(Find([shell viewForCategoryIdentifier:entry[0]],entry[1]),@"settings.change-note").hidden,@"Profile restart warnings survive category transition and reopening");
 CheckOwnerPresentation(shell);
 CheckOwnerEffects(owner,factory,theme);
 CheckOwnerEditing(owner,shell);
 CheckOwnerInvisible(owner,shell);
 CheckOwnerRuntime(owner);
 CheckOwnerSpelling(owner,shell);
 CheckOwnerNavigation(owner,shell);
 CheckOwnerLifecycle(owner,shell);
 CheckOwnerSearch(owner,shell);
 CheckOwnerThemeWells(owner,shell,theme);
 CheckOwnerOpacity(owner,shell,theme);
 // Complete production editing callbacks: untouched focus, Return, validation and teardown.
 NSMapTable *inputRules=[owner valueForKey:@"inputRules"];Check(inputRules.count==19,@"All nineteen production input rules are installed");
 NSTextField *tabsField=[owner valueForKey:@"tabIndentField"],*gsField=[owner valueForKey:@"gsBinPathField"],*zoomField=[owner valueForKey:@"magTextField"];
 [TSIsolatedAppKitDefaults setObject:@"" forKey:GSBinPath];gsField.stringValue=@"";
 tabsField.stringValue=@"20";[owner controlTextDidChange:[NSNotification notificationWithName:NSControlTextDidChangeNotification object:tabsField]];
 Check([owner control:tabsField textShouldEndEditing:[NSText new]] && [TSIsolatedAppKitDefaults integerForKey:tabsKey]==20,@"Actual Return commits tab width");
 Check([owner commitPreferenceField:gsField showError:NO reflect:YES] && [[TSIsolatedAppKitDefaults stringForKey:GSBinPath]isEqual:@""],@"Untouched empty GS path cannot acquire the previously committed tab value");
 [TSIsolatedAppKitDefaults setDouble:1.255 forKey:PdfMagnificationKey];zoomField.stringValue=@"126";
 Check([owner commitPreferenceField:zoomField showError:NO reflect:YES] && [TSIsolatedAppKitDefaults doubleForKey:PdfMagnificationKey]==1.255,@"Untouched display rounding cannot change saved magnification");
 [owner controlTextDidChange:[NSNotification notificationWithName:NSControlTextDidChangeNotification object:gsField]];
 Check(![owner commitPreferenceField:gsField showError:NO reflect:NO],@"An edited empty required path fails validation without a sheet");
 TSPreferenceEditing *editing=[owner valueForKey:@"inputEditing"];[editing restoreField:gsField rule:[inputRules objectForKey:gsField] defaults:TSIsolatedAppKitDefaults];
 Check([gsField.stringValue isEqual:@""] && [owner commitPreferenceField:gsField showError:NO reflect:YES],@"Actual owner recovers the GS field's own saved value");
 // The open-PDF condition is an injected service fixture; the real field
 // commit and red-note view are used without creating a visible PDF window.
 [shell selectCategoryIdentifier:TSSettingsCategoryPreview];
 TSSettingsChangeNotes *changeNotes=[owner valueForKey:@"settingsChangeNotes"];changeNotes.hasPDFWindow=^BOOL{return YES;};
 zoomField.stringValue=@"150";[owner controlTextDidChange:[NSNotification notificationWithName:NSControlTextDidChangeNotification object:zoomField]];
 Check([owner control:zoomField textShouldEndEditing:[NSText new]],@"Return commits actual zoom field");
 NSView *zoomRow=Find([shell viewForCategoryIdentifier:TSSettingsCategoryPreview],@"row.catalog.preview.0.2");Check(!Find(zoomRow,@"settings.change-note").hidden,@"Actual zoom commit shows a note with the open-PDF fixture");
 SaveNote(shell,zoomRow,argc>2?@(argv[2]):nil,@"pdf-zoom");
 // Bracket wells use the edited dictionary, never the separately applied theme.
 NSMutableDictionary *editedTheme=[theme mutableCopy];editedTheme[@"SyntaxMarker"]=@[@0.1,@0.6,@0.5,@1];
 for(NSString *key in @[@"SyntaxMarkerParen",@"SyntaxMarkerCurly",@"SyntaxMarkerSquare"])[editedTheme removeObjectForKey:key];
 [owner setValue:editedTheme forKey:@"EditingColors"];[owner refreshInheritedBracketColorWells];
 for(NSString *name in @[@"markerParenColorWell",@"markerCurlyColorWell",@"markerSquareColorWell"]){NSColorWell *well=[owner valueForKey:name];NSColor *rgb=[well.color colorUsingColorSpace:NSColorSpace.genericRGBColorSpace];Check(fabs(rgb.redComponent-[[NSColor colorWithRed:0.1 green:0.6 blue:0.5 alpha:1]colorUsingColorSpace:NSColorSpace.genericRGBColorSpace].redComponent)<0.001 && fabs(rgb.greenComponent-[[NSColor colorWithRed:0.1 green:0.6 blue:0.5 alpha:1]colorUsingColorSpace:NSColorSpace.genericRGBColorSpace].greenComponent)<0.001,@"Actual detached bracket wells inherit the edited marker");}
 Check(editedTheme[@"SyntaxMarkerParen"]==nil,@"Refreshing inherited wells does not materialize saved overrides");
 // Apply all nine shipped profiles through the unmodified production transaction.
 NSArray<NSString *> *profileFiles=[NSFileManager.defaultManager contentsOfDirectoryAtPath:[fixture.resourcePath stringByAppendingPathComponent:@"Profiles"] error:NULL];
 Check(profileFiles.count==9,@"Nine shipped profiles are present");
 __block NSMutableArray<NSString *> *effects=[NSMutableArray array];
 id token=[NSNotificationCenter.defaultCenter addObserverForName:nil object:owner queue:nil usingBlock:^(NSNotification *note){[effects addObject:note.name];Check(note.userInfo==nil,@"Profile notifications contain no transient theme dictionary");}];
 for(NSString *file in profileFiles){
  NSDictionary *values=[NSDictionary dictionaryWithContentsOfFile:[[fixture.resourcePath stringByAppendingPathComponent:@"Profiles"]stringByAppendingPathComponent:file]];
  TSPreferenceProfile *proposal=[[TSPreferenceProfile alloc]initWithProfile:values documentFont:[NSArchiver archivedDataWithRootObject:profileFont] registeredDefaults:factory];Check(proposal!=nil,@"Each shipped profile validates");
  [owner applyPreferenceProfile:proposal font:profileFont];
  Check([[owner valueForKey:@"keepBackupButton"]isEnabled]==![TSIsolatedAppKitDefaults boolForKey:AutoSaveEnabledKey],@"Every shipped profile applies autosave dependency using its effective Boolean");
  Check(editorCanAddBrackets==[TSIsolatedAppKitDefaults boolForKey:EditorCanAddBracketsKey],@"Real profile refresh updates the process-wide copy");
  [effects removeAllObjects];[owner applyPreferenceProfile:proposal font:profileFont];Check(effects.count==0,@"Unchanged profile emits no runtime notifications");
  for(NSString *key in @[AlwaysHighlightEnabledKey,ShowIndicatorForMoveEnabledKey,HighlightContentEnabledKey,BeepEnabledKey,FlashBackgroundEnabledKey,CheckBraceEnabledKey,CheckBracketEnabledKey,CheckSquareBracketEnabledKey,CheckParenEnabledKey,MakeatletterEnabledKey,expl3SyntaxColoringKey,ShowInvisibleCharactersEnabledKey]){
   [TSIsolatedAppKitDefaults setBool:![TSIsolatedAppKitDefaults boolForKey:key] forKey:key];[effects removeAllObjects];[owner applyPreferenceProfile:proposal font:profileFont];
   Check([effects containsObject:@"NeedsForRecolorNotification"],[NSString stringWithFormat:@"Profile sends recolor for changed %@",key]);
  }
  Check(![effects containsObject:@"MagnificationChangedNotification"],@"Profile leaves current PDF magnification to document state");
 }
 [NSNotificationCenter.defaultCenter removeObserver:token];
 [TSIsolatedAppKitDefaults setObject:@"round" forKey:TSDockIconKey];[dock restoreSavedIcon];
 NSUInteger oldThemeGeneration=[[owner valueForKey:@"themeOperationGeneration"]unsignedIntegerValue],oldEngineGeneration=[[owner valueForKey:@"enginePathSearchGeneration"]unsignedIntegerValue];
 [owner finishPreferencesForTermination];
 Check([[owner valueForKey:@"themeOperationGeneration"]unsignedIntegerValue]>oldThemeGeneration && [[owner valueForKey:@"enginePathSearchGeneration"]unsignedIntegerValue]>oldEngineGeneration,@"Actual termination invalidates stale theme and engine completions");
 Check(editing.editedField==nil,@"Actual termination clears edited-field ownership");
 Check([[TSIsolatedAppKitDefaults stringForKey:TSDockIconKey]isEqual:@"round"],@"Preference termination preserves the saved Dock choice for next launch");
 Check([[owner valueForKey:@"endingPreferences"]boolValue] && ![[owner valueForKey:@"ownsFontPanel"]boolValue],@"Actual termination releases preference editing ownership");
 if(argc>2)WriteWordingReview(shell,@(argv[2]));
 [shell endSession];Check(!shell.window.visible,@"Closing session stays headless");
 puts("PASS: actual owner, complete localized shell, real keyboard provider, sidebar width limits and inert navigation");
}return 0;}
