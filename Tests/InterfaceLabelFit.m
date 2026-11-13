// Load every window, panel and view of the given compiled nibs offscreen, apply
// the layout and the text the application gives it after loading, and print each
// piece of text that is cut off:
//   CLIPPED  a label, button, matrix cell or pop-up choice is narrower (or, for a
//            wrapping label, shorter) than its text;
//   OUTSIDE  what a control draws reaches past its window, box, tab or other
//            enclosing view, which cuts it off;
//   OVERLAP  two controls draw over each other.
// Each control is drawn on its own with cacheDisplayInRect: to find the pixels it
// draws. Resizable windows are checked again at their smallest size. Nothing is
// ordered on screen and AppKit defaults stay in memory.
// What is typed into an editable field is not measured; its placeholder is.
// Usage: InterfaceLabelFit [--images DIR] <label>|<compiled nib>|<Localizable.strings> ...
#import <Cocoa/Cocoa.h>
#import <objc/runtime.h>
#import "TestAppKitIsolation.h"
#include "ProductionLayout.inc"
#import "TSMacroEditor.h"

// The macro editor adds its status line, list buttons and placeholder guide and
// lays out its buttons after loading; MacroEditorLayout.inc is that code, copied
// from its source.
@implementation TSMacroEditor
#include "MacroEditorLayout.inc"
- (void)setValue:(id)v forUndefinedKey:(NSString *)k {}
@end
@interface TSMacroOutlineController : NSObject @end
@implementation TSMacroOutlineController
- (void)setValue:(id)v forUndefinedKey:(NSString *)k {}
- (NSInteger)outlineView:(NSOutlineView *)view numberOfChildrenOfItem:(id)item { return 0; }
@end
@interface TSMacroOutlineView : NSOutlineView @end
@implementation TSMacroOutlineView @end

// NSLocalizedString in the application's code returns the strings of the
// language whose nib is being checked.
static NSDictionary<NSString *, NSString *> *LocalizedStrings;
static IMP OriginalLocalizedString;
static NSString *LocalizedString(NSBundle *self, SEL _cmd, NSString *key, NSString *value, NSString *table) {
    if (self == NSBundle.mainBundle && (table == nil || [table isEqual:@"Localizable"]) && LocalizedStrings[key]) return LocalizedStrings[key];
    return ((NSString *(*)(id, SEL, NSString *, NSString *, NSString *))OriginalLocalizedString)(self, _cmd, key, value, table);
}

static int problems;
static BOOL automaticBezel;
static NSString *imagesDirectory;

static BOOL Placeholder(NSString *title) {
    return [title isEqual:@"Button"] || [title isEqual:@"Radio"] || [title isEqual:@"Switch"]
        || [title rangeOfString:@"^Item [0-9]+$" options:NSRegularExpressionSearch].location != NSNotFound;
}
static void Report(NSString *line) { printf("%s\n", line.UTF8String); problems++; }
static NSString *Describe(NSView *v) {
    NSString *text = nil;
    if ([v isKindOfClass:NSPopUpButton.class]) text = ((NSPopUpButton *)v).titleOfSelectedItem;
    else if ([v isKindOfClass:NSButton.class]) text = ((NSButton *)v).title;
    else if ([v isKindOfClass:NSTextField.class]) text = ((NSTextField *)v).stringValue;
    else if ([v isKindOfClass:NSMatrix.class]) text = [[((NSMatrix *)v).cells valueForKey:@"title"] componentsJoinedByString:@" / "];
    else if ([v isKindOfClass:NSBox.class]) text = ((NSBox *)v).title;
    text = [text stringByReplacingOccurrencesOfString:@"\n" withString:@"⏎"];
    if (text.length > 60) text = [[text substringToIndex:60] stringByAppendingString:@"…"];
    return [NSString stringWithFormat:@"%@ \"%@\"", NSStringFromClass(v.class), text ?: @""];
}

// What one control draws, and where, in the coordinates of the root view.
@interface Ink : NSObject
@property (strong) NSView *view;
@property (strong) NSBitmapImageRep *bitmap;
@property NSRect drawn;   // the bounding box of the pixels it draws, in the root view
@end
@implementation Ink @end

