#pragma once
#import <Cocoa/Cocoa.h>
#import <PDFKit/PDFKit.h>
#include <string.h>

// Read the catalog of the already-loaded PDF (including in-memory snapshots).
// A missing, malformed or unknown direction is not a document-level preference.
static inline NSNumber *TSPreviewPDFDirection(PDFDocument *document) {
    CGPDFDocumentRef reference = document.documentRef;
    if (!reference) return nil;
    CGPDFDictionaryRef catalog = CGPDFDocumentGetCatalog(reference), preferences = NULL;
    const char *direction = NULL;
    if (!catalog || !CGPDFDictionaryGetDictionary(catalog, "ViewerPreferences", &preferences) ||
        !CGPDFDictionaryGetName(preferences, "Direction", &direction)) return nil;
    if (strcmp(direction, "R2L") == 0) return @YES;
    if (strcmp(direction, "L2R") == 0) return @NO;
    return nil;
}

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

// The icons of the display formats (#65). The open books are drawn from SVG path data, in the
// 22 x 20 frame of the images, y downward; only the commands M L H V C and Z, absolute or
// relative, are used. The pages' top and bottom edges are arcs, and each line of text keeps the
// same distance from the top edge of its page.
static NSString * const TSPreviewBookPages[] = {
    @"M2.2,17.2V3.3c2.81-1.2,5.99-1.2,8.8,0v13.9C8.19,16,5.01,16,2.2,17.2",
    @"M11,17.2V3.3c2.81-1.2,5.99-1.2,8.8,0v13.9C16.99,16,13.81,16,11,17.2"};
static NSString * const TSPreviewBookLines[] = {
    @"M3.78,5.47c1.83-.63,3.81-.63,5.64,0", @"M3.78,7.85c1.23-.6,2.62-.7,3.95-.45",
    @"M12.58,5.47c1.83-.63,3.81-.63,5.64,0", @"M12.58,7.85c1.23-.6,2.69-.71,3.99-.41"};

static inline NSBezierPath *TSPreviewPathFromSVG(NSString *data) {
    NSBezierPath *path = [NSBezierPath bezierPath];
    NSScanner *scanner = [NSScanner scannerWithString:data];
    NSCharacterSet *separators = [NSCharacterSet characterSetWithCharactersInString:@" ,\n\r\t\f"];
    scanner.charactersToBeSkipped = separators;
    NSCharacterSet *commands = [NSCharacterSet characterSetWithCharactersInString:@"MmLlHhVvCcZz"];
    unichar command = 'M';
    NSPoint current = NSZeroPoint, start = NSZeroPoint;
    while (YES) {
        // One command letter at a time: a close may be followed at once by the next command.
        while (scanner.scanLocation < data.length && [separators characterIsMember:[data characterAtIndex:scanner.scanLocation]])
            scanner.scanLocation += 1;
        if (scanner.isAtEnd) break;
        unichar next = [data characterAtIndex:scanner.scanLocation];
        if ([commands characterIsMember:next]) {
            command = next;
            scanner.scanLocation += 1;
            if (command == 'Z' || command == 'z') { [path closePath]; current = start; continue; }
        }
        else if (command == 'Z' || command == 'z') return path;   // numbers after a close
        BOOL relative = command >= 'a';
        NSUInteger count = (command == 'C' || command == 'c') ? 6 : (command == 'H' || command == 'h' || command == 'V' || command == 'v') ? 1 : 2;
        double v[6];
        for (NSUInteger i = 0; i < count; i++)
            if (![scanner scanDouble:&v[i]]) return path;
        switch (command) {
            case 'M': case 'm':
                current = relative ? NSMakePoint(current.x + v[0], current.y + v[1]) : NSMakePoint(v[0], v[1]);
                [path moveToPoint:current]; start = current;
                command = relative ? 'l' : 'L';   // further pairs are lines
                break;
            case 'L': case 'l':
                current = relative ? NSMakePoint(current.x + v[0], current.y + v[1]) : NSMakePoint(v[0], v[1]);
                [path lineToPoint:current]; break;
            case 'H': case 'h':
                current.x = relative ? current.x + v[0] : v[0]; [path lineToPoint:current]; break;
            case 'V': case 'v':
                current.y = relative ? current.y + v[0] : v[0]; [path lineToPoint:current]; break;
            default: {
                NSPoint base = relative ? current : NSZeroPoint;
                NSPoint c1 = NSMakePoint(base.x + v[0], base.y + v[1]), c2 = NSMakePoint(base.x + v[2], base.y + v[3]);
                current = NSMakePoint(base.x + v[4], base.y + v[5]);
                [path curveToPoint:current controlPoint1:c1 controlPoint2:c2];
            }
        }
    }
    return path;
}

