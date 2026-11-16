// The toolbar of a document window (TSToolbar.m, production code) in a window that is never shown.
// run-toolbar-overflow-priorities.py builds it.
//
//   ToolbarOverflow settle <items> <width>   lays the toolbar out 40 times at the width and prints
//                                            "steady" or "OSCILLATES" with the items shown each time
//   ToolbarOverflow checks                    the priorities the toolbar gives, and when it gives them
//
// <items> is a comma-separated list: Typeset, Tags, Labels, AutoComplete, ShowFullPath, ColorIndex and
// Sharing are the custom views of the nib, built at the nib's sizes and styled as TSToolbarController
// styles them on macOS 26 and later; Split and img0…img9 are image items; flex is a flexible space;
// a name ending in "!" keeps a priority of its own (NSToolbarItemVisibilityPriorityUser).
#import <Cocoa/Cocoa.h>
#import "TSToolbar.h"

static int failures = 0;
static void check(BOOL ok, NSString *what) {
    if (!ok) { failures++; fprintf(stderr, "FAIL: %s\n", what.UTF8String); }
}

@interface Items : NSObject <NSToolbarDelegate>
@property NSArray<NSString *> *identifiers;
@end

@implementation Items
- (NSArray<NSToolbarItemIdentifier> *)toolbarDefaultItemIdentifiers:(NSToolbar *)toolbar { return self.identifiers; }
- (NSArray<NSToolbarItemIdentifier> *)toolbarAllowedItemIdentifiers:(NSToolbar *)toolbar
{
    return [self.identifiers arrayByAddingObjectsFromArray:@[@"img8", @"img9", NSToolbarFlexibleSpaceItemIdentifier]];
}
- (void)noop:(id)sender {}

static NSButton *Check(NSString *title, CGFloat width, BOOL on, BOOL message)
{
    NSButton *button = [NSButton checkboxWithTitle:title target:nil action:nil];
    button.frame = NSMakeRect(0, 0, width, 18);
    button.state = on ? NSControlStateValueOn : NSControlStateValueOff;
    button.font = message ? [NSFont messageFontOfSize:0] : [NSFont systemFontOfSize:0];
    return button;
}

static NSPopUpButton *PullDown(NSString *title, CGFloat width)
{
    NSPopUpButton *button = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(0, 0, width, 26) pullsDown:YES];
    [button addItemWithTitle:title];
    button.font = [NSFont messageFontOfSize:0];
    return button;
}

- (NSView *)viewFor:(NSString *)name
{
    if ([name isEqual:@"Typeset"]) {
        NSButton *button = [NSButton buttonWithTitle:@"タイプセット" target:nil action:nil];
        button.frame = NSMakeRect(0, 0, 118, 32);
        return button;
    }
    if ([name isEqual:@"Sharing"]) {
        NSButton *button = [NSButton buttonWithImage:[NSImage imageNamed:NSImageNameShareTemplate] target:nil action:nil];
        button.frame = NSMakeRect(0, 0, 48, 32);
        button.imagePosition = NSImageOnly;
        button.imageScaling = NSImageScaleProportionallyDown;
        return button;
    }
    if ([name isEqual:@"Tags"]) return PullDown(@"タグ", 71);
    if ([name isEqual:@"Labels"]) return PullDown(@"ラベル", 87);
    if ([name isEqual:@"AutoComplete"]) return Check(@"キーバインド", 100, NO, YES);
    if ([name isEqual:@"ShowFullPath"]) return Check(@"フルパス表示", 100, YES, NO);
    if ([name isEqual:@"ColorIndex"]) return Check(@"索引の色づけ", 95, NO, NO);
    return nil;
}

