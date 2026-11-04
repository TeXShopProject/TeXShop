// added by Terada: Keep the user's Dock artwork when the application is not running.
// SPDX-License-Identifier: GPL-2.0-or-later
#import "../TSDockIcon.h"
@interface TSDockIconPlugin : NSObject <NSDockTilePlugIn>
@property (strong) NSDockTile *tile;
@property (strong) NSBundle *applicationBundle;
@end
@implementation TSDockIconPlugin
- (void)setDockTile:(NSDockTile *)tile {
    [[NSDistributedNotificationCenter defaultCenter] removeObserver:self];
    self.tile = tile;
    if (!tile) return;
    NSURL *url = [NSBundle bundleForClass:self.class].bundleURL;
    for (int i = 0; i < 3; i++) url = url.URLByDeletingLastPathComponent;
    self.applicationBundle = [NSBundle bundleWithURL:url];
    NSString *identifier = self.applicationBundle.bundleIdentifier;
    if (!identifier.length) return;
    [[NSDistributedNotificationCenter defaultCenter] addObserver:self selector:@selector(refresh:) name:TSDockIconChanged object:identifier suspensionBehavior:NSNotificationSuspensionBehaviorDeliverImmediately];
    [self refresh:nil];
}
- (void)refresh:(NSNotification *)notification {
    NSString *identifier = self.applicationBundle.bundleIdentifier;
    if (!identifier) return;
    CFPreferencesAppSynchronize((__bridge CFStringRef)identifier);
    NSString *name = CFBridgingRelease(CFPreferencesCopyAppValue((__bridge CFStringRef)TSDockIconKey, (__bridge CFStringRef)identifier));
    TSApplyDockIcon(self.tile, self.applicationBundle, TSDockIconName(name));
}
- (void)dealloc { [[NSDistributedNotificationCenter defaultCenter] removeObserver:self]; }
@end
