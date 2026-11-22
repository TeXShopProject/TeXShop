// SPDX-License-Identifier: GPL-2.0-or-later
// The colors of a theme that may give way to the system's: the cursor and the selection of the source. Each has a
// switch in the theme, "Use system color" in Settings, which keeps the theme's color while it is on.
#pragma once
#import <Cocoa/Cocoa.h>

typedef NSString *TSThemeSystemColorKey NS_TYPED_EXTENSIBLE_ENUM;
// The color of the selection of the source. The cursor's is EditorInsertionPoint.
static TSThemeSystemColorKey const TSThemeSelectionKey = @"EditorSelection";
// The switches.
static TSThemeSystemColorKey const TSThemeInsertionPointUsesSystemColorKey = @"EditorInsertionPointUsesSystemColor";
static TSThemeSystemColorKey const TSThemeSelectionUsesSystemColorKey = @"EditorSelectionUsesSystemColor";

static inline BOOL TSThemeIsSystemColorSwitch(id key)
{
    return [key isEqual:TSThemeInsertionPointUsesSystemColorKey] || [key isEqual:TSThemeSelectionUsesSystemColorKey];
}

// Whether the system's color is drawn instead of the theme's. A theme without the switch, or with anything but a number
// in its place (written by hand), gets what TeXShop drew before there were switches: its own cursor color and the
// system's selection color.
static inline BOOL TSThemeUsesSystemColor(NSDictionary *theme, TSThemeSystemColorKey switchKey)
{
    id value = [theme isKindOfClass:NSDictionary.class] ? theme[switchKey] : nil;
    if ([value isKindOfClass:NSNumber.class])
        return [value boolValue];
    return [switchKey isEqualToString:TSThemeSelectionUsesSystemColorKey];
}

// Gives a text view its selection color, each time its theme's colors are applied: the system's included, so that a
// view whose theme turns the switch on again draws the system's, not the color it had.
static inline void TSThemeSetSelectionColor(NSTextView *view, NSColor *color)
{
    if (view == nil)
        return;
    NSMutableDictionary *attributes = [NSMutableDictionary dictionaryWithDictionary:view.selectedTextAttributes ?: @{}];
    attributes[NSBackgroundColorAttributeName] = color ?: NSColor.selectedTextBackgroundColor;
    view.selectedTextAttributes = attributes;
}
