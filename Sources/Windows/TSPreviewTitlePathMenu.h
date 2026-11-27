// SPDX-License-Identifier: GPL-2.0-or-later
#import <AppKit/AppKit.h>

// In preview windows outside document management, and in the window that shows the source and
// the Preview, the title NSTextField can consume Command-clicks without opening AppKit's path menu
// (observed on macOS 27).
// Redirect clicks on the title text to the document icon and let NSWindow handle them.
// AppKit still builds the menu, handles its items, and consults the window delegate.
static inline NSEvent *TSPreviewTitlePathMenuEvent(NSWindow *window, NSEvent *event)
{
    if (event.type != NSEventTypeLeftMouseDown || !(event.modifierFlags & NSEventModifierFlagCommand)
        || window.representedURL == nil || window.titleVisibility != NSWindowTitleVisible)
        return nil;

    NSView *frame = window.contentView.superview;
    NSView *hit = [frame hitTest:[frame convertPoint:event.locationInWindow fromView:nil]];
    NSButton *icon = [window standardWindowButton:NSWindowDocumentIconButton];
    if (![hit isKindOfClass:NSTextField.class] || [hit isDescendantOf:window.contentView]
        || ((NSTextField *)hit).isEditable || ![((NSTextField *)hit).stringValue isEqualToString:window.title]
        || icon == nil || icon.superview == nil || icon.isHiddenOrHasHiddenAncestor)
        return nil;

    // Exclude toolbar fields and other controls. The title is at the same height as the document icon.
    NSRect iconRect = [icon convertRect:icon.bounds toView:nil];
    if (event.locationInWindow.y < NSMinY(iconRect) || event.locationInWindow.y > NSMaxY(iconRect))
        return nil;

    return [NSEvent mouseEventWithType:event.type
                            location:NSMakePoint(NSMidX(iconRect), NSMidY(iconRect))
                       modifierFlags:event.modifierFlags timestamp:event.timestamp
                        windowNumber:event.windowNumber context:nil eventNumber:event.eventNumber
                          clickCount:event.clickCount pressure:event.pressure];
}
