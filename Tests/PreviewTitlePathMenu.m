#import <Cocoa/Cocoa.h>
#import "TSPreviewTitlePathMenu.h"

static NSUInteger checks;
static void check(BOOL value, NSString *message) {
    checks++;
    if (!value) { fprintf(stderr, "FAIL: %s\n", message.UTF8String); exit(1); }
}
static NSTextField *titleField(NSView *view, NSString *title) {
    if ([view isKindOfClass:NSTextField.class] && [((NSTextField *)view).stringValue isEqual:title])
        return (NSTextField *)view;
    for (NSView *child in view.subviews) {
        NSTextField *found = titleField(child, title);
        if (found) return found;
    }
    return nil;
}
static NSEvent *click(NSWindow *window, NSView *view, NSEventModifierFlags flags, NSEventType type) {
    NSPoint point = [view convertPoint:NSMakePoint(NSMidX(view.bounds), NSMidY(view.bounds)) toView:nil];
    return [NSEvent mouseEventWithType:type location:point modifierFlags:flags timestamp:123
        windowNumber:window.windowNumber context:nil eventNumber:12 clickCount:1 pressure:0.5];
}
int main(void) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        for (NSNumber *fullSize in @[@NO, @YES]) {
            NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 1000, 400)
                styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskResizable
                backing:NSBackingStoreBuffered defer:NO];
            if (fullSize.boolValue) {
                window.toolbarStyle = NSWindowToolbarStyleExpanded;
                window.toolbar = [[NSToolbar alloc] initWithIdentifier:@"test"];
                window.styleMask |= NSWindowStyleMaskFullSizeContentView;
            }
            window.representedURL = [NSURL fileURLWithPath:@"/tmp/日本語 空白/sample.pdf"];
            for (NSString *name in @[@"sample.pdf", @"/tmp/日本語 空白/sample.pdf"]) {
                window.title = name;
                [window layoutIfNeeded];
                NSTextField *title = titleField(window.contentView.superview, name);
                check(title != nil, @"AppKit の実際のタイトル文字を取得できる");
                NSEvent *original = click(window, title, NSEventModifierFlagCommand, NSEventTypeLeftMouseDown);
                NSEvent *forward = TSPreviewTitlePathMenuEvent(window, original);
                check(forward != nil, @"ファイル名とフルパスのどちらでも転送される");
                NSButton *icon = [window standardWindowButton:NSWindowDocumentIconButton];
                NSRect iconRect = [icon convertRect:icon.bounds toView:nil];
                check(NSPointInRect(forward.locationInWindow, iconRect), @"転送先は標準書類アイコン");
                check(forward.modifierFlags == original.modifierFlags && forward.windowNumber == original.windowNumber
                    && forward.timestamp == original.timestamp && forward.eventNumber == original.eventNumber,
                    @"イベントの修飾キーと識別情報を維持する");
                check(TSPreviewTitlePathMenuEvent(window, click(window, title, 0, NSEventTypeLeftMouseDown)) == nil,
                    @"通常のタイトルクリックは変更しない");
                check(TSPreviewTitlePathMenuEvent(window, click(window, title, NSEventModifierFlagCommand, NSEventTypeLeftMouseUp)) == nil,
                    @"マウスを離すイベントは変更しない");
                check(TSPreviewTitlePathMenuEvent(window, click(window, icon, NSEventModifierFlagCommand, NSEventTypeLeftMouseDown)) == nil,
                    @"書類アイコン自体は既存の処理に任せる");
                title.editable = YES;
                check(TSPreviewTitlePathMenuEvent(window, original) == nil, @"編集可能な欄を転送しない");
                title.editable = NO;
                NSTextField *body = [NSTextField labelWithString:name];
                body.frame = NSMakeRect(10, 100, 800, 30);
                [window.contentView addSubview:body];
                check(TSPreviewTitlePathMenuEvent(window, click(window, body, NSEventModifierFlagCommand, NSEventTypeLeftMouseDown)) == nil,
                    @"タイトルと同じ内容の本文ラベルを転送しない");
                [body removeFromSuperview];
            }
            NSURL *url = window.representedURL;
            NSTextField *title = titleField(window.contentView.superview, window.title);
            NSEvent *original = click(window, title, NSEventModifierFlagCommand, NSEventTypeLeftMouseDown);
            window.representedURL = nil;
            check(TSPreviewTitlePathMenuEvent(window, original) == nil, @"ファイル未指定ならメニューを要求しない");
            window.representedURL = url;
            window.titleVisibility = NSWindowTitleHidden;
            check(TSPreviewTitlePathMenuEvent(window, original) == nil, @"非表示のタイトルは転送しない");
        }
        printf("PASS: %lu preview title path menu checks\n", (unsigned long)checks);
    }
}
