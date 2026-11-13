// Load every window of the given compiled nibs offscreen, apply the button layout
// the application applies to it, find each bezel button's drawn extent by hiding it
// and diffing the rendering, and print pairs of side-by-side or stacked buttons whose
// drawn bezels are closer than the minimum: the push-button gap for two push buttons
// side by side, 8 points otherwise. Nothing is ordered on screen and AppKit defaults
// stay in memory.
// Usage: ButtonSpacing <push-button gap in points> <label>=<compiled nib> ...
#import <Cocoa/Cocoa.h>
#import "TestAppKitIsolation.h"
#import <objc/message.h>
@interface NSButtonCell (Private) - (NSInteger)_buttonType; @end
#import "TSDialogButtonLayout.h"
#import "TSMarkMenu.h"
// Older nibs set outlets directly on instance variables of these names.
@interface SpacingOwner : NSObject { @public id linePanel, projectPanel, extensionPanel; }
@property (strong) NSMutableDictionary *outlets;
@end
@implementation SpacingOwner
- (instancetype)init { if ((self = [super init])) _outlets = [NSMutableDictionary dictionary]; return self; }
- (void)setValue:(id)v forUndefinedKey:(NSString *)k { if (v) self.outlets[k] = v; }
- (id)valueForUndefinedKey:(NSString *)k { return nil; }
// Older nibs connect an action only when the owner responds to it.
- (IBAction)didTapDoneButton:(id)sender {}
- (IBAction)didTapCancelButton:(id)sender {}
- (IBAction)itemChosen:(id)sender {}
@end
// The layout the application applies after loading each nib.
static void ApplyProductionLayout(NSString *name, id owner, NSArray *objects) {
    NSArray<NSWindow *> *windows = [objects filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(id o, NSDictionary *b) { return [o isKindOfClass:NSWindow.class]; }]];
    if ([name isEqual:@"TSDocument.nib"]) {
        SpacingOwner *document = owner;
        if (!document->linePanel || !document->projectPanel || !document->extensionPanel) { printf("ERROR TSDocument.nib panels are not connected\n"); exit(2); }
        for (NSWindow *panel in @[document->linePanel, document->projectPanel, document->extensionPanel]) TSLayoutDialogButtonRow(panel);
    } else if ([name isEqual:@"MainMenu.nib"]) {
        // HelpDocuments (two panels) and TSStationery lay out their OK/Cancel panels.
        NSUInteger dialogs = 0;
        for (NSWindow *w in windows) {
            BOOL ret = NO, esc = NO;
            for (NSView *v in w.contentView.subviews) if ([v isKindOfClass:NSButton.class]) { ret |= [((NSButton *)v).keyEquivalent isEqual:@"\r"]; esc |= [((NSButton *)v).keyEquivalent isEqual:@"\033"]; }
            if (ret && esc) { TSLayoutDialogButtonRow(w); dialogs++; }
        }
        if (dialogs != 3) { printf("ERROR MainMenu.nib has %lu OK/Cancel panels, not the three the application lays out\n", (unsigned long)dialogs); exit(2); }
    } else if ([name isEqual:@"CustomModalWindowController.xib"]) {
        // Its constraints space the buttons; lay them out as a window would.
        for (NSWindow *w in windows) [w.contentView layoutSubtreeIfNeeded];
    } else if ([name isEqual:@"FindPanel.nib"]) {
        for (NSWindow *w in windows) TSLayoutBottomActionRow(w);
    }
}
static NSBitmapImageRep *Render(NSView *v) {
    NSBitmapImageRep *rep = [v bitmapImageRepForCachingDisplayInRect:v.bounds];
    [v cacheDisplayInRect:v.bounds toBitmapImageRep:rep];
    return rep;
}
// Bounding box, in points from the top left, of the pixels that differ.
static NSRect Diff(NSBitmapImageRep *a, NSBitmapImageRep *b, CGFloat scale) {
    NSInteger w = a.pixelsWide, h = a.pixelsHigh, bpr = a.bytesPerRow, spp = a.bitsPerPixel / 8;
    unsigned char *p = a.bitmapData, *q = b.bitmapData;
    NSInteger minx = w, miny = h, maxx = -1, maxy = -1;
    for (NSInteger y = 0; y < h; y++) {
        unsigned char *r1 = p + y * bpr, *r2 = q + y * bpr;
        if (memcmp(r1, r2, w * spp) == 0) continue;
        for (NSInteger x = 0; x < w; x++) {
            unsigned char *c1 = r1 + x * spp, *c2 = r2 + x * spp; int d = 0;
            for (int k = 0; k < spp; k++) d = MAX(d, abs(c1[k] - c2[k]));
            if (d > 8) { minx = MIN(minx, x); maxx = MAX(maxx, x); miny = MIN(miny, y); maxy = MAX(maxy, y); }
        }
    }
    if (maxx < 0) return NSZeroRect;
    return NSMakeRect(minx / scale, miny / scale, (maxx - minx + 1) / scale, (maxy - miny + 1) / scale);
}
// Buttons that draw a bezel: push and square buttons and pop-up buttons, not
// check boxes, radio buttons, disclosure triangles or borderless images.
static BOOL HasBezel(NSView *v) {
    if (![v isKindOfClass:NSButton.class]) return NO;
    NSButton *b = (NSButton *)v;
    if (!b.bordered && ![b isKindOfClass:NSPopUpButton.class]) return NO;
    NSButtonCell *cell = (NSButtonCell *)b.cell;
    if (![cell isKindOfClass:NSButtonCell.class]) return NO;
    if (b.bezelStyle == NSBezelStyleDisclosure || b.bezelStyle == NSBezelStylePushDisclosure) return NO;
    // Check boxes and radio buttons draw their own small mark instead of a bezel.
    if ([cell respondsToSelector:@selector(_buttonType)]) {
        NSInteger type = ((NSInteger (*)(id, SEL))objc_msgSend)(cell, @selector(_buttonType));
        if (type == NSButtonTypeSwitch || type == NSButtonTypeRadio) return NO;
    }
    return YES;
}
static void Collect(NSView *v, NSMutableArray *out) {
    for (NSView *c in v.subviews) {
        if (c.hiddenOrHasHiddenAncestor) continue;
        if ([c isKindOfClass:NSMatrix.class]) continue;
        if (HasBezel(c)) [out addObject:c]; else Collect(c, out);
    }
}
static NSString *Name(NSView *v) {
    NSString *s = [v isKindOfClass:NSPopUpButton.class] ? ((NSPopUpButton *)v).titleOfSelectedItem : ((NSButton *)v).title;
    return [NSString stringWithFormat:@"%@\"%@\"", [v isKindOfClass:NSPopUpButton.class] ? @"PopUp" : @"Button", s ?: @""];
}
int main(int argc, char **argv) { @autoreleasepool {
    TSInstallAppKitIsolation();
    [NSApplication sharedApplication];
    [NSApp setActivationPolicy:NSApplicationActivationPolicyProhibited];
    CGFloat minimum = atof(argv[1]);
    NSUInteger roots = 0, buttons = 0, findings = 0;
    for (int i = 2; i < argc; i++) {
        NSString *arg = @(argv[i]); NSRange eq = [arg rangeOfString:@"="];
        NSString *label = [arg substringToIndex:eq.location], *path = [arg substringFromIndex:NSMaxRange(eq)];
        fprintf(stderr, "NIB %s\n", label.UTF8String);
        NSString *name = label.lastPathComponent;
        NSNib *nib = [[NSNib alloc] initWithNibData:[NSData dataWithContentsOfFile:path] bundle:nil];
        NSArray *objects = nil;
        id owner = [SpacingOwner new];
        if (![nib instantiateWithOwner:owner topLevelObjects:&objects]) { printf("ERROR %s cannot load\n", label.UTF8String); return 2; }
        ApplyProductionLayout(name, owner, objects);
        NSMutableArray<NSArray *> *views = [NSMutableArray array];
        for (id object in objects) {
            // Top-level views are toolbar items and settings panes, which their own code lays out.
            if ([object isKindOfClass:NSWindow.class]) [views addObject:@[((NSWindow *)object).title ?: @"", ((NSWindow *)object).contentView]];
        }
        for (NSArray *entry in views) {
            NSView *root = entry[1];
            for (NSAppearanceName mode in @[NSAppearanceNameAqua, NSAppearanceNameDarkAqua]) {
                root.appearance = [NSAppearance appearanceNamed:mode];
                [root layoutSubtreeIfNeeded];
                NSMutableArray<NSView *> *found = [NSMutableArray array]; Collect(root, found);
                if (found.count < 2) continue;
                roots++;
                NSBitmapImageRep *base = Render(root); CGFloat scale = base.pixelsWide / MAX(1, NSWidth(root.bounds));
                NSMutableArray<NSValue *> *extents = [NSMutableArray array];
                for (NSView *b in found) { b.hidden = YES; [extents addObject:[NSValue valueWithRect:Diff(base, Render(root), scale)]]; b.hidden = NO; }
                buttons += found.count;
                for (NSUInteger a = 0; a < found.count; a++) for (NSUInteger b = a + 1; b < found.count; b++) {
                    NSRect r = extents[a].rectValue, s = extents[b].rectValue;
                    if (NSIsEmptyRect(r) || NSIsEmptyRect(s)) continue;
                    CGFloat vertical = MIN(NSMaxY(r), NSMaxY(s)) - MAX(NSMinY(r), NSMinY(s));
                    CGFloat horizontal = MIN(NSMaxX(r), NSMaxX(s)) - MAX(NSMinX(r), NSMinX(s));
                    CGFloat gap = -1; NSString *axis = nil;
                    if (vertical > 0.5 * MIN(NSHeight(r), NSHeight(s))) { gap = MAX(NSMinX(s) - NSMaxX(r), NSMinX(r) - NSMaxX(s)); axis = @"side by side"; }
                    else if (horizontal > 0.5 * MIN(NSWidth(r), NSWidth(s))) { gap = MAX(NSMinY(s) - NSMaxY(r), NSMinY(r) - NSMaxY(s)); axis = @"stacked"; }
                    // Square buttons placed edge to edge form one attached bar, like the console's.
                    NSBezelStyle sa = ((NSButton *)found[a]).bezelStyle, sb = ((NSButton *)found[b]).bezelStyle;
                    BOOL square = (sa == NSBezelStyleShadowlessSquare || sa == NSBezelStyleSmallSquare) && (sb == NSBezelStyleShadowlessSquare || sb == NSBezelStyleSmallSquare);
                    if (square && axis && fabs(gap) <= 1.5) continue;
                    BOOL push = ((NSButton *)found[a]).bezelStyle == NSBezelStylePush && ((NSButton *)found[b]).bezelStyle == NSBezelStylePush && ![found[a] isKindOfClass:NSPopUpButton.class] && ![found[b] isKindOfClass:NSPopUpButton.class];
                    CGFloat required = [axis isEqual:@"side by side"] && push ? minimum : 8;
                    if (axis == nil || gap >= required) continue;
                    findings++;
                    printf("CLOSE %s | %s | %s | %s and %s | %s gap %.1f\n", label.UTF8String, [entry[0] UTF8String],
                           [mode isEqual:NSAppearanceNameAqua] ? "light" : "dark", Name(found[a]).UTF8String, Name(found[b]).UTF8String, axis.UTF8String, gap);
                }
            }
        }
    }
    printf("STAT roots=%lu buttons=%lu close=%lu\n", (unsigned long)roots, (unsigned long)buttons, (unsigned long)findings);
} return 0; }
