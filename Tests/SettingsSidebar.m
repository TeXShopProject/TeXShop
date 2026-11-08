// Exercise the settings shell with real localized nibs and memory-only state.
#import <Cocoa/Cocoa.h>
#import "TestAppKitIsolation.h"
#import "TSSettingsWindowController.h"
#import "TSShortcutPaneController.h"
#import "TSPrefPaneController.h"
#import "TSPrefFooterController.h"
@interface TSSettingsWindowController (Testing)
@property (strong, readonly) NSTableView *categoryTable;
@property (strong, readonly) NSSegmentedControl *navigationControl;
@property (strong, readonly) NSScrollView *contentScroll;
- (void)navigate:(NSSegmentedControl *)sender;
@end
static NSString *shellPath;
static BOOL testKeyWindow;
static BOOL restoreFrame;
static NSRect savedFrame;
static BOOL smallScreen;
static BOOL largeScreen;
static IMP originalVisibleFrame;
static NSRect VisibleFrame(NSScreen *screen, SEL selector) {
 return smallScreen ? NSMakeRect(0,0,800,600) : largeScreen ? NSMakeRect(0,0,2560,1600) : ((NSRect (*)(id,SEL))originalVisibleFrame)(screen,selector);
}
static BOOL RestoreFrame(NSWindow *window, SEL selector, NSString *name) {
 if (restoreFrame && [name isEqual:@"SettingsSidebarWindow"]) [window setFrame:savedFrame display:NO];
 return YES;
}
static NSEvent *Key(NSString *text){return [NSEvent keyEventWithType:NSEventTypeKeyDown location:NSZeroPoint modifierFlags:0 timestamp:0 windowNumber:0 context:nil characters:text charactersIgnoringModifiers:text isARepeat:NO keyCode:0];}
static NSWindow *testSheet;
static BOOL IsKey(id self,SEL selector){return testKeyWindow;}
static NSWindow *Sheet(id self,SEL selector){return testSheet;}
static void Check(BOOL yes,NSString *message){if(!yes){fprintf(stderr,"FAIL: %s\n",message.UTF8String);exit(1);}}
static NSData *ReadNib(NSString *path) {NSData *data=[NSData dataWithContentsOfFile:path];if(data==nil) abort();return data;}
static NSString *Argument(const char *value) {NSString *text=[NSString stringWithUTF8String:value];if(text==nil) abort();return text;}
@interface Segment:NSSegmentedControl
@property NSInteger testSegment;
@end
@implementation Segment
- (NSInteger)selectedSegment {return self.testSegment;}
@end
@interface TestController:TSSettingsWindowController @end
@implementation TestController
- (void)loadWindow {
 NSNib *nib=[[NSNib alloc]initWithNibData:ReadNib(shellPath) bundle:nil];
 NSArray *objects=nil;Check([nib instantiateWithOwner:self topLevelObjects:&objects],@"shell XIB loads");
}
@end
static NSBundle *paneBundle;
static TSMemoryDefaults *fixtureDefaults;
@interface Owner:NSObject<TSSettingsWindowDelegate,NSObject> { @public NSWindow *_prefsWindow; }
@property NSArray<TSPrefPaneController *> *preferencePanes;
@property TSSettingsWindowController *settingsController;
@property NSMutableDictionary *outlets;
@property BOOL valid;
@property (strong) NSMapTable *inputRules;
@property (strong) NSControl *errorField;
@property NSUInteger commits,fonts;
@end
@interface Owner (FixturePanes)
- (NSArray<TSPrefPaneController *> *)makeSettingsPanes;
@end
@implementation Owner
// PRODUCTION_PREPARE
- (void)setValue:(id)value forUndefinedKey:(NSString *)key {if(value)self.outlets[key]=value;}
// PRODUCTION_VALIDATE
// PRODUCTION_FINISH
- (BOOL)commitPreferenceField:(NSControl *)field showError:(BOOL)showError reflect:(BOOL)reflect {
 if(!self.valid && self.errorField) [_prefsWindow makeFirstResponder:self.errorField];
 return self.valid;
}
- (void)releasePreferencePanels { self.commits++; }
- (BOOL)tabView:(NSTabView *)tabView shouldSelectTabViewItem:(NSTabViewItem *)item { return [self settingsMayChangeCategory]; }
- (void)settingsChangeFont:(NSFontManager *)sender {self.fonts++;}
@end
@interface EditingField:NSTextField @end
@implementation EditingField
- (NSText *)currentEditor { return [NSText new]; }
@end
static NSDictionary *HostPanes(NSArray<TSPrefPaneController *> *panes) {
 NSMutableDictionary *result=[NSMutableDictionary dictionary];
 for(TSPrefPaneController *pane in panes) if(pane.categoryIdentifier.length)result[pane.categoryIdentifier]=pane;
 return result;
}
static NSView *Footer(NSArray<TSPrefPaneController *> *panes) { for(TSPrefPaneController *pane in panes)if([pane isKindOfClass:TSPrefFooterController.class])return pane.view;abort(); }
@implementation Owner (FixturePanes)
- (NSArray<TSPrefPaneController *> *)makeSettingsPanes {
 NSArray *names=@[@"Source",@"Editor",@"Preview",@"Console",@"Typesetting",@"Engines",@"MiscOne",@"MiscTwo",@"Themes",@"Footer",@"ThemeName"];
 NSArray *ids=@[@"source",@"editor",@"preview",@"console",@"typesetting",@"engines",@"misc-1",@"misc-2",@"themes"];
 NSMutableArray *result=[NSMutableArray array];
 for(NSUInteger index=0;index<names.count;index++){
  Class cls=NSClassFromString([NSString stringWithFormat:@"TSPref%@Controller",names[index]]);
  TSPrefPaneController *pane=[[cls alloc]initWithNibName:[@"Settings" stringByAppendingString:names[index]] bundle:paneBundle];
  Check(pane.view!=nil,@"shared pane loads");if(index<ids.count)pane.categoryIdentifier=ids[index];[result addObject:pane];
 }
 return result;
}
@end
static void SaveImage(NSView *v,NSString *path){[v layoutSubtreeIfNeeded];[v display];NSBitmapImageRep *rep=[v bitmapImageRepForCachingDisplayInRect:v.bounds];[v cacheDisplayInRect:v.bounds toBitmapImageRep:rep];NSImage *image=[[NSImage alloc]initWithSize:v.bounds.size];[image lockFocus];[v.effectiveAppearance performAsCurrentDrawingAppearance:^{[NSColor.windowBackgroundColor setFill];NSRectFill(NSMakeRect(0,0,v.bounds.size.width,v.bounds.size.height));}];NSImage *capture=[[NSImage alloc]initWithSize:v.bounds.size];[capture addRepresentation:rep];[capture drawInRect:NSMakeRect(0,0,v.bounds.size.width,v.bounds.size.height) fromRect:NSZeroRect operation:NSCompositingOperationSourceOver fraction:1];[image unlockFocus];NSData *tiff=image.TIFFRepresentation;if(tiff==nil)abort();NSBitmapImageRep *opaque=[[NSBitmapImageRep alloc]initWithData:tiff];[[opaque representationUsingType:NSBitmapImageFileTypePNG properties:@{}]writeToFile:path atomically:YES];}
int main(int argc,char **argv){@autoreleasepool{
 TSInstallAppKitIsolation();TSReplaceTestMethod(class_getInstanceMethod(NSWindow.class,@selector(setFrameAutosaveName:)),(IMP)RestoreFrame);[NSApplication sharedApplication];
 Method visibleMethod=class_getInstanceMethod(NSScreen.class,@selector(visibleFrame));
 Check(visibleMethod!=NULL,@"screen method exists");
 if(visibleMethod!=NULL) originalVisibleFrame=method_setImplementation(visibleMethod,(IMP)VisibleFrame);
 class_addMethod(TSSettingsWindow.class,@selector(isKeyWindow),(IMP)IsKey,"B@:");
 class_addMethod(TSSettingsWindow.class,@selector(attachedSheet),(IMP)Sheet,"@@:");shellPath=@(argv[1]);
 TSSettingsNavigationHistory *h=[TSSettingsNavigationHistory new];[h resetWithIdentifier:@"a"];
 Check(h.count==1 && !h.backIdentifier && !h.forwardIdentifier,@"initial history");
 [h visitIdentifier:@"b"];[h visitIdentifier:@"c"];[h goBack];Check([h.currentIdentifier isEqual:@"b"] && [h.forwardIdentifier isEqual:@"c"],@"back/forward");
 [h visitIdentifier:@"d"];Check(!h.forwardIdentifier && h.count==3,@"new navigation discards forward history");
 [h visitIdentifier:@"d"];Check(h.count==3,@"same category is not appended");
 for(int i=0;i<60;i++)[h visitIdentifier:[NSString stringWithFormat:@"%d",i]];Check(h.count==50,@"history limit");
 for(int i=0;i<60;i++)[h goBack];Check([h.currentIdentifier isEqual:@"10"],@"oldest entries evicted");
 for(int a=3;a<argc;a++){
  paneBundle=[NSBundle bundleWithPath:Argument(argv[a])];fixtureDefaults=[TSMemoryDefaults new];
  Owner *integration=[Owner new];integration.outlets=[NSMutableDictionary new];integration.valid=YES;
  restoreFrame=NO;smallScreen=(a==3);
  Check([integration prepareSettingsWindow],@"production prepare succeeds");[integration.settingsController beginSession];
  Check(integration->_prefsWindow==integration.settingsController.window,@"production owner targets new window");
  if(a==3){
   Check(NSWidth(integration->_prefsWindow.frame)<=800 && NSHeight(integration->_prefsWindow.frame)<=600,@"initial window fits a small screen");
  }
  smallScreen=NO;
  if(a==3){
   [integration->_prefsWindow.contentView layoutSubtreeIfNeeded];
   NSSize extent=integration.settingsController.contentScroll.contentSize, pane=integration.settingsController.contentScroll.documentView.frame.size;
   fprintf(stderr,"INITIAL viewport %.0fx%.0f pane %.0fx%.0f\n",extent.width,extent.height,pane.width,pane.height);
   Check(extent.height>0 && pane.height>extent.height,@"small screen uses a scrollable pane");
  }
  if(a==3){
   largeScreen=YES;
   Owner *large=[Owner new];large.outlets=[NSMutableDictionary new];large.valid=YES;
   Check([large prepareSettingsWindow],@"large screen production prepare succeeds");[large.settingsController beginSession];
   [large->_prefsWindow.contentView layoutSubtreeIfNeeded];
   NSSize extent=large.settingsController.contentScroll.contentSize, pane=large.settingsController.contentScroll.documentView.frame.size;
   Check(extent.height>0 && pane.height>0,@"large screen has a usable scrollable viewport");
   largeScreen=NO;
  }
  Check(integration.preferencePanes.count==11 && [integration.settingsController viewForCategoryIdentifier:@"source"].window==integration->_prefsWindow,@"production retains eager pane owners in the host window");
  Owner *owner=[Owner new];owner.outlets=[NSMutableDictionary new];owner.valid=YES;
  NSArray *loadedPanes=[owner makeSettingsPanes];
  TSMemoryDefaults *memory=[TSMemoryDefaults new];[memory setObject:@"unknown" forKey:@"TSSettingsSelectedCategory"];[memory setObject:@"sentinel" forKey:@"TexCommand"];
  // Fresh controllers must preserve a valid saved category through assembly.
  [memory setObject:@"console" forKey:@"TSSettingsSelectedCategory"];
  restoreFrame=YES;savedFrame=NSMakeRect(100,100,1200,900);
  TestController *c=[[TestController alloc]initWithDefaults:memory];c.settingsDelegate=owner;
  owner->_prefsWindow=c.window;
  EditingField *editing=[EditingField new];owner.inputRules=[NSMapTable strongToStrongObjectsMapTable];[owner.inputRules setObject:@YES forKey:editing];
  NSDictionary *panes=HostPanes(loadedPanes);NSView *footer=Footer(loadedPanes);
  [c hostPaneControllers:panes footer:footer];
  Check([[memory stringForKey:@"TSSettingsSelectedCategory"] isEqual:@"console"],@"assembly never overwrites persisted category");
  [c beginSession];Check([c.history.currentIdentifier isEqual:@"console"] && c.categoryTable.selectedRow==3,@"fresh controller restores saved category");
  [c.window.contentView layoutSubtreeIfNeeded];
  Check(NSEqualRects(c.window.frame,savedFrame) && !c.shouldCascadeWindows,@"restore frame after complete assembly without cascading");
  Check((c.window.styleMask & NSWindowStyleMaskFullSizeContentView)!=0,@"full height content enabled");
  NSRect scrollInWindow=[c.contentScroll convertRect:c.contentScroll.bounds toView:nil];
  Check(fabs(NSMaxY(scrollInWindow)-NSMaxY(c.window.contentLayoutRect))<1,@"content pinned below toolbar safe area");
  NSSplitViewController *split=(id)c.window.contentViewController;
  NSRect sidebarInWindow=[split.splitViewItems[0].viewController.view convertRect:split.splitViewItems[0].viewController.view.bounds toView:nil];
  Check(fabs(NSMaxY(sidebarInWindow)-NSHeight(c.window.contentView.bounds))<1,@"sidebar reaches titlebar top");
  Check(c.contentScroll.documentView.isFlipped && fabs(c.contentScroll.documentVisibleRect.origin.y)<1,@"content starts at top in tall window");
  Check(c.window.toolbar.items.count==2 && [c.window.toolbar.items[0] isKindOfClass:NSTrackingSeparatorToolbarItem.class] && c.window.toolbar.items[1].navigational,@"tracking divider and navigational toolbar");
  NSArray *expected=@[@"source",@"editor",@"preview",@"console",@"typesetting",@"engines",@"misc-1",@"misc-2",@"themes"];
  Check([c.categoryIdentifiers isEqual:[expected arrayByAddingObject:@"keyboard"]],@"stable ordered category identifiers");
  for(NSUInteger i=0;i<expected.count;i++) Check([c viewForCategoryIdentifier:expected[i]]==[(NSViewController *)panes[expected[i]] view],@"category maps to original localized pane");
  [memory setObject:@"unknown" forKey:@"TSSettingsSelectedCategory"];
  Check([c viewForCategoryIdentifier:@"console"].window==c.window,@"selected controls use the host window");
  Check(c.categoryTable.numberOfRows==10,@"sidebar includes all categories");
  [c beginSession];Check([c.history.currentIdentifier isEqual:@"source"] && c.categoryTable.selectedRow==0,@"unknown category falls back to source");


  Check(c.window.firstResponder==c.categoryTable,@"begin session focuses sidebar");
  NSEvent *arrow=[NSEvent keyEventWithType:NSEventTypeKeyDown location:NSZeroPoint modifierFlags:NSEventModifierFlagFunction|NSEventModifierFlagNumericPad timestamp:0 windowNumber:c.window.windowNumber context:nil characters:@"\uF701" charactersIgnoringModifiers:@"\uF701" isARepeat:NO keyCode:125];
  NSUInteger beforeArrows=owner.commits;
  for(NSInteger step=1;step<=3;step++) {
   [c.window sendEvent:arrow];
   Check(c.categoryTable.selectedRow==step && c.window.firstResponder==c.categoryTable,@"consecutive window arrows preserve sidebar focus");
   Check(owner.commits==beforeArrows+(NSUInteger)step,@"one production validation per category change");
  }
  NSUInteger beforeSame=owner.commits;[c selectCategoryIdentifier:@"console"];
  Check(owner.commits==beforeSame,@"reselect does not validate or release panels");
  [c.window makeFirstResponder:nil];[c endSession];[c beginSession];
  Check(c.window.firstResponder==c.categoryTable,@"reopen restores sidebar focus");
  [c selectCategoryIdentifier:@"source"];

  Check([c viewForCategoryIdentifier:@"themes"].fittingSize.height>700,@"both theme color groups remain scrollable");
  // Selection-query callbacks must never navigate or validate.
  NSUInteger queryCount=c.history.count,queryCommits=owner.commits;
  for(NSInteger row=0;row<9;row++) [(id<NSTableViewDelegate>)c tableView:c.categoryTable shouldSelectRow:row];
  Check(c.history.count==queryCount && owner.commits==queryCommits,@"selection queries have no side effects");
  if(a==3){
   [c.categoryTable keyDown:Key(@"c")];Check(c.history.count<=queryCount+1 && owner.commits<=queryCommits+1,@"type select visits at most one row");
   queryCount=c.history.count;queryCommits=owner.commits;[c.categoryTable keyDown:Key(@"¤")];Check(c.history.count==queryCount && owner.commits==queryCommits,@"unmatched typing never navigates");
  }
  NSRect frame=c.window.frame;
  for(NSString*identifier in expected){Check([c selectCategoryIdentifier:identifier],@"all categories reachable");Check([c.window.title isEqual:((NSViewController *)panes[identifier]).title],@"title follows selected category");}
  Check(NSEqualRects(frame,c.window.frame),@"navigation never resizes window");
  Check(memory.values.count==2 && [[memory stringForKey:@"TexCommand"]isEqual:@"sentinel"],@"navigation only saves UI category state");
  [c goBack:nil];Check(c.categoryTable.selectedRow==7 && [c.navigationControl isEnabledForSegment:1],@"back syncs sidebar/buttons");
  [c goForward:nil];Check(c.categoryTable.selectedRow==8 && ![c.navigationControl isEnabledForSegment:1],@"forward syncs sidebar/buttons");
  owner.valid=NO;NSUInteger count=c.history.count;[c goBack:nil];Check(c.categoryTable.selectedRow==8 && c.history.count==count,@"invalid field blocks history changes");
  Check(![c selectCategoryIdentifier:@"preview"] && c.categoryTable.selectedRow==8,@"invalid field blocks sidebar changes");
  owner.valid=YES;
  [c goBack:nil];owner.valid=NO;[c goForward:nil];Check(c.categoryTable.selectedRow==7,@"invalid field blocks forward");
  [c.categoryTable selectRowIndexes:[NSIndexSet indexSetWithIndex:2] byExtendingSelection:NO];Check(c.categoryTable.selectedRow==7 && [c.history.currentIdentifier isEqual:@"misc-2"],@"invalid sidebar selection restored");
  owner.valid=YES;testSheet=[NSWindow new];[c goForward:nil];Check(c.categoryTable.selectedRow==7,@"sheet blocks forward");testSheet=nil;
  Segment *segment=[Segment new];segment.testSegment=1;Check(c.navigationControl.target==c && c.navigationControl.action==@selector(navigate:),@"toolbar action wired");[c navigate:segment];Check(c.categoryTable.selectedRow==8,@"forward toolbar segment");
  segment.testSegment=0;[c navigate:segment];Check(c.categoryTable.selectedRow==7,@"back toolbar segment");[c goForward:nil];
  testSheet=[NSWindow new];[c goBack:nil];Check(c.categoryTable.selectedRow==8 && ![c selectCategoryIdentifier:@"source"],@"sheet blocks both routes");testSheet=nil;
  testKeyWindow=YES;
  NSEvent *back=[NSEvent keyEventWithType:NSEventTypeKeyDown location:NSZeroPoint modifierFlags:NSEventModifierFlagCommand timestamp:0 windowNumber:0 context:nil characters:@"[" charactersIgnoringModifiers:@"[" isARepeat:NO keyCode:33];
  Check([c.window performKeyEquivalent:back] && c.categoryTable.selectedRow==7,@"Command bracket follows window history");
  testKeyWindow=NO;[c.window performKeyEquivalent:back];Check(c.categoryTable.selectedRow==7,@"history shortcut only in key settings window");
  [c.categoryTable selectRowIndexes:[NSIndexSet indexSetWithIndex:2] byExtendingSelection:NO];Check(c.categoryTable.selectedRow==2 && c.history.forwardIdentifier==nil,@"sidebar route synchronizes once and truncates forward history");
  NSEvent *down=[NSEvent keyEventWithType:NSEventTypeKeyDown location:NSZeroPoint modifierFlags:0 timestamp:0 windowNumber:0 context:nil characters:@"\uF701" charactersIgnoringModifiers:@"\uF701" isARepeat:NO keyCode:125];
  [c.categoryTable keyDown:down];Check(c.categoryTable.selectedRow==3,@"arrow key uses validated category route");
  [c selectCategoryIdentifier:@"preview"];
  NSUInteger visits=c.history.count;[c.categoryTable selectRowIndexes:[NSIndexSet indexSetWithIndex:2] byExtendingSelection:NO];Check(c.history.count==visits,@"reselect is not duplicate history");
  [c endSession];[c beginSession];Check(c.history.count==1 && !c.history.backIdentifier && !c.history.forwardIdentifier,@"reopen resets history and preserves category");
  [c endSession];[memory setObject:@"console" forKey:@"TSSettingsSelectedCategory"];[c beginSession];
  Check([c.history.currentIdentifier isEqual:@"console"] && c.history.count==1,@"reopening reads saved category without retaining history");
  [c changeFont:(NSFontManager *)owner];Check(owner.fonts==1,@"font is explicitly forwarded to preference owner");

  [c.window setContentSize:NSMakeSize(660,440)];[c.window.contentView layoutSubtreeIfNeeded];
  [c.contentScroll.contentView scrollToPoint:NSMakePoint(0,200)];
  NSPoint scrolled=c.contentScroll.contentView.bounds.origin;
  Check(scrolled.y>0,@"fixture is scrolled before rejection");
  owner.valid=NO;NSUInteger rejectedHistory=c.history.count;
  // Simulate a validation failure with focus already in a field, not the sidebar.
  NSTextField *focusField=[[NSTextField alloc]initWithFrame:NSMakeRect(0,0,100,20)];
  [[c viewForCategoryIdentifier:c.history.currentIdentifier ?: @"source"] addSubview:focusField];[c.window makeFirstResponder:focusField];
  NSResponder *failedFocus=c.window.firstResponder;
  [c.categoryTable selectRowIndexes:[NSIndexSet indexSetWithIndex:2] byExtendingSelection:NO];
  Check(NSEqualPoints(c.contentScroll.contentView.bounds.origin,scrolled) && c.history.count==rejectedHistory,@"rejected selection preserves scroll and history");
  Check(c.window.firstResponder==failedFocus,@"failed validation does not steal field focus");
  [c.window makeFirstResponder:c.categoryTable];owner.errorField=focusField;
  [c.categoryTable selectRowIndexes:[NSIndexSet indexSetWithIndex:2] byExtendingSelection:NO];
  Check(c.window.firstResponder==focusField.currentEditor && c.window.firstResponder!=c.categoryTable,@"validation error transfers focus to the invalid field");
  owner.errorField=nil;owner.valid=YES;[focusField removeFromSuperview];
  [c selectCategoryIdentifier:@"preview"];
  Check(fabs(c.contentScroll.contentView.bounds.origin.y)<1,@"successful category switch resets scroll");
  Check(c.window.firstResponder!=c.categoryTable,@"navigation from content does not force sidebar focus");
  [c selectCategoryIdentifier:@"engines"];[c endSession];
  // A new controller reads what actual navigation saved, without injecting defaults.
  TestController *fresh=[[TestController alloc]initWithDefaults:memory];fresh.settingsDelegate=owner;
  [fresh hostPaneControllers:panes footer:footer];owner->_prefsWindow=fresh.window;[fresh beginSession];
  Check([fresh.history.currentIdentifier isEqual:@"engines"] && fresh.categoryTable.selectedRow==5,@"navigation persists for a fresh controller");
  [c hostPaneControllers:panes footer:footer];owner->_prefsWindow=c.window;[c beginSession];

  for(NSString *appearance in @[NSAppearanceNameAqua,NSAppearanceNameDarkAqua]){
   c.window.appearance=[NSAppearance appearanceNamed:appearance];
   for(NSValue *size in @[[NSValue valueWithSize:NSMakeSize(960,650)],[NSValue valueWithSize:NSMakeSize(660,440)]]){
    [c.window setContentSize:size.sizeValue];[c.window.contentView layoutSubtreeIfNeeded];
    for(NSString*identifier in expected){
     [c selectCategoryIdentifier:identifier];[c.window.contentView layoutSubtreeIfNeeded];
     Check([c viewForCategoryIdentifier:identifier].window==c.window,@"selected controls belong to new window");
     if(strlen(argv[2])>0 && (a==3 || [@(argv[a]) containsString:@"ja.lproj"])){
      NSString *lang=[[@(argv[a]) stringByDeletingLastPathComponent]stringByDeletingLastPathComponent].lastPathComponent;
      NSString *name=[NSString stringWithFormat:@"%@-%@-%@-%.0f.png",lang,appearance,identifier,size.sizeValue.width];
      SaveImage([c viewForCategoryIdentifier:identifier], [@(argv[2]) stringByAppendingPathComponent:[@"pane-" stringByAppendingString:name]]);
      SaveImage(c.window.contentView,[@(argv[2]) stringByAppendingPathComponent:name]);
     }
    }
   }
  }
  Check(!c.window.visible,@"no window ordered");
  printf("PASS %s: categories, history, persistence, ownership and four layouts\n",argv[a]);
 }
}return 0;}
