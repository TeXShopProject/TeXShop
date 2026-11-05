// Render every Preferences tab of each localization offscreen. Find each control's drawn
// extent by hiding it and diffing the rendering, and print controls that overlap or touch.
// Usage: PreferencesOverlaps Resources/Interfaces/<lang>.lproj/Preferences.nib ...
#import <Cocoa/Cocoa.h>
@interface TSPreferences : NSObject @end
@implementation TSPreferences
- (void)setValue:(id)v forUndefinedKey:(NSString *)k {}
- (id)valueForUndefinedKey:(NSString *)k { return nil; }
@end
static NSTabView *MainTabs(NSView *v) {
    if ([v isKindOfClass:NSTabView.class] && ((NSTabView *)v).numberOfTabViewItems == 9) return (NSTabView *)v;
    for (NSView *c in v.subviews) { NSTabView *t = MainTabs(c); if (t) return t; }
    return nil;
}
static NSString *Name(NSView *v) {
    NSString *s = nil;
    if ([v isKindOfClass:NSButton.class]) s = ((NSButton *)v).title;
    else if ([v isKindOfClass:NSTextField.class]) s = ((NSTextField *)v).stringValue;
    else if ([v isKindOfClass:NSMatrix.class]) s = [[(NSMatrix *)v cells].firstObject title];
    else if ([v isKindOfClass:NSPopUpButton.class]) s = ((NSPopUpButton *)v).titleOfSelectedItem;
    if (s.length > 22) s = [[s substringToIndex:22] stringByAppendingString:@"…"];
    return [NSString stringWithFormat:@"%@[%@]\"%@\"", NSStringFromClass(v.class), v.identifier ?: @"", s ?: @""];
}
static void Collect(NSView *v, NSMutableArray *out) {
    for (NSView *c in v.subviews) {
        if (c.hiddenOrHasHiddenAncestor) continue;
        if ([c isKindOfClass:NSControl.class] || [c isKindOfClass:NSImageView.class]) [out addObject:c];
        else Collect(c, out);
    }
}
static NSBitmapImageRep *Render(NSView *v) {
    NSBitmapImageRep *rep = [v bitmapImageRepForCachingDisplayInRect:v.bounds];
    [v cacheDisplayInRect:v.bounds toBitmapImageRep:rep];
    return rep;
}
// Bounding box (in points, view coordinates with origin top-left) of pixels that differ.
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
static void Check(NSString *lang, NSString *tab, NSView *root, NSView *tv, NSMutableString *report) {
    NSBitmapImageRep *base = Render(root);
    CGFloat scale = base.pixelsWide / root.bounds.size.width;
    NSMutableArray *leaves = [NSMutableArray array]; Collect(tv, leaves);
    NSMutableArray *rects = [NSMutableArray array];
    NSRect noise = Diff(base, Render(root), scale);
    if (!NSIsEmptyRect(noise)) [report appendFormat:@"%@\t%@\tNOISE %@\n", lang, tab, NSStringFromRect(noise)];
    for (NSView *c in leaves) {
        c.hidden = YES; [root displayIfNeeded]; NSBitmapImageRep *img = Render(root); c.hidden = NO; [root displayIfNeeded];
        NSBitmapImageRep *again = Render(root);
        NSRect d = Diff(again, img, scale);
        [rects addObject:[NSValue valueWithRect:d]];
    }
    for (NSUInteger i = 0; i < leaves.count; i++) for (NSUInteger j = i + 1; j < leaves.count; j++) {
        NSRect a = [rects[i] rectValue], b = [rects[j] rectValue];
        if (NSIsEmptyRect(a) || NSIsEmptyRect(b)) continue;
        NSRect x = NSIntersectionRect(a, b);
        if (x.size.width >= 1 && x.size.height >= 1)
            [report appendFormat:@"%@\t%@\tOVERLAP %.1fx%.1f\t%@ %@\t%@ %@\n", lang, tab, x.size.width, x.size.height, Name(leaves[i]), NSStringFromRect(a), Name(leaves[j]), NSStringFromRect(b)];
        else {
            // Vertically stacked with horizontal overlap and a gap under 2pt.
            CGFloat hov = MIN(NSMaxX(a), NSMaxX(b)) - MAX(NSMinX(a), NSMinX(b));
            CGFloat gap = MAX(NSMinY(a), NSMinY(b)) - MIN(NSMaxY(a), NSMaxY(b));
            CGFloat vov = MIN(NSMaxY(a), NSMaxY(b)) - MAX(NSMinY(a), NSMinY(b));
            CGFloat hgap = MAX(NSMinX(a), NSMinX(b)) - MIN(NSMaxX(a), NSMaxX(b));
            if (hov > 0 && gap >= 0 && gap < 2) [report appendFormat:@"%@\t%@\tTIGHT-V gap=%.1f\t%@ %@\t%@ %@\n", lang, tab, gap, Name(leaves[i]), NSStringFromRect(a), Name(leaves[j]), NSStringFromRect(b)];
            else if (vov > 0 && hgap >= 0 && hgap < 2) [report appendFormat:@"%@\t%@\tTIGHT-H gap=%.1f\t%@ %@\t%@ %@\n", lang, tab, hgap, Name(leaves[i]), NSStringFromRect(a), Name(leaves[j]), NSStringFromRect(b)];
        }
    }
}
int main(int argc, char **argv) { @autoreleasepool {
    [NSApplication sharedApplication];
    NSMutableString *report = [NSMutableString string];
    TSPreferences *owner = [TSPreferences new];
    for (int a = 1; a < argc; a++) {
        NSString *path = @(argv[a]);
        NSString *file = [path stringByAppendingPathComponent:@"keyedobjects-101300.nib"];
        if (![NSFileManager.defaultManager fileExistsAtPath:file]) file = [path stringByAppendingPathComponent:@"keyedobjects.nib"];
        NSNib *nib = [[NSNib alloc] initWithNibData:[NSData dataWithContentsOfFile:file] bundle:nil];
        NSArray *objects;
        if (![nib instantiateWithOwner:owner topLevelObjects:&objects]) { fprintf(stderr, "load failed %s\n", argv[a]); return 1; }
        NSString *lang = path.stringByDeletingLastPathComponent.lastPathComponent.stringByDeletingPathExtension;
        for (id o in objects) {
            if (![o isKindOfClass:NSWindow.class]) continue;
            NSWindow *w = o; NSTabView *tabs = MainTabs(w.contentView);
            if (!tabs) continue;
            w.appearance = [NSAppearance appearanceNamed:NSAppearanceNameAqua];
            for (NSInteger t = 0; t < tabs.numberOfTabViewItems; t++) {
                [tabs selectTabViewItemAtIndex:t];
                NSView *tv = tabs.tabViewItems[t].view;
                NSMutableArray *nested = [NSMutableArray array]; NSMutableArray *st = [NSMutableArray arrayWithObject:tv];
                while (st.count) { NSView *v = st.lastObject; [st removeLastObject]; if (v != tv && [v isKindOfClass:NSTabView.class]) [nested addObject:v]; [st addObjectsFromArray:v.subviews]; }
                NSInteger inner = 1; for (NSTabView *n in nested) inner = MAX(inner, n.numberOfTabViewItems);
                for (NSInteger k = 0; k < inner; k++) {
                    for (NSTabView *n in nested) if (k < n.numberOfTabViewItems) [n selectTabViewItemAtIndex:k];
                    [w.contentView layoutSubtreeIfNeeded]; [w displayIfNeeded];
                    NSString *tag = nested.count ? [NSString stringWithFormat:@"%ld.%ld", (long)t, (long)k] : [NSString stringWithFormat:@"%ld", (long)t];
                    Check(lang, tag, w.contentView, tv, report);
                }
            }
            [w close];
        }
    }
    fputs(report.UTF8String, stdout);
} return 0; }
