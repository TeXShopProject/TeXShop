// The toolbar of a document window (TSToolbar.m, production code) opening its customization sheet,
// in windows that are never shown. run-toolbar-customization-sheet.py builds it.
//
// The sheet itself is not opened: NSToolbar's own runCustomizationPalette:, which TSToolbar calls,
// is replaced by one that notes the style and the frame of the window at that moment. The version
// of macOS that TSToolbar reads is given on the command line:
//
//   ToolbarCustomizationSheet <major version of macOS>
#import <Cocoa/Cocoa.h>
#import <objc/runtime.h>
#import "TSToolbar.h"

static int failures = 0;
static void check(BOOL ok, NSString *what) {
    if (!ok) { failures++; fprintf(stderr, "FAIL: %s\n", what.UTF8String); }
}

static NSInteger fakeMajorVersion;
static NSOperatingSystemVersion FakeVersion(id self, SEL _cmd) {
    return (NSOperatingSystemVersion){fakeMajorVersion, 0, 0};
}

// What NSToolbar's own runCustomizationPalette: saw.
static NSInteger sheets;
static NSWindowToolbarStyle styleAtSheet;
static NSRect frameAtSheet;
static void NotedSheet(NSToolbar *self, SEL _cmd, id sender) {
    sheets++;
    for (NSWindow *window in NSApp.windows)
        if (window.toolbar == self) {
            styleAtSheet = window.toolbarStyle;
            frameAtSheet = window.frame;
        }
}

@interface Items : NSObject <NSToolbarDelegate>
@end

@implementation Items
- (NSArray<NSToolbarItemIdentifier> *)toolbarDefaultItemIdentifiers:(NSToolbar *)toolbar
{
    return @[@"img0", @"img1", NSToolbarFlexibleSpaceItemIdentifier, @"img2"];
}
- (NSArray<NSToolbarItemIdentifier> *)toolbarAllowedItemIdentifiers:(NSToolbar *)toolbar
{
    return [self toolbarDefaultItemIdentifiers:toolbar];
}
- (NSToolbarItem *)toolbar:(NSToolbar *)toolbar itemForItemIdentifier:(NSToolbarItemIdentifier)identifier willBeInsertedIntoToolbar:(BOOL)flag
{
    NSToolbarItem *item = [[NSToolbarItem alloc] initWithItemIdentifier:identifier];
    item.label = identifier;
    item.image = [NSImage imageWithSystemSymbolName:@"doc" accessibilityDescription:identifier];
    return item;
}
@end

static NSString *StyleName(NSWindowToolbarStyle style) {
    switch (style) {
        case NSWindowToolbarStyleAutomatic: return @"automatic";
        case NSWindowToolbarStyleExpanded: return @"expanded";
        case NSWindowToolbarStylePreference: return @"preference";
        case NSWindowToolbarStyleUnified: return @"unified";
        case NSWindowToolbarStyleUnifiedCompact: return @"unified compact";
    }
    return @"?";
}

