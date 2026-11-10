#pragma once
#import <Cocoa/Cocoa.h>

// Control characters other than tab, line feed and carriage return. The editor
// always shows them as U+FFFD; otherwise they would take no space, and a form
// feed would hide the rest of the document.
static inline BOOL TSIsShownControlCharacter(unichar character)
{
    return character <= 0x08 || (character >= 0x0B && character <= 0x1F && character != 0x0D);
}

static NSString *const TSControlCharacterMarker = @"\uFFFD";

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

// Additional choices use a separate key so an older TeXShop still sees 0 or 1.
static inline NSString *TSInvisibleExtendedKey(NSString *key)
{
    return [key stringByAppendingString:@"Extended"];
}

static inline NSInteger TSInvisibleStoredIndex(NSUserDefaults *defaults, NSString *key)
{
    NSInteger legacy = [defaults integerForKey:key];
    id extended = [defaults objectForKey:TSInvisibleExtendedKey(key)];
    // Honor a selection of the second historical marker made in an older app.
    NSInteger selected = (legacy == 0 && extended != nil) ? [extended integerValue] : legacy;
    return TSInvisibleMarkerIndex(selected, TSInvisibleMarkers(key).count);
}

static inline void TSSetInvisibleIndex(NSUserDefaults *defaults, NSString *key, NSInteger index)
{
    NSString *extendedKey = TSInvisibleExtendedKey(key);
    index = TSInvisibleMarkerIndex(index, TSInvisibleMarkers(key).count);
    [defaults setInteger:index < 2 ? index : 0 forKey:key];
    if (index >= 2) [defaults setInteger:index forKey:extendedKey];
    else [defaults removeObjectForKey:extendedKey];
}
