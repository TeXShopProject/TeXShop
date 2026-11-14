// SPDX-License-Identifier: GPL-2.0-or-later
#import <Cocoa/Cocoa.h>
#import <objc/runtime.h>
#import "TestAppKitIsolation.h"
#import "TSPrefPaneController.h"
#import "TSPrefPaneLayout.h"
#import "TSPreferences+Panes.h"
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wincomplete-implementation"
@implementation TSPreferences
@end
#pragma clang diagnostic pop
static NSBundle *fixtureBundle;
static id FixtureMainBundle(id receiver, SEL selector) { return fixtureBundle; }
#import "TSDockIconController.h"
#import "TSDockIcon.h"
@interface DockTileProbe : NSObject
@property NSSize size;
@property NSView *contentView;
@property(copy) NSString *badgeLabel;
@end
@implementation DockTileProbe
- (void)display {}
@end
static DockTileProbe *dockTile;
static id IsolatedDockTile(id object, SEL selector) { return dockTile; }
static void Check(BOOL value, NSString *message) { if (!value) { fprintf(stderr,"FAIL: %s\n",message.UTF8String); exit(1); } }
static NSUInteger Walk(NSView *view) {
    NSUInteger count = 1;
    Check(!view.window.visible, @"No test window is visible");
    for (NSView *child in view.subviews) count += Walk(child);
    return count;
}
static NSView *Find(NSView *view, NSString *identifier) {
    if ([view.identifier isEqualToString:identifier]) return view;
    for (NSView *child in view.subviews) { NSView *found = Find(child, identifier); if (found) return found; }
    return nil;
}
@interface ActionProbe : NSObject
@property SEL received;
@property id sender;
@property NSUInteger calls;
@end
@implementation ActionProbe
- (NSMethodSignature *)methodSignatureForSelector:(SEL)selector { return [super methodSignatureForSelector:selector] ?: [NSMethodSignature signatureWithObjCTypes:"v@:@"]; }
- (void)forwardInvocation:(NSInvocation *)invocation { self.calls++;self.received=invocation.selector;__unsafe_unretained id sender=nil;[invocation getArgument:&sender atIndex:2];self.sender=sender; }
@end
static id Object(TSPrefPaneController *pane, NSDictionary *entry) {
    NSView *view=Find(pane.view,entry[@"view"]);NSString *kind=entry[@"kind"];
    if ([kind isEqual:@"window"]) return pane.view.window;
    if ([kind isEqual:@"cell"]) return ((NSControl *)view).cell;
    if ([kind isEqual:@"prototype"]) return ((NSMatrix *)view).prototype;
    if ([kind isEqual:@"matrix"]) return [((NSMatrix *)view) cellAtRow:[entry[@"row"] integerValue] column:[entry[@"column"] integerValue]];
    if ([kind isEqual:@"menu"]) return ((NSPopUpButton *)view).menu;
    if ([kind isEqual:@"menuItem"]) return [((NSPopUpButton *)view).menu itemAtIndex:[entry[@"index"] integerValue]];
    return view;
}
static void CheckStrings(TSPrefPaneController *pane, NSArray<NSDictionary *> *expected) {
    for (NSDictionary *entry in expected) {
        id object=Object(pane,entry);
        Check(object!=nil, [NSString stringWithFormat:@"Localized object exists: %@",entry]);
        id actual=[object valueForKey:entry[@"property"]];
        Check([actual isEqual:entry[@"value"]], [NSString stringWithFormat:@"Localized %@: expected %@, got %@",entry[@"key"],entry[@"value"],actual]);
    }
}
static void CheckActions(TSPrefPaneController *pane, NSArray<NSDictionary *> *expected) {
    ActionProbe *probe=[ActionProbe new];pane.preferences=(TSPreferences *)probe;
    for(NSDictionary *entry in expected) {
        id control=Object(pane,entry);SEL action=NSSelectorFromString(entry[@"value"]);
        Check([control action]==action && [control target]==pane,@"Nib action targets its pane");
        probe.received=NULL;probe.sender=nil;probe.calls=0;
        NSInvocation *invocation=[NSInvocation invocationWithMethodSignature:[pane methodSignatureForSelector:action]];
        invocation.selector=action;invocation.target=pane;[invocation setArgument:&control atIndex:2];[invocation invoke];
        Check(probe.calls==1 && probe.received==action && probe.sender==control,@"Pane forwards the original action and sender exactly once");
    }
    pane.preferences=nil;
}
static void CheckGeometry(NSView *view) {
    Check(![view.identifier isEqual:@"heading.settings.3cH-6c-fhq"] && ![view.identifier isEqual:@"heading.settings.PTb-79-UFr"],@"Retired Basic and Additional theme headings are absent");
    if (view.hidden) return;
    for(NSView *child in view.subviews) {
        if(child.hidden)continue;
        Check(NSContainsRect(NSInsetRect(view.bounds,-1,-1),[child alignmentRectForFrame:child.frame]),[NSString stringWithFormat:@"Control %@ %@ is inside parent %@ %@",child.identifier,NSStringFromRect(child.frame),NSStringFromClass(view.class),NSStringFromRect(view.bounds)]);
        CheckGeometry(child);
    }
    if([view isKindOfClass:NSButton.class] && ![view isKindOfClass:NSPopUpButton.class]) {
        NSButton *button=(NSButton *)view;
        Check(button.imagePosition==NSImageOnly || button.cell.cellSize.width<=NSWidth(button.frame)+2,[NSString stringWithFormat:@"Button title fits: %@ %.1f <= %.1f",button.title,button.cell.cellSize.width,NSWidth(button.frame)]);
    }
    if([view isKindOfClass:NSMatrix.class]) {
        NSMatrix *matrix=(NSMatrix *)view;
        for(NSInteger row=0;row<matrix.numberOfRows;row++)for(NSInteger column=0;column<matrix.numberOfColumns;column++) {
            NSCell *cell=[matrix cellAtRow:row column:column];NSRect frame=[matrix cellFrameAtRow:row column:column];
            Check(cell.cellSize.width<=NSWidth(frame)+1,[NSString stringWithFormat:@"Matrix title fits: %@ %.1f <= %.1f",cell.title,cell.cellSize.width,NSWidth(frame)]);
        }
    }
    if([view isKindOfClass:NSBox.class]) {
        NSBox *box=(NSBox *)view;
        Check(box.cornerRadius==[TSSettingsGroupStyle cornerRadiusForMajorVersion:NSProcessInfo.processInfo.operatingSystemVersion.majorVersion],@"Shared group appearance applied");
    }
    if([view isKindOfClass:NSStackView.class]) {
        NSArray *children=((NSStackView *)view).arrangedSubviews;
        for(NSUInteger a=0;a<children.count;a++)for(NSUInteger b=a+1;b<children.count;b++) {
            NSView *x=children[a],*y=children[b];
            if(!x.hidden && !y.hidden)Check(!NSIntersectsRect(NSInsetRect(x.frame,1,1),NSInsetRect(y.frame,1,1)),@"Arranged controls do not overlap");
        }
    }
}
int main(int argc, const char **argv) { @autoreleasepool {
    TSInstallAppKitIsolation();
    dockTile=[DockTileProbe new];dockTile.size=NSMakeSize(128,128);dockTile.badgeLabel=@"7";
    TSReplaceTestMethod(class_getInstanceMethod(NSApplication.class,@selector(dockTile)),(IMP)IsolatedDockTile);
    [NSApplication sharedApplication];
    Check(argc >= 2, @"Resource bundle argument");
    NSBundle *bundle = [NSBundle bundleWithPath:[NSString stringWithUTF8String:argv[1]]];
    Check(bundle != nil, @"Resource bundle loads");
    NSData *data = [NSData dataWithContentsOfFile:[bundle.resourcePath stringByAppendingPathComponent:@"expected.json"]];
    NSDictionary *expected = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
    Check(expected != nil, @"Localization expectations load");
    fixtureBundle=bundle;
    IMP mainBundle=method_setImplementation(class_getClassMethod(NSBundle.class,@selector(mainBundle)),(IMP)FixtureMainBundle);
    TSPreferences *coordinator=[TSPreferences new];
    NSArray<TSPrefPaneController *> *panes=[coordinator makeSettingsPanes];
    method_setImplementation(class_getClassMethod(NSBundle.class,@selector(mainBundle)),mainBundle);
    for (NSString *name in expected[@"Categories"]) {
        NSString *className=[NSString stringWithFormat:@"TSPref%@Controller",name];
        TSPrefPaneController *found=nil;
        for(TSPrefPaneController *pane in panes) if([NSStringFromClass(pane.class) isEqual:className]) found=pane;
        Check(found!=nil && [found.categoryIdentifier isEqual:expected[@"Categories"][name]],@"Production category ID belongs to its fixed pane class");
    }
    Check([TSSettingsGroupStyle cornerRadiusForMajorVersion:14]==10 && [TSSettingsGroupStyle cornerRadiusForMajorVersion:15]==10 && [TSSettingsGroupStyle cornerRadiusForMajorVersion:26]==12,@"Group radii match the supported OS versions");
    Check(panes.count==10,@"Production factory eagerly owns all ten panes");
    for(NSDictionary *entry in expected[@"Bridge"]) {
        TSPrefPaneController *pane=nil;
        for(TSPrefPaneController *candidate in panes)if([NSStringFromClass(candidate.class) isEqual:entry[@"class"]])pane=candidate;
        Ivar ivar=class_getInstanceVariable(TSPreferences.class,[entry[@"ivar"] UTF8String]);
        Check(ivar!=NULL && pane!=nil,@"Production bridge references a real coordinator ivar and pane");
        Check(object_getIvar(coordinator,ivar)==[pane valueForKey:entry[@"property"]],@"Production bridge assigns each original outlet to its matching pane control");
        Check(pane.preferences==coordinator,@"Every pane forwards to its owning coordinator");
    }
    NSArray *names = @[@"Source",@"Editor",@"Preview",@"Console",@"Typesetting",@"Engines",@"MiscOne",@"MiscTwo",@"Themes",@"ThemeName"];
    NSUInteger outlets = 0;
    for (NSString *name in names) {
        Class cls = NSClassFromString([NSString stringWithFormat:@"TSPref%@Controller", name]);
        TSPrefPaneController *pane = [[cls alloc] initWithNibName:[@"Settings" stringByAppendingString:name] bundle:bundle];
        NSView *view = pane.view;
        Check(view != nil && pane.nibObjects.count > 0, @"Pane retains its nib objects");
        CheckStrings(pane, expected[name]);
        CheckStrings(pane, expected[[name stringByAppendingString:@"Tags"]]);
        CheckActions(pane, expected[[name stringByAppendingString:@"Actions"]]);
        // Dock behavior is exercised in the General category in SettingsProductShell.m.
        unsigned int count = 0;
        objc_property_t *properties = class_copyPropertyList(cls, &count);
        for (unsigned int index = 0; index < count; index++) {
            NSString *property = @(property_getName(properties[index]));
            Check([pane valueForKey:property] != nil, [@"Connected outlet: " stringByAppendingString:property]);
            NSString *attributes=@(property_getAttributes(properties[index]));
            NSArray *type=[attributes componentsSeparatedByString:@"\""];
            if(type.count>1)Check([[pane valueForKey:property] isKindOfClass:NSClassFromString(type[1])],@"Outlet has its declared class");
            outlets++;
        }
        free(properties);
        {
            NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0,0,700,700) styleMask:NSWindowStyleMaskBorderless backing:NSBackingStoreBuffered defer:NO];
            NSView *parent = window.contentView;
            [parent addSubview:view];
            NSLayoutConstraint *width=[view.widthAnchor constraintEqualToConstant:[name isEqual:@"ThemeName"] ? 420 : 620];
            [NSLayoutConstraint activateConstraints:@[width, [view.leadingAnchor constraintEqualToAnchor:parent.leadingAnchor], [view.topAnchor constraintEqualToAnchor:parent.topAnchor]]];
            for (NSNumber *wide in @[@NO,@YES]) {
                width.constant=[name isEqual:@"ThemeName"] ? 420 : (wide.boolValue ? 900 : 620);
                for (NSAppearanceName appearance in @[NSAppearanceNameAqua,NSAppearanceNameDarkAqua]) {
                    window.appearance=[NSAppearance appearanceNamed:appearance];
                    [parent layoutSubtreeIfNeeded]; CheckGeometry(view);
                    for(NSDictionary *heading in expected[[name stringByAppendingString:@"Headings"]]) {
                        NSTextField *label=(NSTextField *)Find(view,heading[@"id"]);
                        Check(label!=nil && [label.stringValue isEqual:heading[@"title"]] && !label.hidden && NSHeight(label.frame)>0,@"Each localized group heading remains visible");
                    }
                    if([name isEqual:@"MiscOne"]) {
                        NSView *parentControl=Find(view,@"settings.RVR-YO-Xhy"),*childControl=Find(view,@"settings.jhC-up-cya");
                        CGFloat parentX=NSMinX([parentControl convertRect:parentControl.bounds toView:view]);
                        CGFloat childX=NSMinX([childControl convertRect:childControl.bounds toView:view]);
                        Check(fabs(childX-parentX-24)<1,@"Backup setting retains one explicit level of indentation");
                    }
                    if (argc > 2 && !wide.boolValue) {
                        NSString *folder=[NSString stringWithUTF8String:argv[2]];
                        NSString *file=[folder stringByAppendingPathComponent:[NSString stringWithFormat:@"%@-%@",name,appearance]];
                        [view display];
                        NSBitmapImageRep *bitmap=[view bitmapImageRepForCachingDisplayInRect:view.bounds];
                        [view cacheDisplayInRect:view.bounds toBitmapImageRep:bitmap];
                        NSData *png=[bitmap representationUsingType:NSBitmapImageFileTypePNG properties:@{}];
                        Check([png writeToFile:[file stringByAppendingPathExtension:@"png"] atomically:YES],@"Offscreen bitmap written");
                        Check([[view dataWithPDFInsideRect:view.bounds] writeToFile:[file stringByAppendingPathExtension:@"pdf"] atomically:YES],@"Offscreen PDF written");
                    }
                }
            }
            printf("%s views=%lu: minimum/wide and light/dark geometry passed\n",name.UTF8String,(unsigned long)Walk(view));
            [view removeFromSuperview];
        }
    }
    // 170 migrated from the legacy Preferences window and 4 added since.
    Check(outlets == 174, @"Every typed outlet loads");
    puts("PASS: 11 panes and 174 typed outlets");
} return 0; }
