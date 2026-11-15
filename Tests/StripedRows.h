#pragma once
#import <Cocoa/Cocoa.h>
// Whether a list draws its rows striped in an appearance: the list and its
// scroll view are drawn offscreen over the window background, and the empty
// right ends of three neighboring rows are compared. The list should have at
// least three rows and none of the first three selected.
static NSColor *TSTestRowEndColor(NSBitmapImageRep *rep, NSView *drawn, NSTableView *table, NSInteger row)
{
    NSRect rect = [table convertRect:[table rectOfRow:row] toView:drawn];
    CGFloat scale = rep.pixelsWide / NSWidth(drawn.bounds);
    CGFloat y = NSMidY(rect); if (!drawn.isFlipped) y = NSHeight(drawn.bounds) - y;
    return [[rep colorAtX:(NSInteger)((NSMaxX(rect) - 40) * scale) y:(NSInteger)(y * scale)] colorUsingColorSpace:NSColorSpace.sRGBColorSpace];
}
static CGFloat TSTestColorDistance(NSColor *a, NSColor *b)
{
    return fabs(a.redComponent - b.redComponent) + fabs(a.greenComponent - b.greenComponent) + fabs(a.blueComponent - b.blueComponent);
}
static BOOL TSTestRowsStriped(NSTableView *table, NSAppearanceName name, NSString **detail)
{
    NSWindow *window = table.window;
    NSView *drawn = table.enclosingScrollView ?: table;
    NSAppearance *previous = window.appearance, *appearance = [NSAppearance appearanceNamed:name];
    window.appearance = appearance;
    // Row views take their colors when drawn, so draw once before capturing.
    for (int i = 0; i < 2; i++) {
        [window.contentView layoutSubtreeIfNeeded]; [drawn display];
        [NSRunLoop.currentRunLoop runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.02]];
    }
    NSBitmapImageRep *capture = [drawn bitmapImageRepForCachingDisplayInRect:drawn.bounds];
    [appearance performAsCurrentDrawingAppearance:^{ [drawn cacheDisplayInRect:drawn.bounds toBitmapImageRep:capture]; }];
    // Stripes may be translucent: lay the capture on the window background.
    NSBitmapImageRep *rep = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL pixelsWide:capture.pixelsWide pixelsHigh:capture.pixelsHigh bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES isPlanar:NO colorSpaceName:NSCalibratedRGBColorSpace bytesPerRow:0 bitsPerPixel:0];
    [NSGraphicsContext saveGraphicsState];
    NSGraphicsContext.currentContext = [NSGraphicsContext graphicsContextWithBitmapImageRep:rep];
    NSRect whole = NSMakeRect(0, 0, capture.pixelsWide, capture.pixelsHigh);
    [appearance performAsCurrentDrawingAppearance:^{ [NSColor.windowBackgroundColor setFill]; NSRectFill(whole); }];
    [capture drawInRect:whole fromRect:NSZeroRect operation:NSCompositingOperationSourceOver fraction:1 respectFlipped:NO hints:nil];
    [NSGraphicsContext restoreGraphicsState];
    window.appearance = previous;
    if (table.numberOfRows < 3) { if (detail) *detail = @"too few rows to compare"; return NO; }
    NSColor *first = TSTestRowEndColor(rep, drawn, table, 0), *second = TSTestRowEndColor(rep, drawn, table, 1), *third = TSTestRowEndColor(rep, drawn, table, 2);
    CGFloat neighbors = TSTestColorDistance(first, second), alternate = TSTestColorDistance(first, third);
    if (detail) *detail = [NSString stringWithFormat:@"%@ neighbors %.3f, every other row %.3f (rgb %.3f %.3f %.3f / %.3f %.3f %.3f)", name, neighbors, alternate,
                           first.redComponent, first.greenComponent, first.blueComponent, second.redComponent, second.greenComponent, second.blueComponent];
    // Neighboring rows differ visibly; every other row is the same.
    return neighbors >= 0.03 && alternate < 0.01;
}
