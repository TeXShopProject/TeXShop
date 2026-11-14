// Load TSDocument.nib and MainMenu.nib of every localization offscreen, apply
// what the application applies after loading them (ProductionLayout.inc), and
// check what TSOlderPanelLayout fits to current macOS: the Log File window, the
// two notices shown as alerts, the list of Select Source and the labels of the
// open panel's and the Save Selection panel's accessories. Nothing is ordered on screen and
// AppKit defaults stay in memory.
// Usage: OlderPanelLayout <label>|<compiled nib>|<Localizable.strings> ...
#import <Cocoa/Cocoa.h>
#import <objc/runtime.h>
#import "TestAppKitIsolation.h"
#include "LayoutChecks.inc"
#include "ProductionLayout.inc"

static int failures;
static void Fail(NSString *where, NSString *what) { printf("FAIL %s: %s\n", where.UTF8String, what.UTF8String); failures++; }
static NSRect InWindow(NSView *v) { return [v convertRect:v.bounds toView:nil]; }
static NSArray<NSView *> *All(NSView *root) {
    NSMutableArray *out = [NSMutableArray array], *queue = [NSMutableArray arrayWithObject:root];
    while (queue.count) { NSView *v = queue.lastObject; [queue removeLastObject]; [out addObject:v]; [queue addObjectsFromArray:v.subviews]; }
    return out;
}
static BOOL Shown(NSView *v) { for (; v; v = v.superview) if (v.hidden) return NO; return YES; }
static CGFloat OneLine(NSTextField *label) {
    NSTextFieldCell *cell = [label.cell copy]; cell.wraps = NO;
    return ceil([cell cellSizeForBounds:NSMakeRect(0, 0, 10000, 10000)].width);
}
static BOOL IsCJK(unichar c) { return (c >= 0x3000 && c <= 0x9FFF) || (c >= 0xFF00 && c <= 0xFFEF); }

static void CheckLogWindow(NSString *where, NSWindow *window) {
    NSView *content = window.contentView;
    NSScrollView *scroll = nil; NSMutableArray<NSButton *> *controls = [NSMutableArray array];
    for (NSView *v in content.subviews) {
        if ([v isKindOfClass:NSScrollView.class]) scroll = (NSScrollView *)v;
        else if ([v isKindOfClass:NSButton.class] && Shown(v)) [controls addObject:(NSButton *)v];
    }
    if (!scroll || controls.count < 10) { Fail(where, @"the log and its controls are not found"); return; }
    CGFloat width = NSWidth(content.bounds);
    if (NSMinX(scroll.frame) > 0 || NSMaxX(scroll.frame) < width || NSMinY(scroll.frame) > 0) Fail(where, @"the log does not reach the window's edges");
    for (NSButton *a in controls) {
        if (ceil(a.fittingSize.width) > NSWidth(a.frame) + 0.5) Fail(where, [NSString stringWithFormat:@"%@ is cut", a.title]);
        if (NSMinX(a.frame) < TSDialogMargin - 0.5 || NSMaxX(a.frame) > width - TSDialogMargin + 0.5) Fail(where, [NSString stringWithFormat:@"%@ is closer than 20 points to the window's edge", a.title]);
        if (NSMinY(a.frame) < NSMaxY(scroll.frame)) Fail(where, [NSString stringWithFormat:@"%@ runs into the log", a.title]);
        for (NSButton *b in controls)
            if (a != b && NSMaxY(a.frame) > NSMinY(b.frame) && NSMinY(a.frame) < NSMaxY(b.frame) && NSMinX(b.frame) > NSMinX(a.frame) + 12
                && NSMinX(b.frame) - NSMaxX(a.frame) < 12)
                Fail(where, [NSString stringWithFormat:@"%@ is closer than 12 points to %@", b.title, a.title]);
    }
    // Shrinking the window to its smallest width keeps the controls inside.
    if (window.contentMinSize.width < width - 0.5 && window.contentMinSize.width > 0) Fail(where, @"the window can be made narrower than its controls");
}

