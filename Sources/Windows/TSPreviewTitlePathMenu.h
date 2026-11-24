// SPDX-License-Identifier: GPL-2.0-or-later
#import <AppKit/AppKit.h>

// 文書管理外のプレビューでは、タイトルの NSTextField が Command クリックを
// 受け取り、AppKit の親パスメニューが開かない場合がある（macOS 27 で確認）。
// タイトル文字へのクリックだけを書類アイコンの中心へ移し、NSWindow の標準処理に渡す。
// メニューの生成、項目の操作、delegate の判断はすべて AppKit に任せる。
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

    // ツールバーの入力欄などを転送しない。タイトルは書類アイコンと同じ高さにある。
    NSRect iconRect = [icon convertRect:icon.bounds toView:nil];
    if (event.locationInWindow.y < NSMinY(iconRect) || event.locationInWindow.y > NSMaxY(iconRect))
        return nil;

    return [NSEvent mouseEventWithType:event.type
                            location:NSMakePoint(NSMidX(iconRect), NSMidY(iconRect))
                       modifierFlags:event.modifierFlags timestamp:event.timestamp
                        windowNumber:event.windowNumber context:nil eventNumber:event.eventNumber
                          clickCount:event.clickCount pressure:event.pressure];
}
