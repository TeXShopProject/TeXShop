// Exercise the settings shell with real localized nibs and memory-only state.
#import <Cocoa/Cocoa.h>
#import "TestAppKitIsolation.h"
#import "TSSettingsWindowController.h"
static NSString *shellPath;
static BOOL testKeyWindow;
static NSWindow *testSheet;
static BOOL IsKey(id self,SEL selector){return testKeyWindow;}
static NSWindow *Sheet(id self,SEL selector){return testSheet;}
static void Check(BOOL yes,NSString *message){if(!yes){fprintf(stderr,"FAIL: %s\n",message.UTF8String);exit(1);}}
@interface TestController:TSSettingsWindowController @end
@implementation TestController
- (void)loadWindow {
 NSNib *nib=[[NSNib alloc]initWithNibData:[NSData dataWithContentsOfFile:shellPath] bundle:nil];
 NSArray *objects=nil;Check([nib instantiateWithOwner:self topLevelObjects:&objects],@"shell XIB loads");
}
@end
@interface Owner:NSObject<TSSettingsWindowDelegate>
@property NSMutableDictionary *outlets;
@property BOOL valid;
@property NSUInteger commits,fonts;
@end
@implementation Owner
- (void)setValue:(id)value forUndefinedKey:(NSString *)key {if(value)self.outlets[key]=value;}
- (BOOL)settingsMayChangeCategory {self.commits++;return self.valid;}
- (void)settingsChangeFont:(id)sender {self.fonts++;}
@end
@interface TSPreferenceWindow:NSWindow @end
@implementation TSPreferenceWindow @end
static NSTabView *Tabs(NSView *v){if([v isKindOfClass:NSTabView.class])return (id)v;for(NSView*c in v.subviews){NSTabView*t=Tabs(c);if(t)return t;}return nil;}
static void SaveImage(NSView *v,NSString *path){[v layoutSubtreeIfNeeded];[v display];NSBitmapImageRep *rep=[v bitmapImageRepForCachingDisplayInRect:v.bounds];[v cacheDisplayInRect:v.bounds toBitmapImageRep:rep];NSImage *image=[[NSImage alloc]initWithSize:v.bounds.size];[image lockFocus];[v.effectiveAppearance performAsCurrentDrawingAppearance:^{[NSColor.windowBackgroundColor setFill];NSRectFill(NSMakeRect(0,0,v.bounds.size.width,v.bounds.size.height));}];NSImage *capture=[[NSImage alloc]initWithSize:v.bounds.size];[capture addRepresentation:rep];[capture drawInRect:NSMakeRect(0,0,v.bounds.size.width,v.bounds.size.height) fromRect:NSZeroRect operation:NSCompositingOperationSourceOver fraction:1];[image unlockFocus];NSBitmapImageRep *opaque=[[NSBitmapImageRep alloc]initWithData:image.TIFFRepresentation];[[opaque representationUsingType:NSBitmapImageFileTypePNG properties:@{}]writeToFile:path atomically:YES];}
int main(int argc,char **argv){@autoreleasepool{
 TSInstallAppKitIsolation();[NSApplication sharedApplication];
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
  Owner *owner=[Owner new];owner.outlets=[NSMutableDictionary new];owner.valid=YES;
  NSNib *nib=[[NSNib alloc]initWithNibData:[NSData dataWithContentsOfFile:@(argv[a])] bundle:nil];NSArray *objects;
  Check([nib instantiateWithOwner:owner topLevelObjects:&objects],@"legacy nib loads");
  NSWindow *old=nil;NSTabView*tabs=nil;for(id o in objects)if([o isKindOfClass:NSWindow.class] && Tabs([o contentView]).numberOfTabViewItems==9){old=o;tabs=Tabs(old.contentView);break;}
  Check(tabs.numberOfTabViewItems==9,@"nine localized primary categories");
  [old.contentView layoutSubtreeIfNeeded];
  NSMutableArray<NSView *> *savedViews=[NSMutableArray new];NSMutableArray<NSValue *> *savedFrames=[NSMutableArray new];
  for(NSTabViewItem *i in tabs.tabViewItems){NSMutableArray *pending=[i.view.subviews mutableCopy];while(pending.count){NSView*v=pending.firstObject;[pending removeObjectAtIndex:0];[savedViews addObject:v];[savedFrames addObject:[NSValue valueWithRect:v.frame]];[pending addObjectsFromArray:v.subviews];}}
  NSRect expectedTabFrame=[tabs convertRect:tabs.contentRect toView:old.contentView];
  NSArray *oldIdentifiers=[tabs.tabViewItems valueForKey:@"identifier"];
  TSMemoryDefaults *memory=[TSMemoryDefaults new];[memory setObject:@"unknown" forKey:@"TSSettingsSelectedCategory"];[memory setObject:@"sentinel" forKey:@"TexCommand"];
  TestController *c=[[TestController alloc]initWithDefaults:memory];c.settingsDelegate=owner;
  NSView *content=old.contentView;[c hostLegacyContent:content tabView:tabs];old.contentView=nil;
  Check(c.window!=old && tabs.window==c.window,@"every sheet and focus target uses the host window");
  Check(NSEqualRects(tabs.frame,expectedTabFrame),@"hidden tabs preserve the original pane frame");
  Check(tabs.tabViewType==NSNoTabsNoBorder && c.categoryTable.numberOfRows==9,@"hidden legacy tabs and sidebar");
  [c beginSession];Check([c.history.currentIdentifier isEqual:@"source"] && c.categoryTable.selectedRow==0,@"unknown category falls back to source");
  for(NSUInteger n=0;n<savedViews.count;n++) Check(NSEqualRects(savedViews[n].frame,savedFrames[n].rectValue),@"hosting preserves fixed control geometry");
  NSTabView *themeTabs=Tabs([c legacyViewForCategoryIdentifier:@"themes"]);
  Check(themeTabs.numberOfTabViewItems==2,@"both theme groups retained");
  for(NSTabViewItem *item in themeTabs.tabViewItems){[themeTabs selectTabViewItem:item];Check(themeTabs.selectedTabViewItem==item,@"theme groups selectable");}
  NSRect frame=c.window.frame;
  for(NSString*identifier in c.categoryIdentifiers)Check([c selectCategoryIdentifier:identifier],@"all categories reachable");
  Check(NSEqualRects(frame,c.window.frame),@"navigation never resizes window");
  Check([[tabs.tabViewItems valueForKey:@"identifier"] isEqual:oldIdentifiers],@"legacy tab identifiers retained");
  Check(memory.values.count==2 && [[memory stringForKey:@"TexCommand"]isEqual:@"sentinel"],@"navigation only saves UI category state");
  [c goBack:nil];Check(c.categoryTable.selectedRow==7 && [c.navigationControl isEnabledForSegment:1],@"back syncs sidebar/buttons");
  [c goForward:nil];Check(c.categoryTable.selectedRow==8 && ![c.navigationControl isEnabledForSegment:1],@"forward syncs sidebar/buttons");
  owner.valid=NO;NSUInteger count=c.history.count;[c goBack:nil];Check(c.categoryTable.selectedRow==8 && c.history.count==count,@"invalid field blocks history changes");
  Check(![c selectCategoryIdentifier:@"preview"] && c.categoryTable.selectedRow==8,@"invalid field blocks sidebar changes");
  owner.valid=YES;testSheet=[NSWindow new];[c goBack:nil];Check(c.categoryTable.selectedRow==8 && ![c selectCategoryIdentifier:@"source"],@"sheet blocks both routes");testSheet=nil;
  testKeyWindow=YES;
  NSEvent *back=[NSEvent keyEventWithType:NSEventTypeKeyDown location:NSZeroPoint modifierFlags:NSEventModifierFlagCommand timestamp:0 windowNumber:0 context:nil characters:@"[" charactersIgnoringModifiers:@"[" isARepeat:NO keyCode:33];
  Check([c.window performKeyEquivalent:back] && c.categoryTable.selectedRow==7,@"Command bracket follows window history");
  testKeyWindow=NO;[c.window performKeyEquivalent:back];Check(c.categoryTable.selectedRow==7,@"history shortcut only in key settings window");
  [c.categoryTable.delegate tableView:c.categoryTable shouldSelectRow:2];Check(c.categoryTable.selectedRow==2 && c.history.forwardIdentifier==nil,@"sidebar route synchronizes once and truncates forward history");
  NSEvent *down=[NSEvent keyEventWithType:NSEventTypeKeyDown location:NSZeroPoint modifierFlags:0 timestamp:0 windowNumber:0 context:nil characters:@"\uF701" charactersIgnoringModifiers:@"\uF701" isARepeat:NO keyCode:125];
  [c.categoryTable keyDown:down];Check(c.categoryTable.selectedRow==3,@"arrow key uses validated category route");
  [c selectCategoryIdentifier:@"preview"];
  NSUInteger visits=c.history.count;[c.categoryTable.delegate tableView:c.categoryTable shouldSelectRow:2];Check(c.history.count==visits,@"reselect is not duplicate history");
  [c endSession];[c beginSession];Check(c.history.count==1 && !c.history.backIdentifier && !c.history.forwardIdentifier,@"reopen resets history and preserves category");
  [c endSession];[memory setObject:@"console" forKey:@"TSSettingsSelectedCategory"];[c beginSession];
  Check([c.history.currentIdentifier isEqual:@"console"] && c.history.count==1,@"reopening reads saved category without retaining history");
  [c changeFont:nil];Check(owner.fonts==1,@"font is explicitly forwarded to preference owner");
  for(NSString *appearance in @[NSAppearanceNameAqua,NSAppearanceNameDarkAqua]){
   c.window.appearance=[NSAppearance appearanceNamed:appearance];
   for(NSValue *size in @[[NSValue valueWithSize:NSMakeSize(960,650)],[NSValue valueWithSize:NSMakeSize(660,440)]]){
    [c.window setContentSize:size.sizeValue];[c.window.contentView layoutSubtreeIfNeeded];
    for(NSString*identifier in c.categoryIdentifiers){
     [c selectCategoryIdentifier:identifier];[c.window.contentView layoutSubtreeIfNeeded];
     Check(tabs.selectedTabViewItem.view.window==c.window,@"selected controls belong to new window");
     if(a==3 || [@(argv[a]) containsString:@"ja.lproj"]){
      NSString *lang=[[@(argv[a]) stringByDeletingLastPathComponent]stringByDeletingLastPathComponent].lastPathComponent;
      NSString *name=[NSString stringWithFormat:@"%@-%@-%@-%.0f.png",lang,appearance,identifier,size.sizeValue.width];
      SaveImage(content, [@(argv[2]) stringByAppendingPathComponent:[@"pane-" stringByAppendingString:name]]);
      SaveImage(c.window.contentView,[@(argv[2]) stringByAppendingPathComponent:name]);
     }
    }
   }
  }
  Check(!c.window.visible && !old.visible,@"no window ordered");
  printf("PASS %s: categories, history, persistence, ownership and four layouts\n",argv[a]);
 }
}return 0;}
