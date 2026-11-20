// SPDX-License-Identifier: GPL-2.0-or-later
#pragma once
#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

// Fonts read from the settings. A font that is no longer installed, a size of 0, or settings data that is damaged,
// written by hand or by another version give nil or raise in AppKit; text views and the font panel raise when given
// nil (-setFont:, -convertFont:). Every font read from the settings goes through these.

// The font that the settings name, or `fallback` when it is not installed or the name or size is unusable.
static inline NSFont *TSFontNamed(id _Nullable name, CGFloat size, NSFont *fallback)
{
    if (![name isKindOfClass:NSString.class] || [(NSString *)name length] == 0 || !(size > 0) || !isfinite(size))
        return fallback;
    return [NSFont fontWithName:(NSString *)name size:size] ?: fallback;
}

// The console font of the settings, or a fixed-pitch font of its size.
static inline NSFont *TSConsoleFontFromDefaults(NSUserDefaults *defaults, NSString *nameKey, NSString *sizeKey)
{
    CGFloat size = [defaults floatForKey:sizeKey];
    if (!(size > 0) || !isfinite(size)) size = 12.0;
    NSFont *fallback = [NSFont userFixedPitchFontOfSize:size] ?: [NSFont monospacedSystemFontOfSize:size weight:NSFontWeightRegular];
    return TSFontNamed([defaults objectForKey:nameKey], size, fallback);
}

// The object archived with NSArchiver in settings data, when it is of `expected` class; nil for anything else.
static inline id _Nullable TSUnarchivedObject(id _Nullable data, Class expected)
{
    if (![data isKindOfClass:NSData.class]) return nil;
    id object = nil;
    @try {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
        object = [NSUnarchiver unarchiveObjectWithData:(NSData *)data];
#pragma clang diagnostic pop
    } @catch (NSException *exception) {
        object = nil;
    }
    return [object isKindOfClass:expected] ? object : nil;
}

// The document font of the settings (DocumentFontKey, archived), or nil when there is none that can be used.
static inline NSFont * _Nullable TSArchivedFont(id _Nullable data)
{
    return TSUnarchivedObject(data, NSFont.class);
}

NS_ASSUME_NONNULL_END