- (NSToolbarItem *)toolbar:(NSToolbar *)toolbar itemForItemIdentifier:(NSString *)identifier willBeInsertedIntoToolbar:(BOOL)flag
{
    NSToolbarItem *item = [[NSToolbarItem alloc] initWithItemIdentifier:identifier];
    NSString *name = [identifier hasSuffix:@"!"] ? [identifier substringToIndex:identifier.length - 1] : identifier;
    item.label = name;
    if ([identifier hasSuffix:@"!"])
        item.visibilityPriority = NSToolbarItemVisibilityPriorityUser;
    NSView *view = [self viewFor:name];
    if (view) {
        // As TSToolbarController's makeToolbarItemWithItemIdentifier:key:customView: on macOS 26 and later.
        view.translatesAutoresizingMaskIntoConstraints = NO;
        item.view = view;
        if ([view isKindOfClass:NSButton.class] && ![view isKindOfClass:NSPopUpButton.class]) {
            [(NSButton *)view setBezelStyle:NSBezelStyleAutomatic];
            item.bordered = YES;
            if ([name isEqual:@"Typeset"])
                item.style = NSToolbarItemStyleProminent;
        }
        return item;
    }
    NSArray *symbols = @[@"folder", @"doc", @"trash", @"star", @"bell", @"gear", @"tag", @"flag", @"book", @"pencil"];
    NSString *symbol = [name isEqual:@"Split"] ? @"rectangle.split.1x2" : symbols[[name substringFromIndex:3].integerValue % 10];
    item.image = [NSImage imageWithSystemSymbolName:symbol accessibilityDescription:name];
    item.target = self;
    item.action = @selector(noop:);
    return item;
}
@end

static NSArray<NSString *> *Identifiers(NSString *list)
{
    NSMutableArray *identifiers = [NSMutableArray array];
    for (NSString *name in [list componentsSeparatedByString:@","])
        [identifiers addObject:[name isEqual:@"flex"] ? NSToolbarFlexibleSpaceItemIdentifier : name];
    return identifiers;
}

static NSWindow *Window(Items *items, CGFloat width)
{
    NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, width, 300)
        styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskMiniaturizable | NSWindowStyleMaskResizable | NSWindowStyleMaskFullSizeContentView
        backing:NSBackingStoreBuffered defer:NO];
    window.releasedWhenClosed = NO;
    window.title = @"名称未設定";
    window.toolbarStyle = NSWindowToolbarStyleExpanded;
    // Toolbars with the same identifier share their items: each window has its own.
    static int windows = 0;
    TSToolbar *toolbar = [[TSToolbar alloc] initWithIdentifier:[NSString stringWithFormat:@"ToolbarOverflow-%d", ++windows]];
    toolbar.delegate = items;
    toolbar.displayMode = NSToolbarDisplayModeIconOnly;
    window.toolbar = toolbar;
    return window;
}

