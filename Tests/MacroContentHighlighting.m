// The macro editor colors its contents as the source is colored, in the theme's
// colors: a TeX macro by the rules of the source, an AppleScript macro by its own,
// each with its placeholders. Coloring follows a new macro, typing, undo, the
// window's appearance and the Syntax Color setting, waits while text is composed,
// and leaves the attributes of other features and the text itself alone. No window
// is shown and the defaults stay in memory.
#import <Cocoa/Cocoa.h>
#import "TestAppKitIsolation.h"
#import "TSMacroEditor.h"
#import "TSColorSupport.h"
#import "TSSyntaxHighlighter.h"
#import "TSSyntaxMacroContentScanner.h"
#import "TSSyntaxTeXScanner.h"
#import "TSPreferenceEffects.h"
#import "TSAdvancedFindTextView.h"
#import "TSAdvancedFindPanelController.h"
#import "globals.h"
// The source's text view and the Advanced Find controller are not needed here, only their classes.
@interface TSTextView : NSTextView
@end
@implementation TSTextView
@end
@implementation TSAdvancedFindController
@end
@implementation TSAdvancedFindPanelController
@end
#define REQUIRE(...) do { if (!(__VA_ARGS__)) { fprintf(stderr,"FAIL %d: %s\n",__LINE__,#__VA_ARGS__); exit(1); } } while(0)
@implementation TSMacroEditor
#include "MacroContentHighlighting.inc"
- (void)setValue:(id)v forUndefinedKey:(NSString *)k {}
@end
static void Spin(void) { [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.02]]; }
static BOOL Same(NSColor *a, NSColor *b) {
    NSColor *x=[a colorUsingColorSpace:NSColorSpace.sRGBColorSpace], *y=[b colorUsingColorSpace:NSColorSpace.sRGBColorSpace];
    return x && y && fabs(x.redComponent-y.redComponent)<.002 && fabs(x.greenComponent-y.greenComponent)<.002 && fabs(x.blueComponent-y.blueComponent)<.002;
}
static NSTextView *contents;
static NSDictionary *At(NSString *text) {
    NSRange range = [contents.string rangeOfString:text];
    REQUIRE(range.location != NSNotFound);
    return [contents.layoutManager temporaryAttributesAtCharacterIndex:range.location effectiveRange:NULL];
}
static NSColor *ColorAt(NSString *text) { return At(text)[NSForegroundColorAttributeName]; }
static BOOL Plain(NSString *text) { return ColorAt(text) == nil; }
static TSSyntaxColorScheme *Scheme(NSDictionary *theme, BOOL dark) { return [[TSSyntaxColorScheme alloc] initWithTheme:theme dark:dark]; }
static NSColor *RoleColor(TSSyntaxColorScheme *scheme, TSSyntaxRole role) { return [scheme attributesForRole:role][NSForegroundColorAttributeName]; }