static unsigned char Alpha(NSBitmapImageRep *rep, NSInteger x, NSInteger y) {
    NSInteger spp = rep.samplesPerPixel, bps = rep.bitsPerPixel / 8;
    unsigned char *p = rep.bitmapData + y * rep.bytesPerRow + x * bps;
    if (!rep.hasAlpha) return 255;
    return rep.bitmapFormat & NSBitmapFormatAlphaFirst ? p[0] : p[spp - 1];
}
static Ink *Draw(NSView *v, NSView *root) {
    if (NSIsEmptyRect(v.bounds)) return nil;
    NSBitmapImageRep *rep = [v bitmapImageRepForCachingDisplayInRect:v.bounds];
    if (!rep) return nil;
    [v cacheDisplayInRect:v.bounds toBitmapImageRep:rep];
    NSInteger w = rep.pixelsWide, h = rep.pixelsHigh, minx = w, miny = h, maxx = -1, maxy = -1;
    for (NSInteger y = 0; y < h; y++) for (NSInteger x = 0; x < w; x++)
        if (Alpha(rep, x, y) > 24) { minx = MIN(minx, x); maxx = MAX(maxx, x); miny = MIN(miny, y); maxy = MAX(maxy, y); }
    Ink *ink = [Ink new];
    ink.view = v; ink.bitmap = rep;
    if (maxx < 0) { ink.drawn = NSZeroRect; return ink; }
    CGFloat sx = w / NSWidth(v.bounds), sy = h / NSHeight(v.bounds);
    // Bitmap rows run from the top; the view may or may not be flipped.
    NSRect local = NSMakeRect(NSMinX(v.bounds) + minx / sx, 0, (maxx - minx + 1) / sx, (maxy - miny + 1) / sy);
    local.origin.y = v.isFlipped ? NSMinY(v.bounds) + miny / sy : NSMaxY(v.bounds) - (maxy + 1) / sy;
    ink.drawn = [root convertRect:local fromView:v];
    return ink;
}
// Whether the control draws a pixel at a point of the root view.
static BOOL Inks(Ink *ink, NSPoint p, NSView *root) {
    NSView *v = ink.view;
    NSPoint q = [v convertPoint:p fromView:root];
    NSBitmapImageRep *rep = ink.bitmap;
    CGFloat sx = rep.pixelsWide / NSWidth(v.bounds), sy = rep.pixelsHigh / NSHeight(v.bounds);
    NSInteger x = floor((q.x - NSMinX(v.bounds)) * sx), y = floor((v.isFlipped ? q.y - NSMinY(v.bounds) : NSMaxY(v.bounds) - q.y) * sy);
    if (x < 0 || y < 0 || x >= rep.pixelsWide || y >= rep.pixelsHigh) return NO;
    return Alpha(rep, x, y) > 24;
}

// The part of the root view in which a view can be seen: the bounds of each
// enclosing view, except that a scroll view's contents can be scrolled to.
static BOOL Scrolls(NSView *v) {
    for (NSView *a = v.superview; a; a = a.superview) if ([a isKindOfClass:NSClipView.class]) return YES;
    return NO;
}
static NSRect Visible(NSView *v, NSView *root) {
    NSRect r = root.bounds;
    for (NSView *a = v.superview; a && a != root; a = a.superview) r = NSIntersectionRect(r, [root convertRect:a.bounds fromView:a]);
    return r;
}

// Controls whose pixels are checked: everything a person reads or clicks.
static BOOL Measured(NSView *v) {
    if (![v isKindOfClass:NSControl.class]) return NO;
    if ([v isKindOfClass:NSScroller.class] || [v isKindOfClass:NSTableView.class]) return NO;
    return YES;
}

