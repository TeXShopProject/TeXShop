#pragma once
#import <Cocoa/Cocoa.h>

// Keep the first two entries in their historical order for saved preferences.
static inline NSArray<NSString *> *TSInvisibleMarkers(NSString *key)
{
    if ([key isEqualToString:@"SpaceCharacterKind"]) return @[@"␣", @"·"];
    if ([key isEqualToString:@"FullwidthSpaceCharacterKind"]) return @[@"□", @"■"];
    if ([key isEqualToString:@"NewLineCharacterKind"]) return @[@"↵", @"¶", @"↩", @"⏎"];
    if ([key isEqualToString:@"TabCharacterKind"]) return @[@"‣", @"▹", @"⇥"];
    return @[];
}

static inline NSInteger TSInvisibleMarkerIndex(NSInteger index, NSUInteger count)
{
    return index >= 0 && (NSUInteger)index < count ? index : 0;
}

static inline NSString *TSInvisibleMarker(NSArray<NSString *> *markers, NSInteger index)
{
    return markers.count ? markers[TSInvisibleMarkerIndex(index, markers.count)] : @"";
}