int main(int argc, char **argv) { @autoreleasepool {
    TSInstallAppKitIsolation();
    [NSApplication sharedApplication];
    liteColors = [NSDictionary dictionaryWithContentsOfFile:@(argv[1])];
    darkColors = [NSDictionary dictionaryWithContentsOfFile:@(argv[2])];
    REQUIRE(liteColors && darkColors);
    g_texChar = '\\';  // as TSAppDelegate sets it for encodings other than the Japanese ones
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    [defaults setBool:YES forKey:SyntaxColoringEnabledKey];
    [defaults setBool:YES forKey:expl3SyntaxColoringKey];

    TSMacroEditor *editor = [TSMacroEditor new];
    NSWindow *host = [[NSWindow alloc] initWithContentRect:NSMakeRect(0,0,400,300) styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:YES];
    host.releasedWhenClosed = NO;
    host.appearance = [NSAppearance appearanceNamed:NSAppearanceNameAqua];
    // The contents, as the editor makes them: TextKit 1, plain text, drawing the Advanced Find highlights.
    contents = [editor makeContentTextViewWithSize:NSMakeSize(400, 300)];
    NSTextStorage *storage = contents.textStorage;
    REQUIRE([contents isKindOfClass:TSTextView.class] && !contents.richText && contents.textContainer.widthTracksTextView);
    REQUIRE([contents.layoutManager conformsToProtocol:@protocol(TSAdvancedFindHighlightDrawing)] ||
            [contents.layoutManager isKindOfClass:TSAdvancedFindLayoutManager.class]);
    contents.allowsUndo = YES;
    host.contentView = contents;
    [host makeFirstResponder:contents];
    [editor setValue:host forKey:@"window"]; [editor setValue:contents forKey:@"contentTextView"];
    [editor applyContentAppearance:nil];
    REQUIRE(editor.contentHighlighter.textView == contents);
    TSSyntaxColorScheme *light = Scheme(liteColors, NO), *dark = Scheme(darkColors, YES);
    NSColor *command = RoleColor(light, TSSyntaxRoleCommand), *marker = RoleColor(light, TSSyntaxRoleMarker);
    REQUIRE(command && marker && !Same(command, marker));

    // A TeX macro, as the source colors it, with its placeholders underlined and its marks.
    contents.string = @"\\begin{#SEL#}#INS# % note\n\\l_tmpa_tl •‹n› #INS# #FILEPATH#";
    Spin();
    REQUIRE(Same(ColorAt(@"\\begin"), command));
    REQUIRE(Same(ColorAt(@"{#SEL#"), RoleColor(light, TSSyntaxRoleBracketCurly)));
    REQUIRE(Same(ColorAt(@"#SEL#"), marker) && [At(@"#SEL#")[NSUnderlineStyleAttributeName] integerValue] == NSUnderlineStyleSingle);
    REQUIRE(Same(ColorAt(@"% note"), RoleColor(light, TSSyntaxRoleComment)));
    REQUIRE(Same(ColorAt(@"\\l_tmpa_tl"), RoleColor(light, TSSyntaxRoleExplVariable)));
    REQUIRE(Same(ColorAt(@"•‹n›"), marker) && At(@"•‹n›")[NSUnderlineStyleAttributeName] == nil);
    NSUInteger second = [contents.string rangeOfString:@"#INS#" options:NSBackwardsSearch].location;
    REQUIRE([[contents.layoutManager temporaryAttributesAtCharacterIndex:second effectiveRange:NULL][NSUnderlineStyleAttributeName] integerValue] == 0);
    REQUIRE(At(@"#FILEPATH#")[NSUnderlineStyleAttributeName] == nil);
    // Only temporary attributes: the text and its stored attributes stay as they were.
    [storage enumerateAttribute:NSForegroundColorAttributeName inRange:NSMakeRange(0, storage.length) options:0 usingBlock:^(id value, NSRange range, BOOL *stop) {
        REQUIRE(value == nil || Same(value, contents.textColor));
    }];

    // An AppleScript macro: its own rules and placeholders, in colors the source already has.
    contents.string = @"--applescript direct\ntell application \"TeXShop\" to set n to 42 -- #SEL#\n#FILEPATH# & «event aevtodoc»";
    Spin();
    REQUIRE(Same(ColorAt(@"--applescript"), RoleColor(light, TSSyntaxRoleComment)));
    REQUIRE(Same(ColorAt(@"tell"), command));
    REQUIRE(Same(ColorAt(@"\"TeXShop\""), RoleColor(light, TSSyntaxRoleXMLValue)));
    REQUIRE(Same(ColorAt(@"42"), RoleColor(light, TSSyntaxRoleXMLSpecial)));
    REQUIRE(Same(ColorAt(@"«event"), RoleColor(light, TSSyntaxRoleXMLSpecial)));
    REQUIRE(Same(ColorAt(@"#FILEPATH#"), marker) && [At(@"#FILEPATH#")[NSUnderlineStyleAttributeName] integerValue] == NSUnderlineStyleSingle);
    REQUIRE(At(@"#SEL#")[NSUnderlineStyleAttributeName] == nil && Same(ColorAt(@"#SEL#"), RoleColor(light, TSSyntaxRoleComment)));
    REQUIRE(Plain(@"application"));

    // Typing is colored once the edit is done.
    contents.string = @"\\emph{x}";
    Spin();
    [contents setSelectedRange:NSMakeRange(contents.string.length, 0)];
    [contents insertText:@" \\textbf" replacementRange:NSMakeRange(NSNotFound, 0)];
    Spin();
    REQUIRE(Same(ColorAt(@"\\textbf"), command));
    // Undo, and the text is colored as it is again.
    [contents.undoManager undo];
    Spin();
    REQUIRE([contents.string isEqual:@"\\emph{x}"] && Same(ColorAt(@"\\emph"), command));

    // Composed text waits: nothing is colored until it is committed.
    [contents setSelectedRange:NSMakeRange(contents.string.length, 0)];
    [contents setMarkedText:@"\\sect" selectedRange:NSMakeRange(5, 0) replacementRange:NSMakeRange(NSNotFound, 0)];
    Spin();
    REQUIRE(contents.hasMarkedText && Plain(@"\\sect"));
    [contents setMarkedText:@"\\section" selectedRange:NSMakeRange(8, 0) replacementRange:NSMakeRange(NSNotFound, 0)];
    Spin();
    REQUIRE(Plain(@"\\section"));
    [contents insertText:@"\\section" replacementRange:NSMakeRange(NSNotFound, 0)];
    Spin();
    REQUIRE(!contents.hasMarkedText && Same(ColorAt(@"\\section"), command));
    // Removing composed text without committing it colors what waited too.
    [contents setMarkedText:@"\\x" selectedRange:NSMakeRange(2, 0) replacementRange:NSMakeRange(NSNotFound, 0)];
    Spin();
    [contents.layoutManager removeTemporaryAttribute:NSForegroundColorAttributeName forCharacterRange:NSMakeRange(0, 5)];
    [contents unmarkText];
    Spin();
    REQUIRE(Same(ColorAt(@"\\emph"), command));

    // Colors of other features stay when the contents are colored again.
    NSColor *find = NSColor.systemPinkColor;
    NSRange x = [contents.string rangeOfString:@"x"];
    [contents.layoutManager addTemporaryAttributes:@{NSBackgroundColorAttributeName: NSColor.cyanColor, NSForegroundColorAttributeName: find} forCharacterRange:x];
    [editor.contentHighlighter highlightWholeText];
    REQUIRE([contents.layoutManager temporaryAttributesAtCharacterIndex:x.location effectiveRange:NULL][NSBackgroundColorAttributeName] == NSColor.cyanColor);
    REQUIRE([contents.layoutManager temporaryAttributesAtCharacterIndex:x.location effectiveRange:NULL][NSForegroundColorAttributeName] == find);
    [contents.layoutManager removeTemporaryAttribute:NSBackgroundColorAttributeName forCharacterRange:x];
    [contents.layoutManager removeTemporaryAttribute:NSForegroundColorAttributeName forCharacterRange:x];
    // ... even when another feature uses the very color object of a role, on plain text or as the background of a
    // token. (A foreground of another feature over a token is colored over again, as the source does.)
    NSColor *same = [editor.contentHighlighter.scheme attributesForRole:TSSyntaxRoleCommand][NSForegroundColorAttributeName];
    REQUIRE(same && Same(same, command));
    contents.string = @"\\foo ordinary \\bar";
    Spin();
    NSRange ordinary = [contents.string rangeOfString:@"ordinary"], bar = [contents.string rangeOfString:@"\\bar"];
    [contents.layoutManager addTemporaryAttributes:@{NSForegroundColorAttributeName: same, NSBackgroundColorAttributeName: same} forCharacterRange:ordinary];
    [contents.layoutManager addTemporaryAttributes:@{NSBackgroundColorAttributeName: same} forCharacterRange:bar];
    [editor.contentHighlighter highlightWholeText];
    NSDictionary *kept = [contents.layoutManager temporaryAttributesAtCharacterIndex:ordinary.location effectiveRange:NULL];
    REQUIRE(kept[NSForegroundColorAttributeName] == same && kept[NSBackgroundColorAttributeName] == same);
    REQUIRE([contents.layoutManager temporaryAttributesAtCharacterIndex:bar.location effectiveRange:NULL][NSBackgroundColorAttributeName] == same);
    REQUIRE(Same(ColorAt(@"\\foo"), command));
    [contents.layoutManager removeTemporaryAttribute:NSBackgroundColorAttributeName forCharacterRange:NSMakeRange(0, contents.string.length)];
    [contents.layoutManager removeTemporaryAttribute:NSForegroundColorAttributeName forCharacterRange:NSMakeRange(0, contents.string.length)];
    contents.string = @"\\emph{x}";
    Spin();

    // The highlights of the Advanced Find panel are drawn over the syntax colors, and go without a trace.
    contents.string = @"\\section{alpha} plain % comment #SEL#";
    Spin();
    [host.contentView layoutSubtreeIfNeeded];
    NSData *(^render)(void) = ^NSData *{
        [contents.layoutManager ensureLayoutForTextContainer:contents.textContainer];
        NSBitmapImageRep *image = [contents bitmapImageRepForCachingDisplayInRect:contents.bounds];
        [contents cacheDisplayInRect:contents.bounds toBitmapImageRep:image];
        return [NSData dataWithBytes:image.bitmapData length:image.bytesPerRow * image.pixelsHigh];
    };
    NSData *plainImage = render();
    TSAdvancedFindHighlights *highlights = [TSAdvancedFindHighlights highlightsForTextStorage:storage];
    highlights.ranges = @[[NSValue valueWithRange:[contents.string rangeOfString:@"alpha"]], [NSValue valueWithRange:[contents.string rangeOfString:@"#SEL#"]]];
    [contents setNeedsDisplay:YES];
    NSData *foundImage = render();
    REQUIRE(![foundImage isEqual:plainImage]);
    REQUIRE(Same(ColorAt(@"\\section"), command) && [At(@"#SEL#")[NSUnderlineStyleAttributeName] integerValue] == NSUnderlineStyleSingle);
    [highlights removeAll];
    [contents setNeedsDisplay:YES];
    REQUIRE([render() isEqual:plainImage]);
    contents.string = @"\\emph{x}";
    Spin();

    // A dark window takes the dark theme.
    host.appearance = [NSAppearance appearanceNamed:NSAppearanceNameDarkAqua];
    [editor applyContentAppearance:nil];
    Spin();
    REQUIRE(!Same(RoleColor(dark, TSSyntaxRoleCommand), command) && Same(ColorAt(@"\\emph"), RoleColor(dark, TSSyntaxRoleCommand)));

    // Syntax Color off in Settings leaves the contents plain; on again, they are colored.
    [defaults setBool:NO forKey:SyntaxColoringEnabledKey];
    [[NSNotificationCenter defaultCenter] postNotificationName:DocumentSyntaxColorNotification object:nil];
    [editor applyContentAppearance:nil];
    Spin();
    REQUIRE(editor.contentHighlighter == nil && Plain(@"\\emph"));
    contents.string = @"\\emph{y}";
    Spin();
    REQUIRE(Plain(@"\\emph"));
    [defaults setBool:YES forKey:SyntaxColoringEnabledKey];
    [editor applyContentAppearance:nil];
    Spin();
    REQUIRE(Same(ColorAt(@"\\emph"), RoleColor(dark, TSSyntaxRoleCommand)));

    // expl3 off in Settings: an expl3 variable is an ordinary command.
    contents.string = @"\\l_tmpa_tl";
    [defaults setBool:NO forKey:expl3SyntaxColoringKey];
    [editor applyContentAppearance:nil];
    Spin();
    REQUIRE(Same(ColorAt(@"\\l"), RoleColor(dark, TSSyntaxRoleCommand)) && Plain(@"_tmpa"));
    puts("PASS: macro contents are colored as the source, follow edits, composing, appearance and Settings, and keep other colors");
} return 0; }