static void CheckText(NSView *v, NSString *where) {
    if ([v isKindOfClass:NSButton.class] && ![v isKindOfClass:NSPopUpButton.class]) {
        NSButton *b = (NSButton *)v;
        if (b.title.length && !Placeholder(b.title) && b.imagePosition != NSImageOnly) {
            // Toolbar buttons use the automatic bezel on macOS 26 and later.
            if (automaticBezel) b.bezelStyle = NSBezelStyleAutomatic;
            CGFloat need = [b.cell attributedTitle].size.width, have = [b.cell titleRectForBounds:b.bounds].size.width;
            if (need > have + 0.5) Report([NSString stringWithFormat:@"CLIPPED %@ button \"%@\"%@: needs %.1f, has %.1f", where, b.title, automaticBezel ? @" (automatic bezel)" : @"", need, have]);
        }
    }
    if ([v isKindOfClass:NSMatrix.class] && !automaticBezel) {
        // Each titled cell of a matrix (radio buttons, check boxes, button grids) fits the cell size.
        NSMatrix *m = (NSMatrix *)v;
        for (NSCell *cell in m.cells) {
            if (![cell isKindOfClass:NSButtonCell.class] || !cell.title.length || Placeholder(cell.title)) continue;
            NSButtonCell *b = (NSButtonCell *)cell;
            if (b.imagePosition == NSImageOnly) continue;
            NSRect bounds = NSMakeRect(0, 0, m.cellSize.width, m.cellSize.height);
            CGFloat need = b.attributedTitle.size.width, have = [b titleRectForBounds:bounds].size.width;
            if (need > have + 0.5) Report([NSString stringWithFormat:@"CLIPPED %@ matrix cell \"%@\": needs %.1f, has %.1f", where, b.title, need, have]);
        }
    }
    if ([v isKindOfClass:NSPopUpButton.class] && !automaticBezel) {
        // Every choice of a pop-up menu, and the title of a pull-down menu, fits the
        // button: each item is selected in a copy of the cell and measured with it.
        // Placeholder items ("Item 1") are replaced at run time.
        NSPopUpButton *p = (NSPopUpButton *)v;
        CGFloat have = p.bounds.size.width;
        NSInteger count = p.pullsDown ? MIN(1, p.numberOfItems) : p.numberOfItems;
        for (NSInteger i = 0; i < count; i++) {
            NSMenuItem *item = [p itemAtIndex:i];
            if (item.isSeparatorItem || item.isHidden || !item.title.length) continue;
            if (Placeholder(item.title) || [item.title hasPrefix:@"-- DO NOT LOCALIZE"]) continue;
            NSPopUpButtonCell *cell = [(NSPopUpButtonCell *)p.cell copy];
            [cell removeAllItems]; [cell addItemWithTitle:item.title]; [cell selectItemAtIndex:0];
            CGFloat need = cell.cellSize.width;
            if (need > have + 1) Report([NSString stringWithFormat:@"CLIPPED %@ popup \"%@\": needs %.1f, has %.1f", where, item.title, need, have]);
        }
    }
    if ([v isKindOfClass:NSTextField.class] && ((NSTextField *)v).isEditable && !automaticBezel) {
        // The placeholder of an empty field, at the window's usual size.
        NSTextField *field = (NSTextField *)v;
        NSString *placeholder = field.placeholderString ?: field.placeholderAttributedString.string;
        if (placeholder.length && ![[field.cell stringValue] length]) {
            NSTextFieldCell *cell = [field.cell copy];
            cell.stringValue = placeholder;
            BOOL wraps = cell.wraps && !cell.usesSingleLineMode;
            CGFloat need = wraps ? [cell cellSizeForBounds:NSMakeRect(0, 0, NSWidth(field.bounds), CGFLOAT_MAX)].height : cell.cellSize.width;
            CGFloat have = wraps ? NSHeight(field.bounds) : NSWidth(field.bounds);
            if (need > have + 1) Report([NSString stringWithFormat:@"CLIPPED %@ placeholder \"%@\": needs %.1f, has %.1f", where, placeholder, need, have]);
        }
    }
    if ([v isKindOfClass:NSTextField.class] && !((NSTextField *)v).isEditable && !automaticBezel) {
        NSString *text = [[(NSTextField *)v stringValue] stringByTrimmingCharactersInSet:NSCharacterSet.newlineCharacterSet];
        if (text.length && !Placeholder(text)) {
            NSTextFieldCell *cell = [[(NSTextField *)v cell] copy];
            cell.stringValue = text;
            NSRect b = v.bounds;
            BOOL wraps = (cell.lineBreakMode == NSLineBreakByWordWrapping || cell.lineBreakMode == NSLineBreakByCharWrapping) && !cell.usesSingleLineMode;
            CGFloat need = wraps ? [cell cellSizeForBounds:NSMakeRect(0, 0, b.size.width, CGFLOAT_MAX)].height : cell.cellSize.width;
            CGFloat have = wraps ? b.size.height : b.size.width;
            if (need > have + 1) Report([NSString stringWithFormat:@"CLIPPED %@ \"%@\": needs %.1f, has %.1f", where, text, need, have]);
        }
    }
}