int main(int argc, const char **argv)
{
    @autoreleasepool {
        if (argc != 2)
            return 2;
        fakeMajorVersion = atoi(argv[1]);
        [NSApplication sharedApplication];
        method_setImplementation(class_getInstanceMethod(object_getClass(NSProcessInfo.processInfo), @selector(operatingSystemVersion)), (IMP)FakeVersion);
        method_setImplementation(class_getInstanceMethod(NSToolbar.class, @selector(runCustomizationPalette:)), (IMP)NotedSheet);
        check(NSProcessInfo.processInfo.operatingSystemVersion.majorVersion == fakeMajorVersion, @"the version of macOS is not replaced");

        // Which windows get the unified style while the sheet is made.
        NSWindowToolbarStyle styles[] = {NSWindowToolbarStyleAutomatic, NSWindowToolbarStyleExpanded, NSWindowToolbarStylePreference,
                                         NSWindowToolbarStyleUnified, NSWindowToolbarStyleUnifiedCompact};
        for (NSInteger major = 14; major <= 28; major++)
            for (int i = 0; i < 5; i++) {
                BOOL expected = major == 26 && (styles[i] == NSWindowToolbarStyleExpanded || styles[i] == NSWindowToolbarStylePreference);
                check(TSToolbarMakesSheetInUnifiedStyle(major, styles[i]) == expected,
                      [NSString stringWithFormat:@"macOS %ld, %@ style: unified %@ while the sheet is made", (long)major, StyleName(styles[i]), expected ? @"expected" : @"not expected"]);
            }

        Items *items = [Items new];
        int windows = 0;
        for (int fullSize = 0; fullSize <= 1; fullSize++)
            for (int i = 0; i < 5; i++) {
                NSWindowStyleMask mask = NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskMiniaturizable | NSWindowStyleMaskResizable;
                if (fullSize)
                    mask |= NSWindowStyleMaskFullSizeContentView;
                NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(100, 100, 700, 500) styleMask:mask backing:NSBackingStoreBuffered defer:YES];
                window.releasedWhenClosed = NO;
                window.toolbarStyle = styles[i];
                TSToolbar *toolbar = [[TSToolbar alloc] initWithIdentifier:[NSString stringWithFormat:@"sheet-%d-%d", fullSize, i]];
                toolbar.delegate = items;
                toolbar.allowsUserCustomization = YES;
                window.toolbar = toolbar;
                [window layoutIfNeeded];
                NSRect frame = window.frame;
                NSRect layout = window.contentLayoutRect;
                NSString *what = [NSString stringWithFormat:@"macOS %ld, %@ window, %@ style", (long)fakeMajorVersion, fullSize ? @"full-size content" : @"plain", StyleName(styles[i])];

                sheets = 0;
                styleAtSheet = (NSWindowToolbarStyle)-1;
                [toolbar runCustomizationPalette:nil];
                BOOL unified = TSToolbarMakesSheetInUnifiedStyle(fakeMajorVersion, styles[i]);
                check(sheets == 1, [what stringByAppendingFormat:@": the sheet is asked for %ld times", (long)sheets]);
                check(styleAtSheet == (unified ? NSWindowToolbarStyleUnified : styles[i]),
                      [what stringByAppendingFormat:@": the sheet is made in the %@ style", StyleName(styleAtSheet)]);
                // The sheet hangs from the top of the window, which stays where it was.
                check(NSMaxY(frameAtSheet) == NSMaxY(frame) && NSMinX(frameAtSheet) == NSMinX(frame) && NSWidth(frameAtSheet) == NSWidth(frame),
                      [what stringByAppendingFormat:@": the window is %@ while the sheet is made, %@ before", NSStringFromRect(frameAtSheet), NSStringFromRect(frame)]);
                check(window.toolbarStyle == styles[i], [what stringByAppendingFormat:@": the window keeps the %@ style", StyleName(window.toolbarStyle)]);
                check(NSEqualRects(window.frame, frame), [what stringByAppendingFormat:@": the window is %@ after, %@ before",
                                                             NSStringFromRect(window.frame), NSStringFromRect(frame)]);
                [window layoutIfNeeded];
                check(NSEqualRects(window.contentLayoutRect, layout), [what stringByAppendingFormat:@": the content is laid out in %@ after, %@ before",
                                                                          NSStringFromRect(window.contentLayoutRect), NSStringFromRect(layout)]);
                window.toolbar = nil;
                [window close];
                windows++;
            }

        // A toolbar in no window opens its sheet as before.
        TSToolbar *alone = [[TSToolbar alloc] initWithIdentifier:@"sheet-alone"];
        sheets = 0;
        [alone runCustomizationPalette:nil];
        check(sheets == 1, @"a toolbar in no window does not ask for its sheet");

        if (failures)
            return 1;
        printf("macOS %ld: %d windows open the sheet in the right style and keep their frame and layout\n", (long)fakeMajorVersion, windows);
    }
    return 0;
}
