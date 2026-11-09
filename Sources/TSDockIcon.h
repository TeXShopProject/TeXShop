// Shared drawing for the application and its Dock plug-in.
// SPDX-License-Identifier: GPL-2.0-or-later
#import <Cocoa/Cocoa.h>

static NSString * const TSDockIconKey = @"DockIconStyle";
static inline NSArray<NSString *> *TSDockIconNames(void) {
    return @[@"original", @"triangle", @"retina", @"round", @"current"];
}
static inline NSString *TSDockIconName(id value) {
    return [TSDockIconNames() containsObject:value ?: @""] ? value : @"current";
}
static inline NSImage *TSDockIconImage(NSBundle *bundle, NSString *name) {
    NSString *path = [bundle pathForResource:TSDockIconName(name) ofType:@"png" inDirectory:@"DockIcons"];
    return path ? [[NSImage alloc] initWithContentsOfFile:path] : nil;
}
static inline void TSApplyDockImage(NSDockTile *tile, NSImage *image) {
    if (!tile) return;
    if (image) {
        NSImageView *view = [[NSImageView alloc] initWithFrame:NSMakeRect(0, 0, tile.size.width, tile.size.height)];
        view.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
        view.imageScaling = NSImageScaleProportionallyUpOrDown;
        view.image = image;
        tile.contentView = view;
    } else {
        tile.contentView = nil;
    }
    [tile display];
}

static inline void TSApplyDockIcon(NSDockTile *tile, NSBundle *bundle, NSString *name) {
    name = TSDockIconName(name);
    TSApplyDockImage(tile, [name isEqualToString:@"current"] ? nil : TSDockIconImage(bundle, name));
}