static void Collect(NSView *v, NSView *root, NSString *where, NSMutableArray<Ink *> *inks, NSMutableArray<NSTabView *> *tabViews) {
    if (v.isHidden) return;
    CheckText(v, where);
    if (!automaticBezel && Measured(v) && !Scrolls(v)) {
        Ink *ink = Draw(v, root);
        if (ink) [inks addObject:ink];
    }
    if ([v isKindOfClass:NSTabView.class]) {
        NSTabView *tabs = (NSTabView *)v;
        [tabViews addObject:tabs];
        // The tabs themselves: NSTabView truncates labels that do not fit.
        if (!automaticBezel && tabs.tabViewType != NSNoTabsBezelBorder && tabs.tabViewType != NSNoTabsLineBorder && tabs.tabViewType != NSNoTabsNoBorder) {
            CGFloat need = tabs.minimumSize.width, have = NSWidth(tabs.bounds);
            if (need > have + 1) Report([NSString stringWithFormat:@"CLIPPED %@ tabs \"%@\": need %.1f, have %.1f", where,
                                         [[tabs.tabViewItems valueForKey:@"label"] componentsJoinedByString:@" / "], need, have]);
        }
    }
    // A matrix draws its own cells; a control's own subviews are part of what it draws.
    if ([v isKindOfClass:NSMatrix.class] || ([v isKindOfClass:NSControl.class] && Measured(v))) return;
    for (NSView *s in v.subviews) Collect(s, root, where, inks, tabViews);
}

static void CheckGeometry(NSView *root, NSString *where, NSArray<Ink *> *inks) {
    for (Ink *ink in inks) {
        if (NSIsEmptyRect(ink.drawn)) continue;
        NSRect visible = Visible(ink.view, root), d = ink.drawn;
        // A Return or Escape button placed out of sight on purpose only gives the
        // panel its key equivalent.
        if ([ink.view isKindOfClass:NSButton.class] && !NSIntersectsRect(d, visible)) {
            NSString *key = ((NSButton *)ink.view).keyEquivalent;
            if ([key isEqual:@"\r"] || [key isEqual:@"\033"]) continue;
        }
        CGFloat left = NSMinX(visible) - NSMinX(d), right = NSMaxX(d) - NSMaxX(visible);
        CGFloat bottom = NSMinY(visible) - NSMinY(d), top = NSMaxY(d) - NSMaxY(visible);
        CGFloat worst = MAX(MAX(left, right), MAX(bottom, top));
        if (worst > 1) {
            NSMutableArray *sides = [NSMutableArray array];
            if (left > 1) [sides addObject:[NSString stringWithFormat:@"left %.0f", left]];
            if (right > 1) [sides addObject:[NSString stringWithFormat:@"right %.0f", right]];
            if (bottom > 1) [sides addObject:[NSString stringWithFormat:@"bottom %.0f", bottom]];
            if (top > 1) [sides addObject:[NSString stringWithFormat:@"top %.0f", top]];
            NSView *clip = ink.view.superview == root ? root : ink.view.superview;
            Report([NSString stringWithFormat:@"OUTSIDE %@ %@ draws past its %@ (%@ points)", where, Describe(ink.view),
                    clip == root ? @"window" : NSStringFromClass(clip.class), [sides componentsJoinedByString:@", "]]);
        }
    }
    for (NSUInteger a = 0; a < inks.count; a++) for (NSUInteger b = a + 1; b < inks.count; b++) {
        Ink *p = inks[a], *q = inks[b];
        if ([p.view isDescendantOf:q.view] || [q.view isDescendantOf:p.view]) continue;
        NSRect both = NSIntersectionRect(NSIntersectionRect(p.drawn, q.drawn), NSIntersectionRect(Visible(p.view, root), Visible(q.view, root)));
        // Square buttons placed edge to edge share one border line, like the console's.
        if (NSWidth(both) <= 1.5 || NSHeight(both) <= 1.5) continue;
        // Count the points both draw, sampled every half point.
        NSUInteger shared = 0;
        for (CGFloat y = NSMinY(both) + 0.25; y < NSMaxY(both); y += 0.5)
            for (CGFloat x = NSMinX(both) + 0.25; x < NSMaxX(both); x += 0.5)
                if (Inks(p, NSMakePoint(x, y), root) && Inks(q, NSMakePoint(x, y), root)) shared++;
        if (shared >= 8)
            Report([NSString stringWithFormat:@"OVERLAP %@ %@ and %@ draw over each other (%.1f square points)", where, Describe(p.view), Describe(q.view), shared / 4.0]);
    }
}

