// SPDX-License-Identifier: GPL-2.0-or-later
#import <Cocoa/Cocoa.h>
#import <objc/runtime.h>
#import "TestAppKitIsolation.h"
#import "TSPreferences+Panes.h"
#import "TSPrefPaneLayout.h"
#import "TSDockIconController.h"
static TSMemoryDefaults *memory;
#define SUD memory
// CONSTANTS
@interface TSSpellSupport:NSObject
+ (void)preferencesDidChange;
@end
@implementation TSSpellSupport
+ (void)preferencesDidChange {}
@end
static NSUInteger bindingOpens, helpOpens, completionOpens;
@interface TSAutoCompletionListEditor:NSObject
- (void)openAutoCompletionListEditor:(id)sender;
@end
@implementation TSAutoCompletionListEditor
- (void)openAutoCompletionListEditor:(id)sender { bindingOpens++; }
@end
@interface HelpDocuments:NSObject
- (void)displayCommentLines:(id)sender;
@end
@implementation HelpDocuments
- (void)displayCommentLines:(id)sender { helpOpens++; }
@end
@interface ApplicationDelegate:NSObject<NSApplicationDelegate>
- (void)openCommandCompletionList:(id)sender;
@end
@implementation ApplicationDelegate
- (void)openCommandCompletionList:(id)sender { completionOpens++; }
@end
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wincomplete-implementation"
@implementation TSPreferences
// DEPENDENCIES
@end
#pragma clang diagnostic pop
static NSBundle *bundle;
static id MainBundle(id receiver,SEL selector) { return bundle; }
static void Check(BOOL ok,NSString *why) { if(!ok){fprintf(stderr,"FAIL: %s\n",why.UTF8String);exit(1);} }
static void Collect(NSView *v,NSMutableDictionary *controls) {
 if([v isKindOfClass:NSControl.class] && [v.identifier hasPrefix:@"settings."]) { Check(controls[v.identifier]==nil,@"Control occurs once");controls[v.identifier]=v; }
 for(NSView *c in v.subviews) Collect(c,controls);
}
static NSView *Find(NSView *v,NSString *key) {if([v.identifier isEqual:key])return v;for(NSView *c in v.subviews){NSView *f=Find(c,key);if(f)return f;}return nil;}
static void Geometry(NSView *v) {
 Check(!v.window.visible,@"Window stays hidden");
 if(v.hasAmbiguousLayout){NSMutableArray *path=[NSMutableArray array];for(NSView *a=v;a;a=a.superview)[path addObject:[NSString stringWithFormat:@"%@:%@ %@",NSStringFromClass(a.class),a.identifier,NSStringFromRect(a.frame)]];Check(NO,[path componentsJoinedByString:@" <- "]);}
 for(NSView *c in v.subviews){
  Check(NSContainsRect(NSInsetRect(v.bounds,-1,-1),[c alignmentRectForFrame:c.frame]),[NSString stringWithFormat:@"%@ inside %@",c.identifier,v.identifier]);Geometry(c);
 }
 if([v isKindOfClass:NSButton.class] && ![v isKindOfClass:NSPopUpButton.class]) {
  NSButton *button=(id)v;Check(button.imagePosition==NSImageOnly || button.cell.cellSize.width<=NSWidth(button.frame)+2,[NSString stringWithFormat:@"Button title fits %@ %.1f <= %.1f",button.title,button.cell.cellSize.width,NSWidth(button.frame)]);
 }
 if([v isKindOfClass:NSMatrix.class]) {NSMatrix *matrix=(id)v;
  for(NSInteger row=0;row<matrix.numberOfRows;row++)for(NSInteger col=0;col<matrix.numberOfColumns;col++)Check([matrix cellAtRow:row column:col].cellSize.width<=NSWidth([matrix cellFrameAtRow:row column:col])+1,@"Matrix title fits");
 }
 if([v.identifier hasPrefix:@"row."]) Check(NSHeight(v.frame)>=37.5,@"Minimum row height is 38");
 if([v isKindOfClass:NSStackView.class]) {NSStackView *stack=(id)v;NSView *ancestor=stack;while(ancestor && ![ancestor.identifier isEqual:@"DockIconChoices"])ancestor=ancestor.superview;Check(stack.spacing==12||(ancestor && stack.spacing==6),@"Row spacing");}
}
static void Pair(NSView *root,NSString *parent,NSString *child) {
 NSView *a=Find(root,parent),*b=Find(root,child);Check(a&&b,@"Dependency controls are in the same category");
 NSRect x=[a.superview convertRect:[a alignmentRectForFrame:a.frame] toView:root],y=[b.superview convertRect:[b alignmentRectForFrame:b.frame] toView:root];
 Check(fabs(NSMinX(y)-NSMinX(x)-24)<1,[NSString stringWithFormat:@"Dependent %@ / %@ indented by 24 (%.2f)",parent,child,NSMinX(y)-NSMinX(x)]);
 Check(NSMaxY(y)<=NSMinY(x)+1,@"Dependent child follows parent");
 NSView *g=a;while(g && ![g isKindOfClass:NSBox.class])g=g.superview;
 Check(g && [b isDescendantOf:g],@"Dependent child shares parent group");
}
int main(int argc,char **argv){@autoreleasepool{
 TSInstallAppKitIsolation();[NSApplication sharedApplication];memory=[TSMemoryDefaults new];
 bundle=[NSBundle bundleWithPath:@(argv[1])];Check(bundle!=nil,@"Fixture bundle");
 method_setImplementation(class_getClassMethod(NSBundle.class,@selector(mainBundle)),(IMP)MainBundle);
 TSPreferences *owner=[TSPreferences new];NSArray *original=[owner makeSettingsPanes];
 NSMutableDictionary *before=[NSMutableDictionary dictionary];
 for(TSPrefPaneController *p in original)if(p.categoryIdentifier)Collect(p.view,before);
 NSMutableArray *originalCells=[NSMutableArray arrayWithArray:[(NSMatrix *)before[@"settings.621"] cells]];
 [originalCells addObjectsFromArray:[(NSMatrix *)before[@"settings.cp7-bc-avh"] cells]];
 [before removeObjectForKey:@"settings.621"];[before removeObjectForKey:@"settings.cp7-bc-avh"];
 NSDictionary *panes=[owner classifySettingsPanes:original];Check(panes.count==10,@"Ten final categories");
 TSDockIconController *dock=[[TSDockIconController alloc]initWithBundle:bundle defaults:memory];
 [dock installInPreferencesPane:[panes[@"appearance"] view]];
 Check(Find([panes[@"appearance"] view],@"DockIconChoices")!=nil,@"Dock choices installed in Appearance");
 NSMutableDictionary *after=[NSMutableDictionary dictionary];for(NSViewController *p in panes.allValues)Collect(p.view,after);
 for(NSString *key in before)Check(before[key]==after[key],[NSString stringWithFormat:@"Original control retained exactly once: %@",key]);
 for(NSString *category in panes){
  NSMutableDictionary *categoryControls=[NSMutableDictionary dictionary];Collect([panes[category] view],categoryControls);
  for(NSString *identifier in [[categoryControls allKeys] sortedArrayUsingSelector:@selector(compare:)])printf("CONTROL %s %s\n",identifier.UTF8String,category.UTF8String);
  NSView *v=[panes[category] view];NSWindow *w=[[NSWindow alloc]initWithContentRect:NSMakeRect(0,0,1200,900) styleMask:NSWindowStyleMaskBorderless backing:NSBackingStoreBuffered defer:NO];
  [w.contentView addSubview:v];NSLayoutConstraint *width=[v.widthAnchor constraintEqualToConstant:700];[NSLayoutConstraint activateConstraints:@[width,[v.leadingAnchor constraintEqualToAnchor:w.contentView.leadingAnchor],[v.topAnchor constraintEqualToAnchor:w.contentView.topAnchor]]];
  for(NSNumber *size in ([category isEqual:@"keyboard"] ? @[@660,@700,@960] : @[@700,@960]))for(NSAppearanceName appearance in @[NSAppearanceNameAqua,NSAppearanceNameDarkAqua]){
   width.constant=size.doubleValue;w.appearance=[NSAppearance appearanceNamed:appearance];[w.contentView layoutSubtreeIfNeeded];Geometry(v);
   if([category isEqual:@"documents"]){Pair(v,@"settings.RVR-YO-Xhy",@"settings.jhC-up-cya");Pair(v,@"settings.RVR-YO-Xhy",@"settings.N8r-9Y-N2R");}
   if([category isEqual:@"general"])Pair(v,@"settings.30",@"settings.33");
   if([category isEqual:@"preview"]){Pair(v,@"settings.44",@"settings.46");Pair(v,@"settings.4qx-Bg-9Ii",@"settings.EPC-FR-GKh");Pair(v,@"settings.437",@"settings.439");Pair(v,@"settings.G6V-Sw-jFT",@"settings.iRm-g2-CpD");}
   if([category isEqual:@"console"])Pair(v,@"settings.fMM-Lh-WMT",@"settings.ySw-P2-zn6");
   if([category isEqual:@"updates"])Pair(v,@"settings.Tu2-Zu-ut5",@"settings.ssL-3D-6IR");
   if([category isEqual:@"typesetting"])Pair(v,@"settings.181",@"settings.592");
   if([category isEqual:@"editor"]){for(NSString *key in @[@"settings.sHY-8y-Sax",@"settings.QEw-MD-Er9",@"settings.SWN-Un-R10"])Pair(v,@"settings.RtB-ZN-uCk",key);
    Check(fabs(NSWidth([Find(v,@"settings.9yz-Dw-vpr") alignmentRectForFrame:Find(v,@"settings.9yz-Dw-vpr").frame])-170)<1,@"Field label column is 170");}
   if([category isEqual:@"spelling"]){Pair(v,@"settings.ts-aware-spelling",@"settings.ts-edit-spelling");for(NSString *key in @[@"settings.cell.teg-0p-Q8J",@"settings.cell.3eF-XA-ahc",@"settings.cell.8Wq-gx-FqO"])Pair(v,@"settings.legacy-spelling",key);}
  }
  printf("CATEGORY %s height=%.0f\n",category.UTF8String,NSHeight(v.frame));
  [v removeFromSuperview];
 }
 NSDictionary *titles=@{@"settings.ts-aware-spelling":@"Use LaTeX-aware spell checking (recommended)",@"settings.legacy-spelling":@"Use legacy spell checking",@"settings.edit-bindings":@"Edit Key Bindings…",@"settings.edit-completion":@"Edit Command Completion…",@"settings.hidden-settings-help":@"Comment Lines and Hidden Settings"};
 for(NSString *identifier in titles) Check([[(NSButton *)after[identifier] title] isEqual:[bundle localizedStringForKey:titles[identifier] value:titles[identifier] table:@"Localizable"]],@"Displayed custom label uses its localized string");
 ApplicationDelegate *appDelegate=[ApplicationDelegate new];NSApp.delegate=appDelegate;
 for(NSString *identifier in @[@"settings.edit-bindings",@"settings.edit-completion",@"settings.hidden-settings-help"]) {
  NSButton *button=after[identifier];Check(button!=nil,@"Editor/help button exists");
  Check([button sendAction:button.action to:button.target],@"Editor/help action reaches its intended owner");
 }
 Check(bindingOpens==1 && completionOpens==1 && helpOpens==1,@"All moved editor/help actions route once without a visible panel");
 Check(owner.keyBindingEditor!=nil && owner.settingsHelpDocuments!=nil,@"Lazily created helper owners are retained");
 // Dispatch through the migrated control and original typed owner, using the
 // production action body. A copied cell or lost target must fail here.
 NSDictionary *writes=@{@"839":@"SyntaxColoringEnabled",@"cgA-o7-Bdw":@"MakeatletterEnabled",@"f1k-jx-ley":@"expl3SyntaxColoring",@"840":@"ParensMatchingEnabled",@"841":@"SpellCheckEnabled",@"842":@"AutoCompleteEnabled",@"843":@"BibDeskCompletion",@"844":@"AcceptFirstMouse",@"845":@"LineNumberEnabled",@"846":@"RightJustify",@"XoX-gZ-pO3":@"TagMenuInMenuBar",@"PhR-Vr-jce":@"AutomaticSpellingCorrectionEnabled",@"CPb-hk-Gqb":@"EditorCanAddBrackets",@"teg-0p-Q8J":@"TurnOffCommandSpellCheck",@"3eF-XA-ahc":@"TurnOffParameterSpellCheck",@"8Wq-gx-FqO":@"TurnOffCommentSpellCheck"};
 for(NSString *identifier in writes) {
  NSButton *button=after[[@"settings.cell." stringByAppendingString:identifier]];
  Check([originalCells containsObject:button.cell],@"Migrated button uses the original cell");
  Check(button!=nil && button.target!=nil && button.action!=NULL,@"Migrated cell retains an action and typed owner");
  for(NSNumber *value in @[@YES,@NO,@YES]) {
   [memory.values removeAllObjects];button.enabled=YES;button.state=value.boolValue;
   Check([button sendAction:button.action to:button.target],@"Migrated action dispatches");
   Check(memory.values.count==1 && [memory.values[writes[identifier]] isEqual:value],[NSString stringWithFormat:@"%@ saves only %@: %@",identifier,writes[identifier],memory.values]);
  }
 }
 // Radio actions are dispatched through the actual targets without a window.
 for(NSNumber *method in @[@NO,@YES,@NO,@YES]) {
  NSButton *choice=after[method.boolValue?@"settings.ts-aware-spelling":@"settings.legacy-spelling"];
  choice.state=NSControlStateValueOn;
  Check([choice sendAction:choice.action to:choice.target],@"Spelling radio action dispatches");
  Check([memory boolForKey:@"TeXAwareSpellChecking"]==method.boolValue,@"Radio choice is saved");
  Check(((NSButton *)after[@"settings.ts-aware-spelling"]).state==method.boolValue && ((NSButton *)after[@"settings.legacy-spelling"]).state==!method.boolValue,@"Exactly one spelling method is selected");
 }
 NSDictionary *families=@{@"settings.RtB-ZN-uCk":@[@"settings.Wrg-WR-c6H",@"settings.l7y-UX-7WO",@"settings.uve-Zu-06Q"],@"settings.437":@[@"settings.434"],@"settings.RVR-YO-Xhy":@[@"settings.jhC-up-cya"]};
 for(NSString *parent in families)for(NSNumber *value in @[@YES,@NO,@YES]) {
  NSButton *button=after[parent];button.state=value.boolValue;
  BOOL expected=[parent isEqual:@"settings.RVR-YO-Xhy"]?!value.boolValue:value.boolValue;
  for(NSString *child in families[parent])((NSControl *)after[child]).enabled=!expected;
  Check([button sendAction:button.action to:button.target],@"Parent action dispatches through original owner");
  for(NSString *child in families[parent])Check(((NSControl *)after[child]).enabled==expected,@"Parent action immediately refreshes dependent controls");
 }
 for(NSString *parent in @[@"settings.G6V-Sw-jFT",@"settings.MBq-SG-G54"]) {
  NSButton *button=after[parent];BOOL expected=button.tag!=0;
  for(NSString *child in @[@"settings.iRm-g2-CpD",@"settings.zvK-4Q-HJ5"])((NSControl *)after[child]).enabled=!expected;
  Check([button sendAction:button.action to:button.target],@"Unified window action dispatches");
  for(NSString *child in @[@"settings.iRm-g2-CpD",@"settings.zvK-4Q-HJ5"])Check(((NSControl *)after[child]).enabled==expected,@"Unified window action refreshes both side choices");
 }
 // Every parent value changes availability only; child state survives both ways.
 for(NSNumber *value in @[@YES,@NO,@YES]){
  BOOL on=value.boolValue;for(NSString *key in @[BlockCursorKey,PdfColorMapKey,SourceAndPreviewInSameWindowKey,AutoSaveEnabledKey,@"TeXAwareSpellChecking"])[memory setBool:on forKey:key];
  NSDictionary *saved=[memory.values copy];[owner updateSettingsDependenciesFromDefaults:memory];[owner updateSpellingControlsFromDefaults:memory];
  for(NSString *key in @[@"settings.Wrg-WR-c6H",@"settings.l7y-UX-7WO",@"settings.uve-Zu-06Q",@"settings.434",@"settings.iRm-g2-CpD",@"settings.zvK-4Q-HJ5",@"settings.ts-edit-spelling"])Check([(NSControl *)after[key] isEnabled]==on,[@"Dependency follows parent: " stringByAppendingString:key]);
  Check([(NSControl *)after[@"settings.jhC-up-cya"] isEnabled]==!on,@"Backup depends on autosave off");
  for(NSString *key in @[@"settings.cell.teg-0p-Q8J",@"settings.cell.3eF-XA-ahc",@"settings.cell.8Wq-gx-FqO"])Check([(NSControl *)after[key] isEnabled]==!on,@"Legacy children use the legacy method");
  for(NSString *key in @[@"settings.cell.cgA-o7-Bdw",@"settings.cell.f1k-jx-ley",@"settings.cell.845",@"settings.949"])Check([(NSControl *)after[key] isEnabled],@"Independent settings stay available");
  Check([saved isEqual:memory.values],@"Dependencies never rewrite saved values");
 }
 puts("PASS: ten categories, complete control migration, geometry and dependency state");
}return 0;}
