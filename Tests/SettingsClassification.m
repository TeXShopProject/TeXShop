// SPDX-License-Identifier: GPL-2.0-or-later
#import <Cocoa/Cocoa.h>
#import <objc/runtime.h>
#import "TestAppKitIsolation.h"
#import "TSPreferences+Panes.h"
#import "TSPrefPaneLayout.h"
#import "TSDockIconController.h"
#import "TSSettingsChangeNote.h"
#import "globals.h"
#import "TSPreferenceEffects.h"
#import "TSColorSupport.h"
#import "TSKeyBindingsController.h"
#import "TSPreferences+LiveSettings.h"
#import "TSWindowManager.h"
#import "TSSettingsWindowController.h"
@interface TSPreferences (TestInputAPI)
- (void)configurePreferenceInputs;
- (BOOL)control:(NSControl *)control textShouldEndEditing:(NSText *)editor;
- (void)FillInColorWells;
@property(strong) TSSettingsWindowController *settingsController;
- (BOOL)commitPreferenceField:(NSControl *)field showError:(BOOL)showError reflect:(BOOL)reflect;
@end
static TSMemoryDefaults *memory;
#undef SUD
#define SUD memory

@interface TSSpellSupport:NSObject
+ (void)preferencesDidChange;
@end
@implementation TSSpellSupport
+ (void)preferencesDidChange {}
@end
static NSUInteger helpOpens, completionOpens;
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