static void SaveImage(NSView *root, NSString *name) {
    if (!imagesDirectory) return;
    NSBitmapImageRep *rep = [root bitmapImageRepForCachingDisplayInRect:root.bounds];
    [root cacheDisplayInRect:root.bounds toBitmapImageRep:rep];
    // The content view draws no window background of its own.
    NSImage *image = [[NSImage alloc] initWithSize:root.bounds.size];
    [image lockFocus];
    [NSColor.windowBackgroundColor setFill]; NSRectFill(root.bounds);
    [rep drawInRect:root.bounds fromRect:NSZeroRect operation:NSCompositingOperationSourceOver fraction:1 respectFlipped:NO hints:nil];
    [image unlockFocus];
    NSBitmapImageRep *out = [[NSBitmapImageRep alloc] initWithData:image.TIFFRepresentation];
    NSString *file = [[name stringByReplacingOccurrencesOfString:@"/" withString:@"-"] stringByAppendingPathExtension:@"png"];
    [[out representationUsingType:NSBitmapImageFileTypePNG properties:@{}] writeToFile:[imagesDirectory stringByAppendingPathComponent:file] atomically:YES];
}

static void CheckRoot(NSView *root, NSString *where) {
    NSMutableArray<Ink *> *inks = [NSMutableArray array];
    NSMutableArray<NSTabView *> *tabViews = [NSMutableArray array];
    [root layoutSubtreeIfNeeded];
    Collect(root, root, where, inks, tabViews);
    if (!automaticBezel) CheckGeometry(root, where, inks);
    // Each tab that is not selected, chosen as a person would choose it.
    for (NSTabView *tabs in tabViews) {
        NSTabViewItem *selected = tabs.selectedTabViewItem;
        for (NSTabViewItem *item in tabs.tabViewItems) {
            if (item == selected || !item.view) continue;
            [tabs selectTabViewItem:item];
            [root layoutSubtreeIfNeeded];
            NSMutableArray<Ink *> *page = [NSMutableArray array];
            NSString *tab = [NSString stringWithFormat:@"%@ tab \"%@\"", where, item.label];
            Collect(item.view, root, tab, page, [NSMutableArray array]);
            if (!automaticBezel) CheckGeometry(root, tab, page);
        }
        if (selected) [tabs selectTabViewItem:selected];
    }
}