static void CheckNotice(NSString *where, NSWindow *panel) {
    NSAlert *alert = TSAlertForNoticePanel(panel);
    NSString *message = alert.messageText;
    if (message.length < 8) Fail(where, @"the alert has no message");
    if ([message rangeOfCharacterFromSet:NSCharacterSet.newlineCharacterSet].location != NSNotFound || [message containsString:@"  "]) Fail(where, @"the message keeps the panel's line breaks");
    for (NSUInteger i = 1; i + 1 < message.length; i++)
        if ([message characterAtIndex:i] == ' ' && IsCJK([message characterAtIndex:i - 1]) && IsCJK([message characterAtIndex:i + 1])) Fail(where, @"a space is put between CJK characters");
    NSString *button = alert.buttons.firstObject.title;
    NSString *expected = nil;
    for (NSView *v in All(panel.contentView))
        if ([v isKindOfClass:NSButton.class] && [((NSButton *)v).keyEquivalent isEqual:@"\r"]) expected = ((NSButton *)v).title;
    if (alert.buttons.count != 1 || !button.length || (expected && ![button isEqual:expected])) Fail(where, @"the alert's button is not the panel's OK");
    printf("NOTICE %s: %s [%s]\n", where.UTF8String, message.UTF8String, button.UTF8String);
}