@interface DetachedPaneHost:TSSettingsWindowController
@property NSDictionary *testPanes;
@end
@implementation DetachedPaneHost
- (NSView *)viewForCategoryIdentifier:(NSString *)identifier { return [self.testPanes[identifier] view]; }
@end
static NSBundle *bundle;
static id MainBundle(id receiver,SEL selector) { return bundle; }
static void Check(BOOL ok,NSString *why) { if(!ok){fprintf(stderr,"FAIL: %s\n",why.UTF8String);exit(1);} }
static id _Nonnull Required(id _Nullable value) {if(value==nil)abort();return (id _Nonnull)value;}
static NSString * _Nonnull Argument(const char *value) {return Required([NSString stringWithUTF8String:value]);}
static void Collect(NSView *v,NSMutableDictionary *controls) {
 if([v isKindOfClass:NSControl.class] && ![v isKindOfClass:NSImageView.class] && [v.identifier hasPrefix:@"settings."]) { Check(controls[Required(v.identifier)]==nil,[NSString stringWithFormat:@"Control occurs once: %@",v.identifier]);controls[Required(v.identifier)]=v; }
 for(NSView *c in v.subviews) Collect(c,controls);
}
static NSView *Find(NSView *v,NSString *key) {if([v.identifier isEqual:key])return v;for(NSView *c in v.subviews){NSView *f=Find(c,key);if(f)return f;}return nil;}
static NSUInteger HeadingCount(NSView *view) {NSUInteger count=[view.identifier hasPrefix:@"heading."]?1:0;for(NSView *child in view.subviews)count+=HeadingCount(child);return count;}
static void SaveImage(NSView *v,NSString *path){[v layoutSubtreeIfNeeded];[v display];NSBitmapImageRep *rep=[v bitmapImageRepForCachingDisplayInRect:v.bounds];[v cacheDisplayInRect:v.bounds toBitmapImageRep:rep];NSImage *image=[[NSImage alloc]initWithSize:v.bounds.size];[image lockFocus];[v.effectiveAppearance performAsCurrentDrawingAppearance:^{[NSColor.windowBackgroundColor setFill];NSRectFill(NSMakeRect(0,0,v.bounds.size.width,v.bounds.size.height));}];NSImage *capture=[[NSImage alloc]initWithSize:v.bounds.size];[capture addRepresentation:rep];[capture drawInRect:NSMakeRect(0,0,v.bounds.size.width,v.bounds.size.height) fromRect:NSZeroRect operation:NSCompositingOperationSourceOver fraction:1];[image unlockFocus];NSData *tiff=image.TIFFRepresentation;if(tiff==nil)abort();NSBitmapImageRep *opaque=[[NSBitmapImageRep alloc]initWithData:tiff];[[opaque representationUsingType:NSBitmapImageFileTypePNG properties:@{}]writeToFile:path atomically:YES];}
static void Geometry(NSView *v) {
 Check(!v.window.visible,@"Window stays hidden");
 if(v.hidden) return;
 if(v.hasAmbiguousLayout){NSMutableArray *path=[NSMutableArray array];for(NSView *a=v;a;a=a.superview)[path addObject:[NSString stringWithFormat:@"%@:%@ %@",NSStringFromClass(a.class),a.identifier,NSStringFromRect(a.frame)]];Check(NO,[path componentsJoinedByString:@" <- "]);}
 for(NSView *c in v.subviews){
  if(c.hidden)continue;
  Check(NSContainsRect(NSInsetRect(v.bounds,-1,-1),[c alignmentRectForFrame:c.frame]),[NSString stringWithFormat:@"%@ inside %@",c.identifier,v.identifier]);Geometry(c);
 }
 if([v isKindOfClass:NSButton.class] && ![v isKindOfClass:NSPopUpButton.class] && !v.hidden) {
  NSButton *button=(id)v;Check(button.imagePosition==NSImageOnly || button.cell.cellSize.width<=NSWidth(button.frame)+2,[NSString stringWithFormat:@"Button title fits %@ %.1f <= %.1f",button.title,button.cell.cellSize.width,NSWidth(button.frame)]);
 }
 if([v isKindOfClass:NSMatrix.class]) {NSMatrix *matrix=(id)v;
  for(NSInteger row=0;row<matrix.numberOfRows;row++)for(NSInteger col=0;col<matrix.numberOfColumns;col++)Check([matrix cellAtRow:row column:col].cellSize.width<=NSWidth([matrix cellFrameAtRow:row column:col])+1,@"Matrix title fits");
 }
 if([v.identifier hasPrefix:@"row."]) Check(NSHeight(v.frame)>=37.5,@"Minimum row height is 38");
 if([v isKindOfClass:NSStackView.class]) {NSStackView *stack=(id)v;NSView *ancestor=stack;while(ancestor && ![ancestor.identifier isEqual:@"DockIconChoices"])ancestor=ancestor.superview;Check(stack.spacing==0||stack.spacing==8||stack.spacing==18||stack.spacing==12||stack.spacing==14||stack.spacing==2||stack.spacing==6||([stack.identifier isEqual:@"settings.change-note"] && stack.spacing==4)||(ancestor && stack.spacing==4)||([NSStringFromClass(stack.class) isEqual:@"TSSettingsOpacityPresentation"] && stack.spacing==4),[NSString stringWithFormat:@"Compact row and section spacing: %@ %.1f",stack.identifier,stack.spacing]);}
}
int main(int argc,char **argv){@autoreleasepool{
 TSInstallAppKitIsolation();[NSApplication sharedApplication];memory=TSIsolatedAppKitDefaults;
 bundle=[NSBundle bundleWithPath:Argument(argv[1])];Check(bundle!=nil,@"Fixture bundle");
 Method mainBundleMethod=class_getClassMethod(NSBundle.class,@selector(mainBundle));if(mainBundleMethod==NULL)abort();
 method_setImplementation(mainBundleMethod,(IMP)MainBundle);
 TSPreferences *owner=[TSPreferences new];NSArray *original=[owner makeSettingsPanes];
 // SNAPSHOT_ENCODING
 NSMutableDictionary *before=[NSMutableDictionary dictionary];
 for(TSPrefPaneController *p in original)if(p.categoryIdentifier)Collect(p.view,before);
 NSMutableArray *originalCells=[NSMutableArray arrayWithArray:[(NSMatrix *)before[@"settings.621"] cells]];
 [originalCells addObjectsFromArray:[(NSMatrix *)before[@"settings.cp7-bc-avh"] cells]];
 [before removeObjectForKey:@"settings.621"];[before removeObjectForKey:@"settings.cp7-bc-avh"];
 NSDictionary *panes=[owner classifySettingsPanes:original];Check(panes.count==10,@"Ten final categories");
 owner.settingsChangeNotes=[[TSSettingsChangeNotes alloc]initWithDefaults:memory launchValues:@{@"AutoSaveEnabled":@NO,@"FindMethod":@1} bundle:bundle];
 [owner.settingsChangeNotes attachToPanes:panes];[owner.settingsChangeNotes beginSession];
 NSDictionary *contract=[NSJSONSerialization JSONObjectWithData:Required([NSData dataWithContentsOfFile:Argument(argv[2])]) options:0 error:NULL][@"groups"];
 Check(contract.count==panes.count,@"Independent category contract covers every category");
 for(NSString *category in contract){
  NSStackView *stack=(NSStackView *)[panes[category] view].subviews.firstObject;
  NSMutableArray *actual=[NSMutableArray array];
  NSView *overview=Find([panes[category] view],@"category.header");
  Check(overview!=nil && [stack.arrangedSubviews.firstObject isEqual:overview],@"Every category starts with its overview card");
  NSTextField *summary=(NSTextField *)Find(overview,@"category.description");
  NSString *summaryKey=[category stringByAppendingString:@".summary"];
  Check([summary.stringValue isEqual:[bundle localizedStringForKey:summaryKey value:nil table:@"SettingsCategories"]] && ![summary.stringValue isEqual:summaryKey],@"Overview uses the translated category summary");
  for(NSView *group in stack.arrangedSubviews)if(![group.identifier isEqual:@"category.header"]) {
   [actual addObject:Required(group.identifier)];
   if([group isKindOfClass:TSSettingsGroupView.class])Check(Find(group,@"card.background")!=nil,@"Settings groups have a visible rounded-card presentation");
  }
  Check([actual isEqual:contract[category]],[NSString stringWithFormat:@"Category group order %@: %@",category,actual]);
 }
 NSDictionary *controlCategories=@{@"settings.hidden-settings-help":@"general",@"settings.926":@"keyboard",@"settings.cell.842":@"keyboard",@"settings.cell.843":@"keyboard",@"settings.edit-completion":@"keyboard",@"settings.o1v-YF-ekd":@"spelling",@"settings.ts-edit-spelling":@"spelling",@"settings.cell.teg-0p-Q8J":@"spelling"};
 for(NSString *identifier in controlCategories)Check(Find([panes[Required(controlCategories[identifier])] view],identifier)!=nil,[@"Planned control category: " stringByAppendingString:identifier]);
 Check(HeadingCount(Find([panes[@"documents"] view],@"group.encoding"))==1 && HeadingCount(Find([panes[@"documents"] view],@"group.saving"))==1,@"Documents has one heading for Encoding and one for Saving");
 Check([Find([panes[@"documents"] view],@"settings.5xa-en-KkV") isDescendantOf:Find([panes[@"documents"] view],@"group.encoding")],@"Encoding dialog option belongs to Encoding");
 TSDockIconController *dock=[[TSDockIconController alloc]initWithBundle:bundle defaults:memory];
 [dock installInPreferencesPane:[panes[@"general"] view]];
 Check(Find([panes[@"general"] view],@"DockIconChoices")!=nil && Find([panes[@"appearance"] view],@"DockIconChoices")==nil,@"Dock choices installed in General, not Themes");
 NSMutableDictionary *after=[NSMutableDictionary dictionary];for(NSViewController *p in panes.allValues)Collect(p.view,after);
 for(NSString *key in before){NSControl *c=before[key];BOOL retained=[c isKindOfClass:NSMatrix.class] || [c isKindOfClass:NSColorWell.class] || c.action!=NULL || ([c isKindOfClass:NSTextField.class] && ((NSTextField *)c).editable) || [@[@"settings.18",@"settings.754"] containsObject:key];if(retained)Check(c==after[key],[NSString stringWithFormat:@"Original functional control retained exactly once: %@",key]);}
 for(NSString *category in panes){
  NSMutableDictionary *categoryControls=[NSMutableDictionary dictionary];Collect([panes[category] view],categoryControls);
  for(NSString *identifier in [[categoryControls allKeys] sortedArrayUsingSelector:@selector(compare:)])printf("CONTROL %s %s\n",identifier.UTF8String,category.UTF8String);
  NSView *v=[panes[category] view];NSWindow *w=[[NSWindow alloc]initWithContentRect:NSMakeRect(0,0,1200,900) styleMask:NSWindowStyleMaskBorderless backing:NSBackingStoreBuffered defer:NO];
  NSView *content=w.contentView;if(content==nil)abort();[content addSubview:v];NSLayoutConstraint *width=[v.widthAnchor constraintEqualToConstant:700];[NSLayoutConstraint activateConstraints:@[width,[v.leadingAnchor constraintEqualToAnchor:content.leadingAnchor],[v.topAnchor constraintEqualToAnchor:content.topAnchor]]];
  for(NSNumber *size in ([category isEqual:@"keyboard"] ? @[@570,@660,@700,@960] : @[@570,@700,@960]))for(NSAppearanceName appearance in @[NSAppearanceNameAqua,NSAppearanceNameDarkAqua]){
   width.constant=size.doubleValue;w.appearance=[NSAppearance appearanceNamed:appearance];[w.contentView layoutSubtreeIfNeeded];Geometry(v);
   if(argc>3 && (size.integerValue==570 || size.integerValue==700))SaveImage(v,[Argument(argv[3]) stringByAppendingPathComponent:[NSString stringWithFormat:@"%@-%@-%@.png",category,appearance,size]]);
   if([category isEqual:@"spelling"]){
    for(NSString *key in @[@"settings.ts-edit-spelling",@"settings.cell.teg-0p-Q8J",@"settings.cell.3eF-XA-ahc",@"settings.cell.8Wq-gx-FqO"]){NSView *row=Find(v,key);while(row && ![row.identifier hasPrefix:@"row."])row=row.superview;Check(row!=nil,@"Spelling child has a catalog row");NSView *label=Find(row,@"label.catalog-row");if(label)Check(fabs(NSMinX([label.superview convertRect:[label alignmentRectForFrame:label.frame] toView:row])-36)<1,[NSString stringWithFormat:@"Spelling child %@ label is indented 24 points: %@",key,NSStringFromRect([label convertRect:label.bounds toView:row])]);}
   }
  }
  printf("CATEGORY %s height=%.0f\n",category.UTF8String,NSHeight(v.frame));
  [v removeFromSuperview];
 }
 NSBox *bindings=(NSBox *)Find([panes[@"keyboard"] view],@"group.bindings");
 NSString *bindingsTitle=[bundle localizedStringForKey:@"group.bindings.title" value:nil table:@"SettingsCategories"];
 Check([bindings.accessibilityLabel isEqual:bindingsTitle],@"Bindings heading follows approved catalog");
 ApplicationDelegate *appDelegate=[ApplicationDelegate new];NSApp.delegate=appDelegate;
 for(NSString *identifier in @[@"settings.edit-completion",@"settings.hidden-settings-help"]) {
  NSButton *button=after[identifier];Check(button!=nil,@"Editor/help button exists");
  Check([button sendAction:button.action to:button.target],@"Editor/help action reaches its intended owner");
 }
 Check(completionOpens==1 && helpOpens==1,@"All moved editor/help actions route once without a visible panel");
 Check(owner.settingsHelpDocuments!=nil,@"Lazily created helper owners are retained");
 // Key bindings are edited in the list in the Key Bindings group, not in a window.
 Check(after[@"settings.edit-bindings"]==nil && owner.keyBindings!=nil && [Find(bindings,@"settings.key-bindings") isEqual:owner.keyBindings.view] && [owner.keyBindings.view isDescendantOf:bindings] && Find(bindings,@"keybindings.table")!=nil,@"The key binding list is embedded in the Key Bindings group");
 // Dispatch through the migrated control and original typed owner, using the
 // production action body. A copied cell or lost target must fail here.
 NSDictionary *writes=@{@"839":@"SyntaxColoringEnabled",@"cgA-o7-Bdw":@"MakeatletterEnabled",@"f1k-jx-ley":@"expl3SyntaxColoring",@"840":@"ParensMatchingEnabled",@"841":@"SpellCheckEnabled",@"842":@"AutoCompleteEnabled",@"843":@"BibDeskCompletion",@"844":@"AcceptFirstMouse",@"845":@"LineNumberEnabled",@"846":@"RightJustify",@"XoX-gZ-pO3":@"TagMenuInMenuBar",@"PhR-Vr-jce":@"AutomaticSpellingCorrectionEnabled",@"CPb-hk-Gqb":@"EditorCanAddBrackets",@"teg-0p-Q8J":@"TurnOffCommandSpellCheck",@"3eF-XA-ahc":@"TurnOffParameterSpellCheck",@"8Wq-gx-FqO":@"TurnOffCommentSpellCheck"};
 for(NSString *identifier in writes) {
  NSButton *button=after[[@"settings.cell." stringByAppendingString:identifier]];
  Check([originalCells containsObject:Required(button.cell)],@"Migrated button uses the original cell");
  Check(button!=nil && button.target!=nil && button.action!=NULL,@"Migrated cell retains an action and typed owner");
  NSSwitch *toggle=(NSSwitch *)Find(button.superview,[@"toggle." stringByAppendingString:Required(button.identifier)]);
  Check([toggle isKindOfClass:NSSwitch.class],@"Individual boolean settings use a native switch");
  Check(button.hidden && !button.isAccessibilityElement,@"Original button is retained without a duplicate accessibility control");
  for(NSNumber *value in @[@YES,@NO,@YES]) {
   button.enabled=value.boolValue; Check(toggle.enabled==value.boolValue,@"Programmatic dependency updates reach the native switch");
   button.state=value.boolValue;Check(toggle.state==button.state,@"Programmatic profile/default updates reach the native switch");
   [memory.values removeAllObjects];button.enabled=YES;toggle.state=value.boolValue;
   Check([toggle sendAction:toggle.action to:toggle.target],@"Native switch dispatches through its original control");
   Check(memory.values.count==1 && [memory.values[Required(writes[identifier])] isEqual:Required(value)],@"Native switch preserves the original key and writes once");
   Check(button.state==toggle.state,@"Native switch updates original cell state");
   [memory.values removeAllObjects];button.enabled=YES;button.state=value.boolValue;
   Check([button sendAction:button.action to:button.target],@"Migrated action dispatches");
   Check(memory.values.count==1 && [memory.values[Required(writes[identifier])] isEqual:Required(value)],[NSString stringWithFormat:@"%@ saves only %@: %@",identifier,writes[identifier],memory.values]);
  }
 }
 if(argc>3){
  [memory.values removeAllObjects];[memory.values addEntriesFromDictionary:@{@"TeXAwareSpellChecking":@NO,@"PdfMagnification":@1,@"Encoding":@"UTF-8",@"AutoSaveEnabled":@NO,@"FindMethod":@1}];
  [owner.settingsChangeNotes beginSession];owner.settingsChangeNotes.hasPDFWindow=^BOOL{return YES;};owner.settingsChangeNotes.hasSourceWindow=^BOOL{return YES;};
  NSArray *cases=@[@[@"spelling",@"row.catalog.spelling.1.0",@"TeXAwareSpellChecking",@YES],@[@"preview",@"row.catalog.preview.0.2",@"PdfMagnification",@1.5],@[@"documents",@"row.catalog.documents.0.0",@"Encoding",@"MacOSRoman"],@[@"documents",@"row.catalog.documents.1.0",@"AutoSaveEnabled",@YES],@[@"editor",@"row.catalog.editor.7.0",@"FindMethod",@2]];
  for(NSArray *entry in cases){
   NSView *pane=[panes[entry[0]] view];NSWindow *window=[[NSWindow alloc]initWithContentRect:NSMakeRect(0,0,700,900) styleMask:NSWindowStyleMaskBorderless backing:NSBackingStoreBuffered defer:NO];
   NSView *host=window.contentView;if(!host)abort();[host addSubview:pane];NSLayoutConstraint *width=[pane.widthAnchor constraintEqualToConstant:570];[NSLayoutConstraint activateConstraints:@[width,[pane.leadingAnchor constraintEqualToAnchor:host.leadingAnchor],[pane.topAnchor constraintEqualToAnchor:host.topAnchor]]];
   [host layoutSubtreeIfNeeded];NSView *row=Find(pane,entry[1]);CGFloat normal=NSHeight(row.frame);
   id previous=[owner.settingsChangeNotes currentValueForKey:entry[2]];[memory setObject:entry[3] forKey:entry[2]];[owner.settingsChangeNotes recordUserChangeForKey:entry[2] previousValue:previous];
   for(NSAppearanceName appearance in @[NSAppearanceNameAqua,NSAppearanceNameDarkAqua]){
    window.appearance=[NSAppearance appearanceNamed:appearance];[host layoutSubtreeIfNeeded];Geometry(row);
    Check(NSHeight(row.frame)>normal,@"Showing a note expands only its row");
    TSSettingsChangeNote *shownNote=(id)Find(row,@"settings.change-note");
    Check(NSWidth(shownNote.frame)>=160 && NSHeight(shownNote.frame)<100,[NSString stringWithFormat:@"Note %@ uses readable horizontal lines: %@",entry[2],NSStringFromRect(shownNote.frame)]);
    SaveImage(row,[Argument(argv[3]) stringByAppendingPathComponent:[NSString stringWithFormat:@"note-%@-%@.png",entry[2],appearance]]);
   }
   [memory setObject:previous forKey:entry[2]];[owner.settingsChangeNotes recordUserChangeForKey:entry[2] previousValue:entry[3]];[host layoutSubtreeIfNeeded];Check(fabs(NSHeight(row.frame)-normal)<1,@"Hiding a note restores compact row height");
   [pane removeFromSuperview];width.active=NO;
  }
  [owner.settingsChangeNotes endSession];
 }
 // Action path through the real migrated spelling controls and production note manager.
 [memory setBool:NO forKey:@"TeXAwareSpellChecking"];[owner.settingsChangeNotes beginSession];
 TSSettingsChangeNote *spellNote=(id)Find(Find([panes[@"spelling"] view],@"row.catalog.spelling.1.0"),@"settings.change-note");
 NSButton *aware=after[@"settings.ts-aware-spelling"],*legacy=after[@"settings.legacy-spelling"];
 aware.state=NSControlStateValueOn;[aware sendAction:aware.action to:aware.target];Check(!spellNote.hidden,@"Spelling action creates a transient note");
 legacy.state=NSControlStateValueOn;[legacy sendAction:legacy.action to:legacy.target];Check(spellNote.hidden,@"Reverse spelling action clears note");
 [owner.settingsChangeNotes endSession];
 // Production encoding action and numeric edit/commit paths.
 [memory setObject:@"UTF-8 Unicode" forKey:EncodingKey];[memory setDouble:1 forKey:PdfMagnificationKey];[owner.settingsChangeNotes beginSession];
 __block BOOL sourceOpen=NO,pdfOpen=NO;owner.settingsChangeNotes.hasSourceWindow=^BOOL{return sourceOpen;};owner.settingsChangeNotes.hasPDFWindow=^BOOL{return pdfOpen;};
 NSPopUpButton *encoding=after[@"settings.262"];if(!encoding)encoding=[owner valueForKey:@"defaultEncodeMatrix"];
 [encoding removeAllItems];[encoding addItemWithTitle:@"UTF-8"];encoding.lastItem.tag=NSUTF8StringEncoding;[encoding addItemWithTitle:@"Mac Roman"];encoding.lastItem.tag=NSMacOSRomanStringEncoding;
 TSSettingsChangeNote *encodingNote=(id)Find(Find([panes[@"documents"] view],@"row.catalog.documents.0.0"),@"settings.change-note");
 [encoding selectItemWithTag:NSMacOSRomanStringEncoding];[owner encodingChanged:encoding];Check(encodingNote.hidden,@"Encoding action without source stays quiet");
 sourceOpen=YES;[encoding selectItemWithTag:NSUTF8StringEncoding];[owner encodingChanged:encoding];Check(encodingNote.hidden,@"Original encoding stays quiet");
 [encoding selectItemWithTag:NSMacOSRomanStringEncoding];[owner encodingChanged:encoding];Check(!encodingNote.hidden,@"Production encoding action shows inline warning");
 [owner configurePreferenceInputs];NSTextField *magnification=[owner valueForKey:@"magTextField"];
 TSSettingsChangeNote *zoomNote=(id)Find(Find([panes[@"preview"] view],@"row.catalog.preview.0.2"),@"settings.change-note");
 magnification.stringValue=@"125";[owner controlTextDidChange:[NSNotification notificationWithName:NSControlTextDidChangeNotification object:magnification]];
 Check([owner commitPreferenceField:magnification showError:NO reflect:YES] && fabs([memory doubleForKey:PdfMagnificationKey]-1.25)<0.00001 && zoomNote.hidden,@"Production zoom commit saves percentage and stays quiet without preview");
 pdfOpen=YES;magnification.stringValue=@"125";[owner controlTextDidChange:[NSNotification notificationWithName:NSControlTextDidChangeNotification object:magnification]];[owner commitPreferenceField:magnification showError:NO reflect:YES];Check(zoomNote.hidden,@"Production same-value commit is quiet");
 magnification.stringValue=@"150";[owner controlTextDidChange:[NSNotification notificationWithName:NSControlTextDidChangeNotification object:magnification]];[owner magChanged:magnification];Check(!zoomNote.hidden && fabs([memory doubleForKey:PdfMagnificationKey]-1.5)<0.00001,@"Production magnification action shows note after saving");
 magnification.stringValue=@"100";[owner controlTextDidChange:[NSNotification notificationWithName:NSControlTextDidChangeNotification object:magnification]];[owner magChanged:magnification];Check(zoomNote.hidden,@"Production magnification action clears note at opening value");
 [owner.settingsChangeNotes endSession];
 // Return commits through the actual NSTextField delegate and clamps percentages.
 magnification.stringValue=@"900";[owner controlTextDidChange:[NSNotification notificationWithName:NSControlTextDidChangeNotification object:magnification]];
 Check([owner control:magnification textShouldEndEditing:[NSText new]],@"Return permits a normalized valid percentage");
 Check([memory doubleForKey:PdfMagnificationKey]==4 && [magnification.stringValue isEqual:@"400"],@"Return normalizes 900 percent to the permitted 400 percent");
 // Grayscale and named/catalog colors must be converted before RGB components are saved.
 NSColorWell *cursor=[owner valueForKey:@"BlockCursorColorWell"];
 for(NSColor *color in @[[NSColor colorWithCalibratedWhite:0.37 alpha:0.6],NSColor.systemRedColor]) {
  cursor.color=color;@try {[owner BlockCursorColorChanged:cursor];} @catch(NSException *exception){Check(NO,@"Cursor action stores converted RGB from its sender");}NSColor *rgb=[color colorUsingColorSpace:NSColorSpace.genericRGBColorSpace];
  Check(!cursor.supportsAlpha,@"The block cursor color offers no opacity");
  Check(fabs([memory doubleForKey:BlockCursorRKey]-rgb.redComponent)<0.0001 && fabs([memory doubleForKey:BlockCursorGKey]-rgb.greenComponent)<0.0001 && fabs([memory doubleForKey:BlockCursorBKey]-rgb.blueComponent)<0.0001,@"Cursor action stores converted RGB from its sender");
  // The block cursor well is opaque; a theme well whose opacity is used keeps alpha.
  NSColorWell *themeWell=[NSColorWell new];themeWell.supportsAlpha=YES;themeWell.color=color;
  NSMutableDictionary *theme=[NSMutableDictionary dictionary];@try {[[TSColorSupport sharedInstance] changeColorValueInDictionary:theme forKey:@"probe" fromColorWell:themeWell];} @catch(NSException *exception){Check(NO,@"Theme wells store converted RGBA");}NSArray *saved=theme[@"probe"];
  Check(saved.count==4 && fabs([saved[0] doubleValue]-rgb.redComponent)<0.0001 && fabs([saved[1] doubleValue]-rgb.greenComponent)<0.0001 && fabs([saved[2] doubleValue]-rgb.blueComponent)<0.0001 && fabs([saved[3] doubleValue]-rgb.alphaComponent)<0.0001,@"Theme wells store converted RGBA");
 }
 // The Themes pane is detached; an unreadable theme still disables all of its wells.
 DetachedPaneHost *detached=[[DetachedPaneHost alloc]initWithDefaults:memory];detached.testPanes=panes;owner.settingsController=detached;
 [owner setValue:nil forKey:@"EditingColors"];[owner FillInColorWells];
 NSUInteger disabledWells=0;for(NSControl *control in after.allValues)if([control isKindOfClass:NSColorWell.class] && control.action!=@selector(BlockCursorColorChanged:)){Check(!control.enabled,@"Unreadable theme disables offscreen color wells");disabledWells++;}
 Check(disabledWells>=30 && cursor.enabled,@"Theme disabling covers all theme wells and preserves independent cursor color");
 [owner setAllThemeEditingEnabled:YES];for(NSControl *control in after.allValues)if([control isKindOfClass:NSColorWell.class])Check(control.enabled,@"Theme wells can be enabled again");owner.settingsController=nil;
 // Saving a PDF frame must update its own selection and preserve the source selection/value.
 NSWindow *pdf=[[NSWindow alloc]initWithContentRect:NSMakeRect(25,30,400,350) styleMask:NSWindowStyleMaskBorderless backing:NSBackingStoreBuffered defer:NO];
 [[TSWindowManager sharedInstance] setValue:pdf forKey:@"activePDFWindow"];
 NSMatrix *sourcePosition=[owner valueForKey:@"sourceWindowPosMatrix"],*pdfPosition=[owner valueForKey:@"pdfWindowPosMatrix"];
 [sourcePosition selectCellWithTag:1];[pdfPosition selectCellWithTag:1];[memory setInteger:1 forKey:DocumentWindowPosModeKey];[memory setObject:@"source sentinel" forKey:DocumentWindowFixedPosKey];
 [owner currentPdfWindowPosDefault:nil];
 Check(sourcePosition.selectedCell.tag==1 && [memory integerForKey:DocumentWindowPosModeKey]==1 && [[memory stringForKey:DocumentWindowFixedPosKey] isEqual:@"source sentinel"],@"Saving PDF position preserves source selection and value");
 Check(pdfPosition.selectedCell.tag==PdfWindowPosFixed && [memory integerForKey:PdfWindowPosModeKey]==PdfWindowPosFixed && [[memory stringForKey:PdfWindowFixedPosKey] isEqual:pdf.stringWithSavedFrame],@"Saving PDF position selects and stores PDF fixed position");
 [[TSWindowManager sharedInstance] setValue:nil forKey:@"activePDFWindow"];
 // Radio actions are dispatched through the actual targets without a window.
 for(NSNumber *method in @[@NO,@YES,@NO,@YES]) {
  NSButton *choice=after[method.boolValue?@"settings.ts-aware-spelling":@"settings.legacy-spelling"];
  [memory.values removeAllObjects];
  [memory.values addEntriesFromDictionary:@{@"TurnOffCommandSpellCheck":@NO,@"TurnOffParameterSpellCheck":@YES,@"TurnOffCommentSpellCheck":@YES,@"sentinel":@"keep"}];
  NSMutableDictionary *expected=[memory.values mutableCopy];expected[@"TeXAwareSpellChecking"]=method;
  choice.state=NSControlStateValueOn;
  Check([choice sendAction:choice.action to:choice.target],@"Spelling radio action dispatches");
  Check([memory.values isEqual:expected],@"Radio writes only the selected method, retaining nondefault child values");
  Check([memory boolForKey:@"TeXAwareSpellChecking"]==method.boolValue,@"Radio choice is saved");
  Check(((NSButton *)after[@"settings.ts-aware-spelling"]).state==method.boolValue && ((NSButton *)after[@"settings.legacy-spelling"]).state==!method.boolValue,@"Exactly one spelling method is selected");
 }
 NSDictionary *families=@{@"settings.RtB-ZN-uCk":@[@"settings.Wrg-WR-c6H",@"settings.l7y-UX-7WO",@"settings.uve-Zu-06Q"],@"settings.437":@[@"settings.434"],@"settings.RVR-YO-Xhy":@[@"settings.jhC-up-cya"]};
 for(NSString *parent in families)for(NSNumber *value in @[@YES,@NO,@YES]) {
  [memory.values removeAllObjects];[memory.values addEntriesFromDictionary:@{@"KeepBackup":@YES,@"sentinel":@"keep"}];
  NSPopUpButton *popup=after[@"settings.434"];Check(popup.numberOfItems>1,@"Popup has a nondefault choice");[popup selectItemAtIndex:popup.numberOfItems-1];
  NSInteger selected=popup.indexOfSelectedItem;
  NSButton *backup=after[@"settings.jhC-up-cya"];backup.state=NSControlStateValueOn;
  NSButton *button=after[parent];button.state=value.boolValue;
  NSMutableDictionary *expectedWrites=[memory.values mutableCopy];
  NSString *parentKey=[parent isEqual:@"settings.RtB-ZN-uCk"]?BlockCursorKey:[parent isEqual:@"settings.437"]?PdfColorMapKey:AutoSaveEnabledKey;
  expectedWrites[parentKey]=value;
  BOOL expected=[parent isEqual:@"settings.RVR-YO-Xhy"]?!value.boolValue:value.boolValue;
  for(NSString *child in families[parent])((NSControl *)after[child]).enabled=!expected;
  Check([button sendAction:button.action to:button.target],@"Parent action dispatches through original owner");
  Check([memory.values isEqual:expectedWrites],@"Parent action writes only its own key");
  Check(popup.indexOfSelectedItem==selected && backup.state==NSControlStateValueOn,@"Nondefault dependent UI values survive parent actions");
  for(NSString *child in families[parent])Check(((NSControl *)after[child]).enabled==([parent isEqual:@"settings.RtB-ZN-uCk"]?YES:expected),@"Parent action respects global versus per-document dependencies");
 }
 for(NSString *parent in @[@"settings.G6V-Sw-jFT",@"settings.MBq-SG-G54"]) {
  NSButton *button=after[parent];BOOL expected=button.tag!=0;
  for(NSString *child in @[@"settings.iRm-g2-CpD",@"settings.zvK-4Q-HJ5"])((NSControl *)after[child]).enabled=!expected;
  Check([button sendAction:button.action to:button.target],@"Unified window action dispatches");
  for(NSString *child in @[@"settings.iRm-g2-CpD",@"settings.zvK-4Q-HJ5"])Check(((NSControl *)after[child]).enabled,@"Source position remains editable for per-document combined windows");
 }
 // Individual and profile changes share a single notification dependency table.
 __block NSMutableArray<NSString *> *received=[NSMutableArray array];
 id observer=[NSNotificationCenter.defaultCenter addObserverForName:nil object:owner queue:nil usingBlock:^(NSNotification *n){[received addObject:n.name];}];
 NSDictionary *actionEffects=@{@"settings.cell.839":@"DocumentSyntaxColorNotification",@"settings.cell.cgA-o7-Bdw":@"NeedsForRecolorNotification",@"settings.cell.f1k-jx-ley":@"NeedsForRecolorNotification",@"settings.cell.842":@"DocumentAutoCompleteNotification",@"settings.cell.843":@"DocumentBibDeskCompleteNotification"};
 for(NSString *controlID in actionEffects){NSButton *button=after[controlID];[received removeAllObjects];button.state=!button.state;[button sendAction:button.action to:button.target];Check([received isEqual:@[Required(actionEffects[controlID])]],@"Individual action sends exactly the approved runtime notification");}
 NSButton *invisible=[owner valueForKey:@"showInvisibleCharactersButton"];[received removeAllObjects];invisible.state=!invisible.state;[owner showInvisibleCharacterButtonPressed:invisible];Check([received isEqual:@[@"NeedsForRecolorNotification"]],@"Invisible-character default requests recoloring");
 [received removeAllObjects];TSPostPreferenceNotifications([NSSet setWithArray:@[expl3SyntaxColoringKey,ShowInvisibleCharactersEnabledKey,SpaceCharacterKindKey]],owner);
 Check([received isEqual:@[@"NeedsForRecolorNotification"]],@"Profile batch coalesces the same recolor effects once");
 [NSNotificationCenter.defaultCenter removeObserver:observer];
 // Every parent value changes availability only; child state survives both ways.
 for(NSNumber *value in @[@YES,@NO,@YES]){
  BOOL on=value.boolValue;for(NSString *key in @[BlockCursorKey,PdfColorMapKey,SourceAndPreviewInSameWindowKey,AutoSaveEnabledKey,@"TeXAwareSpellChecking"])[memory setBool:on forKey:key];
  NSPopUpButton *popup=after[@"settings.434"];[popup selectItemAtIndex:popup.numberOfItems-1];NSInteger selected=popup.indexOfSelectedItem;
  NSDictionary *saved=[memory.values copy];[owner updateSettingsDependenciesFromDefaults:memory];[owner updateSpellingControlsFromDefaults:memory];
  Check(popup.indexOfSelectedItem==selected,@"Dependency refresh keeps popup display");
  for(NSString *key in @[@"settings.Wrg-WR-c6H",@"settings.l7y-UX-7WO",@"settings.uve-Zu-06Q",@"settings.434",@"settings.iRm-g2-CpD",@"settings.zvK-4Q-HJ5",@"settings.ts-edit-spelling"])Check([(NSControl *)after[key] isEnabled]==([@[@"settings.434",@"settings.ts-edit-spelling"] containsObject:key]?on:YES),[@"Dependency follows approved scope: " stringByAppendingString:key]);
  Check([(NSControl *)after[@"settings.jhC-up-cya"] isEnabled]==!on,@"Backup depends on autosave off");
  for(NSString *key in @[@"settings.cell.teg-0p-Q8J",@"settings.cell.3eF-XA-ahc",@"settings.cell.8Wq-gx-FqO"])Check([(NSControl *)after[key] isEnabled]==!on,@"Legacy children use the legacy method");
  for(NSString *key in @[@"settings.cell.cgA-o7-Bdw",@"settings.cell.f1k-jx-ley",@"settings.cell.845",@"settings.949"])Check([(NSControl *)after[key] isEnabled],@"Independent settings stay available");
  Check([saved isEqual:memory.values],@"Dependencies never rewrite saved values");
 }
 puts("PASS: ten categories, complete control migration, geometry and dependency state");
}return 0;}