// An open book in the image's frame, moved by `transform`; the widths are of the page outlines
// and of the lines of text.
static inline void TSPreviewDrawBook(NSAffineTransform *transform, CGFloat pageWidth, CGFloat lineWidth) {
    for (NSUInteger i = 0; i < 2; i++) {
        NSBezierPath *page = TSPreviewPathFromSVG(TSPreviewBookPages[i]);
        if (transform) [page transformUsingAffineTransform:transform];
        page.lineWidth = pageWidth; page.lineCapStyle = NSLineCapStyleRound; page.lineJoinStyle = NSLineJoinStyleRound;
        [page stroke];
    }
    for (NSUInteger i = 0; i < 4; i++) {
        NSBezierPath *line = TSPreviewPathFromSVG(TSPreviewBookLines[i]);
        if (transform) [line transformUsingAffineTransform:transform];
        line.lineWidth = lineWidth; line.lineCapStyle = NSLineCapStyleRound;
        [line stroke];
    }
}

// A symbol at the size of the toolbar's symbols, in the middle of the frame.
static inline void TSPreviewDrawSymbol(NSImage *symbol, NSRect frame) {
    NSImage *sized = [symbol imageWithSymbolConfiguration:[NSImageSymbolConfiguration configurationWithPointSize:15 weight:NSFontWeightRegular]] ?: symbol;
    NSSize size = sized.size;
    [sized drawInRect:NSMakeRect(NSMidX(frame) - size.width / 2, NSMidY(frame) - size.height / 2, size.width, size.height)
             fromRect:NSZeroRect operation:NSCompositingOperationSourceOver fraction:1 respectFlipped:YES hints:nil];
}

// Single Page: a sheet with text; Two Pages: an open book; MultiPage: a scroll; Double
// MultiPage: an open book with an arrow down. None looks like the Split Window button.
static inline NSImage *TSPreviewLayoutImage(NSInteger style) {
    NSImage *sheet = [NSImage imageWithSystemSymbolName:@"doc.text" accessibilityDescription:nil];
    NSImage *scroll = [NSImage imageWithSystemSymbolName:@"scroll" accessibilityDescription:nil];
    NSImage *image = [NSImage imageWithSize:NSMakeSize(22, 20) flipped:YES drawingHandler:^BOOL(NSRect rect) {
        [NSColor.blackColor setStroke];
        if (style == 2) TSPreviewDrawBook(nil, 1.35, 0.95);
        else if (style == 4) {
            // The book at 0.8 of its size above the arrow, with lines a little heavier than scaled.
            NSAffineTransform *transform = [NSAffineTransform transform];
            [transform translateXBy:11 * (1 - 0.8) yBy:1.5 - 2.4 * 0.8];
            [transform scaleBy:0.8];
            TSPreviewDrawBook(transform, 1.15, 0.81);
            NSBezierPath *arrow = TSPreviewPathFromSVG(@"M11,14.6V19.2M9.3,17.5L11,19.2L12.7,17.5");
            arrow.lineWidth = 0.95; arrow.lineCapStyle = NSLineCapStyleRound; arrow.lineJoinStyle = NSLineJoinStyleRound;
            [arrow stroke];
        }
        else if (style == 3 && scroll) TSPreviewDrawSymbol(scroll, rect);
        else if (sheet) TSPreviewDrawSymbol(sheet, rect);
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
    item.visibilityPriority = NSToolbarItemVisibilityPriorityUser;
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