int main(int argc, char **argv) { @autoreleasepool {
    TSInstallAppKitIsolation();
    InstallLocalizedStrings();
    [NSApplication sharedApplication]; [NSApp setActivationPolicy:NSApplicationActivationPolicyProhibited];
    NSUInteger checked = 0, notices = 0;
    for (int a = 1; a < argc; a++) {
        NSArray<NSString *> *parts = [@(argv[a]) componentsSeparatedByString:@"|"];
        NSString *label = parts[0], *name = label.lastPathComponent;
        UseLocalizedStrings(parts.count > 2 ? parts[2] : nil);
        SpacingOwner *owner = ProductionOwner(name);
        NSArray *objects = nil;
        NSApp.mainMenu = nil;
        if (![[[NSNib alloc] initWithNibData:[NSData dataWithContentsOfFile:parts[1]] bundle:nil] instantiateWithOwner:owner topLevelObjects:&objects]) { printf("ERROR %s cannot load\n", label.UTF8String); return 2; }
        NSApp.mainMenu = nil;
        ApplyProductionLayout(name, owner, objects);
        if ([name isEqual:@"CustomModalWindowController.nib"]) {
            // The sheet that changes the encoding of a file: its strings table names the label by its object ID.
            NSDictionary *table = [[NSString stringWithContentsOfFile:parts[3] encoding:NSUTF8StringEncoding error:nil] propertyListFromStringsFileFormat];
            for (id o in objects) if ([o isKindOfClass:NSWindow.class]) {
                NSWindow *w = o; NSTextField *field = nil; NSPopUpButton *popUp = nil;
                for (NSView *v in w.contentView.subviews) {
                    if ([v isKindOfClass:NSPopUpButton.class]) popUp = (NSPopUpButton *)v;
                    else if ([v isKindOfClass:NSTextField.class] && [((NSTextField *)v).stringValue isEqual:@"Encoding: "]) field = (NSTextField *)v;
                }
                if (!field || !popUp || !table[@"gGW-lx-NCF.title"]) { Fail(label, @"the encoding label, its pop-up or its translation is not found"); continue; }
                field.stringValue = table[@"gGW-lx-NCF.title"];
                [popUp addItemWithTitle:@"Japanese (Shift JIS X0213) with a long name"];
                [w.contentView layoutSubtreeIfNeeded];
                if (OneLine(field) > NSWidth(field.frame) + 0.5) Fail(label, [NSString stringWithFormat:@"%@ is cut", field.stringValue]);
                // The gap Auto Layout keeps is between alignment rectangles, which leave out a pop-up's shadow and a label's padding.
                NSRect fieldAlign = [field alignmentRectForFrame:field.frame], popUpAlign = [popUp alignmentRectForFrame:popUp.frame];
                if (NSMinX(popUpAlign) - NSMaxX(fieldAlign) < 8 - 0.5) Fail(label, @"the encoding pop-up is closer than 8 points to its label");
                if (NSMaxX(popUp.frame) > NSWidth(w.contentView.bounds) - TSDialogMargin + 0.5) Fail(label, @"the encoding pop-up reaches the window's edge");
                if (fabs(NSMidY(popUp.frame) - NSMidY(field.frame)) > 3) Fail(label, @"the encoding pop-up is not beside its label");
                // The explanation above, in its language, ends before the label's row; the buttons stay below the pop-up.
                for (NSView *v in w.contentView.subviews)
                    if ([v isKindOfClass:NSTextField.class] && v != field && NSMinY(v.frame) > NSMaxY(field.frame) - 2) {
                        NSTextField *text = (NSTextField *)v;
                        text.stringValue = table[@"Prr-63-EQ4.title"] ?: text.stringValue;
                        [w.contentView layoutSubtreeIfNeeded];
                        CGFloat needed = [text.cell cellSizeForBounds:NSMakeRect(0, 0, NSWidth(text.frame), 10000)].height;
                        if (needed > NSHeight(text.frame) + 0.5) Fail(label, @"the explanation is cut");
                        if (NSMinY(text.frame) - NSMaxY([popUp alignmentRectForFrame:popUp.frame]) < 8 && NSMinY(text.frame) - NSMaxY(field.frame) < 8) Fail(label, @"the explanation runs into the encoding row");
                    }
                for (NSView *v in w.contentView.subviews)
                    if ([v isKindOfClass:NSButton.class] && ![v isKindOfClass:NSPopUpButton.class] && NSMaxY([v alignmentRectForFrame:v.frame]) > NSMinY([popUp alignmentRectForFrame:popUp.frame]) - 12)
                        Fail(label, @"a button runs into the encoding row");
                checked++;
            }
            continue;
        }
        if ([name isEqual:@"TSDocument.nib"]) {
            CheckLogWindow([label stringByAppendingString:@" Log File"], owner.logWindow);
            CheckNotice([label stringByAppendingString:@" printRequestPanel"], owner->printRequestPanel);
            CheckNotice([label stringByAppendingString:@" requestWindow"], owner->requestWindow);
            BOOL imageType = NO;
            for (id o in objects)
                if ([o isKindOfClass:NSView.class])
                    for (NSView *v in [o subviews])
                        if ([v isKindOfClass:NSPopUpButton.class] && [[((NSPopUpButton *)v).itemTitles componentsJoinedByString:@"\n"] containsString:@"JPEG"])
                            for (NSView *t in [o subviews])
                                if ([t isKindOfClass:NSTextField.class] && NSMinX(t.frame) < NSMinX(v.frame) && NSMaxX(t.frame) < NSMidX(v.frame)) {
                                    imageType = YES;
                                    NSTextField *field = (NSTextField *)t;
                                    if (fabs(field.font.pointSize - ((NSPopUpButton *)v).font.pointSize) > 0.01) Fail(label, @"Image Type: is smaller than its pop-up");
                                    if (fabs(NSMidY(field.frame) - NSMidY(v.frame)) > 1) Fail(label, @"Image Type: is not centered on its pop-up");
                                    if (OneLine(field) > NSWidth(field.frame) + 0.5 || NSMaxX(field.frame) > NSMinX(v.frame) - 4 || NSMinX(field.frame) < 0) Fail(label, @"Image Type: is cut or runs under its pop-up");
                                }
            if (!imageType) Fail(label, @"the Image Type accessory is not found");
            checked += 4; notices += 2;
        } else {
            BOOL table = NO, accessory = NO;
            for (id o in objects) {
                NSView *root = [o isKindOfClass:NSWindow.class] ? [o contentView] : [o isKindOfClass:NSView.class] ? o : nil;
                for (NSView *v in root ? All(root) : @[]) {
                    if ([v isKindOfClass:NSTableView.class]) {
                        table = YES;
                        if (((NSTableView *)v).gridStyleMask & NSTableViewSolidVerticalGridLineMask) Fail(label, @"the list of Select Source draws vertical grid lines");
                    }
                    if ([o isKindOfClass:NSView.class] && [v isKindOfClass:NSPopUpButton.class]) {
                        for (NSView *t in v.superview.subviews)
                            if ([t isKindOfClass:NSTextField.class] && !((NSTextField *)t).editable && NSMinX(t.frame) < NSMinX(v.frame) && NSMaxX(t.frame) < NSMidX(v.frame)) {
                                accessory = YES;
                                NSTextField *field = (NSTextField *)t;
                                if (fabs(field.font.pointSize - ((NSPopUpButton *)v).font.pointSize) > 0.01) Fail(label, @"Encoding: is smaller than its pop-up");
                                if (fabs(NSMidY(field.frame) - NSMidY(v.frame)) > 1) Fail(label, @"Encoding: is not centered on its pop-up");
                                if (OneLine(field) > NSWidth(field.frame) + 0.5) Fail(label, @"Encoding: is cut");
                                if (NSMaxX(field.frame) > NSMinX(v.frame) - 4 || NSMinX(field.frame) < 0) Fail(label, @"Encoding: runs under its pop-up or out of the view");
                            }
                    }
                }
            }
            if (!table || !accessory) Fail(label, @"the list or the encoding accessory is not found");
            checked += 2;
        }
    }
    if (failures) { printf("FAIL: %d problems\n", failures); return 1; }
    printf("PASS: %lu panels in %d interfaces, %lu notices as alerts\n", (unsigned long)checked, argc - 1, (unsigned long)notices);
} return 0; }