static void Spin(NSWindow *window)
{
    [window.contentView.superview layoutSubtreeIfNeeded];
    [window displayIfNeeded];
    [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
}

static NSString *Shown(NSWindow *window)
{
    NSMutableArray *names = [NSMutableArray array];
    for (NSToolbarItem *item in window.toolbar.visibleItems)
        [names addObject:[item.itemIdentifier isEqual:NSToolbarFlexibleSpaceItemIdentifier] ? @"flex" : item.itemIdentifier];
    return [names componentsJoinedByString:@","];
}

static NSArray<NSNumber *> *Priorities(NSToolbar *toolbar)
{
    return [toolbar.items valueForKey:@"visibilityPriority"];
}

// The priorities come soon after a change, not at once: waits up to half a second for them.
static BOOL Soon(NSWindow *window, NSArray<NSNumber *> *(^expected)(void))
{
    for (int i = 0; i < 50; i++) {
        Spin(window);
        if ([Priorities(window.toolbar) isEqual:expected()])
            return YES;
    }
    return NO;
}

static void Settle(NSString *list, CGFloat width)
{
    Items *items = [Items new];
    items.identifiers = Identifiers(list);
    NSWindow *window = Window(items, width);
    NSMutableOrderedSet *shown = [NSMutableOrderedSet orderedSet];
    for (int pass = 0; pass < 40; pass++) {
        Spin(window);
        if (pass >= 5)
            [shown addObject:Shown(window)];
    }
    printf("%g %s %s\n", width, shown.count > 1 ? "OSCILLATES" : "steady", [[shown.array componentsJoinedByString:@" | "] UTF8String]);
    [window close];
}

static void Checks(void)
{
    const NSInteger high = NSToolbarItemVisibilityPriorityHigh, user = NSToolbarItemVisibilityPriorityUser;
    check(TSToolbarArrangesVisibilityPriorities(), @"the toolbar gives priorities on this macOS");
    check(TSToolbarVisibilityPriority(0, 2) == 0 && TSToolbarVisibilityPriority(2, 2) == 0 && TSToolbarVisibilityPriority(3, 2) == high,
          @"high after the last flexible space, standard up to it");
    check(TSToolbarVisibilityPriority(0, -1) == 0 && TSToolbarVisibilityPriority(4, -1) == 4, @"without a flexible space, rising from left to right");

    // The priorities are given once the toolbar has its items, and an item keeps a higher priority of its own.
    Items *items = [Items new];
    items.identifiers = Identifiers(@"img0,img1!,flex,img2,flex,img3,img4");
    NSWindow *window = Window(items, 900);
    check(Soon(window, ^{ return @[@0, @(user), @0, @0, @0, @(high), @(high)]; }),
          [NSString stringWithFormat:@"priorities with two flexible spaces: %@", Priorities(window.toolbar)]);

    // Adding and removing items gives the priorities again.
    [window.toolbar insertItemWithItemIdentifier:@"img8" atIndex:7];
    check(Soon(window, ^{ return @[@0, @(user), @0, @0, @0, @(high), @(high), @(high)]; }), @"an item added at the end is kept before the others");
    [window.toolbar removeItemAtIndex:4];
    [window.toolbar removeItemAtIndex:2];
    check(Soon(window, ^{ return @[@0, @(user), @2, @3, @4, @5]; }),
          [NSString stringWithFormat:@"without flexible spaces, rising from left to right: %@", Priorities(window.toolbar)]);
    [window.toolbar insertItemWithItemIdentifier:NSToolbarFlexibleSpaceItemIdentifier atIndex:3];
    check(Soon(window, ^{ return @[@0, @(user), @0, @0, @(high), @(high), @(high)]; }),
          [NSString stringWithFormat:@"a flexible space added again: %@", Priorities(window.toolbar)]);
    [window close];

    // A change that no notification told of is caught when the toolbar validates its items.
    items = [Items new];
    items.identifiers = Identifiers(@"img0,flex,img1");
    window = Window(items, 900);
    check(Soon(window, ^{ return @[@0, @0, @(high)]; }), [NSString stringWithFormat:@"priorities of a small toolbar: %@", Priorities(window.toolbar)]);
    window.toolbar.items.lastObject.visibilityPriority = NSToolbarItemVisibilityPriorityStandard;
    [window.toolbar setValue:nil forKey:@"_arrangedIdentifiers"];
    [window.toolbar validateVisibleItems];
    check([Priorities(window.toolbar).lastObject integerValue] == high, @"validation gives the priorities again");
    [window close];
}

int main(int argc, char **argv)
{
    @autoreleasepool {
        [NSApplication sharedApplication];
        [NSApp setActivationPolicy:NSApplicationActivationPolicyProhibited];
        if (argc > 3 && !strcmp(argv[1], "settle")) {
            Settle(@(argv[2]), atof(argv[3]));
            return 0;
        }
        if (argc > 1 && !strcmp(argv[1], "checks")) {
            Checks();
            if (!failures)
                printf("PASS: the priorities of the items, given when the toolbar gets its items, when they change and when it validates them\n");
            return failures ? 1 : 0;
        }
        fprintf(stderr, "usage: ToolbarOverflow settle <items> <width> | checks\n");
        return 2;
    }
}
