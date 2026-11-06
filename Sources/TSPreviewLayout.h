#pragma once
#import <Cocoa/Cocoa.h>

static NSString * const TSPreviewLayoutToolbarID = @"TSPreviewPageLayout";
static NSString * const TSPreviewArrangementToolbarID = @"TSPreviewArrangement";

static inline NSString *TSPreviewLayoutText(NSString *key) {
    return NSLocalizedStringFromTable(key, @"ToolbarItems", @"");
}

static inline NSMenu *TSPreviewPageMenu(NSMenu *menu) {
    for (NSMenuItem *item in menu.itemArray) {
        if (item.action == NSSelectorFromString(@"changePageStyle:")) return menu;
        NSMenu *found = item.submenu ? TSPreviewPageMenu(item.submenu) : nil;
        if (found) return found;
    }
    return nil;
}

static inline NSString *TSPreviewPageTitle(NSInteger style) {
    // Keep the toolbar wording identical to the localized main menu.
    NSMenuItem *item = [TSPreviewPageMenu(NSApp.mainMenu) itemWithTag:style];
    if (item) return item.title;
    NSArray *names = @[@"Single Page", @"Two Pages", @"Continuous", @"Continuous Two Pages"];
    return TSPreviewLayoutText(names[MAX(1, MIN(4, style)) - 1]);
}

static inline NSImage *TSPreviewLayoutImage(NSInteger style) {
    BOOL two = style == 2 || style == 4;
    BOOL continuous = style == 3 || style == 4;
    NSImage *image = [NSImage imageWithSize:NSMakeSize(22, 20) flipped:NO drawingHandler:^BOOL(NSRect rect) {
        [NSColor.blackColor setStroke];
        NSInteger columns = two ? 2 : 1, rows = continuous ? 2 : 1;
        CGFloat width = two ? 8 : 12, height = continuous ? 7 : 16;
        for (NSInteger y = 0; y < rows; y++) for (NSInteger x = 0; x < columns; x++) {
            NSBezierPath *page = [NSBezierPath bezierPathWithRect:NSMakeRect(two ? 1.5 + x * 11 : 5, continuous ? 1.5 + y * 10 : 2, width, height)];
            page.lineWidth = 1.3;
            [page stroke];
        }
        return YES;
    }];
    image.template = YES;
    return image;
}

static inline NSMenuToolbarItem *TSPreviewLayoutItem(id target, NSString *identifier) {
    BOOL layout = [identifier isEqual:TSPreviewLayoutToolbarID];
    NSString *label = TSPreviewLayoutText(layout ? @"Page Layout" : @"Two-Page Arrangement");
    NSMenuToolbarItem *item = [[NSMenuToolbarItem alloc] initWithItemIdentifier:identifier];
    item.label = label;
    item.paletteLabel = label;
    item.toolTip = layout ? label : TSPreviewLayoutText(@"Applies when displaying two pages");
    item.image = layout ? TSPreviewLayoutImage(1) : [NSImage imageWithSystemSymbolName:@"book.pages" accessibilityDescription:label];
    if (!item.image) item.image = [NSImage imageWithSystemSymbolName:@"book" accessibilityDescription:label];
    item.showsIndicator = YES;
    item.target = target;
    NSMenu *menu = [[NSMenu alloc] initWithTitle:label];
    for (NSInteger tag = 1; tag <= 4; tag++) {
        if (!layout && tag >= 3) [menu addItem:NSMenuItem.separatorItem];
        NSString *title = layout ? TSPreviewPageTitle(tag) : TSPreviewLayoutText(@[
            @"Left to right", @"Right to left", @"Show first page alone as cover", @"Restore Document Settings"][tag - 1]);
        NSMenuItem *choice = [[NSMenuItem alloc] initWithTitle:title
            action:NSSelectorFromString(layout ? @"changePreviewLayout:" : @"changePreviewArrangement:") keyEquivalent:@""];
        choice.target = target;
        choice.tag = tag;
        if (layout) choice.image = TSPreviewLayoutImage(tag);
        [menu addItem:choice];
    }
    item.menu = menu;
    return item;
}
