// Console output stays selectable during typesetting: appending never replaces
// the selection, and leaving the input field does not send it.
#import <Cocoa/Cocoa.h>
#import "TestAppKitIsolation.h"
#import "TSConsoleOutput.h"

static int failures;
static void Require(const char *name, BOOL condition)
{
    if (!condition) { printf("FAIL %s\n", name); failures++; }
}

int main(void)
{
    @autoreleasepool {
        TSInstallAppKitIsolation();
        [NSApplication sharedApplication];
        NSScrollView *scroll = [[NSScrollView alloc] initWithFrame:NSMakeRect(0, 0, 300, 60)];
        NSTextView *view = [[NSTextView alloc] initWithFrame:NSMakeRect(0, 0, 300, 60)];
        scroll.documentView = view;
        view.editable = NO;
        view.selectable = YES;
        TSAppendConsoleOutput(view, @"! Undefined control sequence.\nl.3 \\foo\n?", nil);
        Require("output appended", [view.string hasSuffix:@"?"]);
        Require("caret follows output", NSEqualRanges(view.selectedRange, NSMakeRange(view.string.length, 0)));

        // A selection survives later output, which goes to the end.
        NSRange selected = NSMakeRange(2, 9);
        view.selectedRange = selected;
        NSString *copied = [view.string substringWithRange:selected];
        TSAppendConsoleOutput(view, @" x\n", [NSColor redColor]);
        Require("selection kept", NSEqualRanges(view.selectedRange, selected));
        Require("selected text untouched", [[view.string substringWithRange:selected] isEqualToString:copied]);
        Require("echo at the end", [view.string hasSuffix:@"? x\n"]);
        NSColor *red = [view.textStorage attribute:NSForegroundColorAttributeName atIndex:view.string.length - 2 effectiveRange:NULL];
        NSColor *before = [view.textStorage attribute:NSForegroundColorAttributeName atIndex:0 effectiveRange:NULL];
        Require("only the echo is red", [red isEqual:[NSColor redColor]] && ![before isEqual:[NSColor redColor]]);

        // Copy goes through the text view, here to a private pasteboard.
        NSPasteboard *pasteboard = [NSPasteboard pasteboardWithUniqueName];
        Require("selection copies", [view writeSelectionToPasteboard:pasteboard types:view.writablePasteboardTypes] &&
                [[pasteboard stringForType:NSPasteboardTypeString] isEqualToString:copied]);
        [pasteboard releaseGlobally];

        // Without a selection the caret follows the output again.
        view.selectedRange = NSMakeRange(0, 0);
        TSAppendConsoleOutput(view, @"done\n", nil);
        Require("caret follows output again", NSEqualRanges(view.selectedRange, NSMakeRange(view.string.length, 0)));

        // Leaving the field must not send an empty line to TeX.
        NSTextField *field = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 0, 100, 20)];
        [(NSTextFieldCell *)field.cell setSendsActionOnEndEditing:YES];
        TSConfigureConsoleInput(field);
        Require("field sends only on Return", ![(NSTextFieldCell *)field.cell sendsActionOnEndEditing]);
        if (failures) return 1;
        printf("PASS: console output keeps the selection and the input field sends only on Return\n");
    }
    return 0;
}
