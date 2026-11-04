// added by Terada: Keep the user's Dock artwork when the application is not running.
// SPDX-License-Identifier: GPL-2.0-or-later
#import "../TSDockIcon.h"
@interface TSDockIconPlugin : NSObject <NSDockTilePlugIn>
@property (strong) NSDockTile *tile;
@property (strong) NSBundle *applicationBundle;
@property (copy) NSString *applicationIdentifier;
@property (strong) NSMutableDictionary<NSString *, NSImage *> *cachedImages;
@end
@implementation TSDockIconPlugin
- (void)setDockTile:(NSDockTile *)tile {
    [[NSDistributedNotificationCenter defaultCenter] removeObserver:self];
    self.tile = tile;
    if (!tile) { self.cachedImages = nil; return; }
    NSURL *url = [NSBundle bundleForClass:self.class].bundleURL;
    for (int i = 0; i < 3; i++) url = url.URLByDeletingLastPathComponent;
    self.applicationBundle = [NSBundle bundleWithURL:url];
    NSString *identifier = self.applicationBundle.bundleIdentifier;
    if (!identifier.length) return;
    self.applicationIdentifier = identifier;
    self.cachedImages = [NSMutableDictionary dictionary];
    for (NSString *name in TSDockIconNames()) {
        NSImage *image = TSDockIconImage(self.applicationBundle, name);
        NSData *pixels = image.TIFFRepresentation;
        if (pixels) self.cachedImages[name] = [[NSImage alloc] initWithData:pixels];
    }
    [[NSDistributedNotificationCenter defaultCenter] addObserver:self selector:@selector(refresh:) name:TSDockIconChanged object:identifier suspensionBehavior:NSNotificationSuspensionBehaviorDeliverImmediately];
    [self refresh:nil];
}
- (void)refresh:(NSNotification *)notification {
    NSString *identifier = self.applicationIdentifier;
    if (!identifier) return;
    NSURL *installedURL = [[NSWorkspace sharedWorkspace] URLForApplicationWithBundleIdentifier:identifier];
    NSBundle *installed = installedURL ? [NSBundle bundleWithURL:installedURL] : nil;
    if ([installed.bundleIdentifier isEqualToString:identifier]) self.applicationBundle = installed;
    CFPreferencesAppSynchronize((__bridge CFStringRef)identifier);
    NSString *name = CFBridgingRelease(CFPreferencesCopyAppValue((__bridge CFStringRef)TSDockIconKey, (__bridge CFStringRef)identifier));
    name = TSDockIconName(name);
    NSImage *image = nil;
    if (![name isEqualToString:@"current"]) {
        image = TSDockIconImage(self.applicationBundle, name) ?: self.cachedImages[name];
    }
    TSApplyDockImage(self.tile, image);
}
- (void)dealloc { [[NSDistributedNotificationCenter defaultCenter] removeObserver:self]; }
@end