int main(int argc, char **argv) { @autoreleasepool {
    TSInstallAppKitIsolation();
    Method localized = class_getInstanceMethod(NSBundle.class, @selector(localizedStringForKey:value:table:));
    OriginalLocalizedString = method_setImplementation(localized, (IMP)LocalizedString);
    [NSApplication sharedApplication]; [NSApp setActivationPolicy:NSApplicationActivationPolicyProhibited];
    NSApp.appearance = [NSAppearance appearanceNamed:NSAppearanceNameAqua];
    NSMutableArray<NSString *> *entries = [NSMutableArray array];
    for (int i = 1; i < argc; i++) {
        if (!strcmp(argv[i], "--images") && i + 1 < argc) { imagesDirectory = @(argv[++i]); continue; }
        [entries addObject:@(argv[i])];
    }
    NSUInteger roots = 0;
    for (int pass = 0; pass < 2; pass++) { automaticBezel = pass == 1;
    for (NSString *entry in entries) {
        NSArray<NSString *> *parts = [entry componentsSeparatedByString:@"|"];
        NSString *label = parts[0], *path = parts[1], *strings = parts.count > 2 ? parts[2] : nil;
        NSString *source = strings ? [NSString stringWithContentsOfFile:strings encoding:NSUTF8StringEncoding error:nil] : nil;
        LocalizedStrings = source ? [source propertyListFromStringsFileFormat] : @{};
        // The label is <language>.lproj/<interface>[/<compiled variant>].
        NSString *name = label.pathComponents.count > 1 ? label.pathComponents[1] : label.lastPathComponent;
        NSData *data = [NSData dataWithContentsOfFile:path];
        NSArray *objects = nil;
        BOOL macroEditor = [name isEqual:@"MacroEditor.nib"];
        id owner = macroEditor ? [TSMacroEditor new] : ProductionOwner(name);
        // A compiled main menu becomes the application's menu; the guides that name
        // menu commands then fall back to the strings of this nib's language.
        NSApp.mainMenu = nil;
        if (![[[NSNib alloc] initWithNibData:data bundle:nil] instantiateWithOwner:owner topLevelObjects:&objects]) { printf("ERROR %s cannot load\n", label.UTF8String); return 2; }
        NSApp.mainMenu = nil;
        if (macroEditor) {
            TSMacroEditor *editor = owner;
            [editor installShortcutStatus]; [editor installListControls]; [editor installPlaceholderNote]; [editor layoutDialogButtons];
        } else ApplyProductionLayout(name, owner, objects);
        for (id o in objects) {
            if ([o isKindOfClass:NSWindow.class]) {
                NSWindow *w = o;
                NSString *where = [NSString stringWithFormat:@"%@ [%@]", label, w.title.length ? w.title : @"untitled window"];
                CheckRoot(w.contentView, where); roots++;
                if (!automaticBezel) SaveImage(w.contentView, where);
                // A window that can be made smaller must still show everything at its smallest size.
                NSSize smallest = [w contentRectForFrameRect:NSMakeRect(0, 0, w.minSize.width, w.minSize.height)].size;
                if (!NSEqualSizes(w.contentMinSize, NSZeroSize)) smallest = NSMakeSize(MAX(smallest.width, w.contentMinSize.width), MAX(smallest.height, w.contentMinSize.height));
                NSSize current = w.contentView.bounds.size;
                if (!automaticBezel && (w.styleMask & NSWindowStyleMaskResizable) && smallest.width > 1 && smallest.height > 1
                    && (smallest.width < current.width - 0.5 || smallest.height < current.height - 0.5)) {
                    [w setContentSize:NSMakeSize(MIN(current.width, MAX(smallest.width, 1)), MIN(current.height, MAX(smallest.height, 1)))];
                    NSString *smallestWhere = [where stringByAppendingFormat:@" at its smallest size %.0fx%.0f", NSWidth(w.contentView.bounds), NSHeight(w.contentView.bounds)];
                    CheckRoot(w.contentView, smallestWhere);
                    SaveImage(w.contentView, smallestWhere);
                    [w setContentSize:current];
                }
            } else if ([o isKindOfClass:NSView.class]) {
                CheckRoot(o, [NSString stringWithFormat:@"%@ [view]", label]); roots++;
            }
        }
    }}
    if (problems) { printf("FAIL: %d problems\n", problems); return 1; }
    printf("PASS: text, controls and pop-up choices are whole, inside their windows and apart in %lu windows and views of %lu localized interfaces (also with the automatic toolbar bezel)\n", (unsigned long)roots / 2, (unsigned long)entries.count);
} return 0; }
