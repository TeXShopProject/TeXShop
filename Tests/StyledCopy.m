// Copy with Style: the RTF, HTML and text that the four commands put on a pasteboard, made by the production code
// (TSStyledCopy, the TeX scanner and TSSyntaxColorScheme, and -[TSDocument copyStyledSelectionOfTextView:...] on a
// stand-in document) with the bundled Lite and Dark themes. The general pasteboard is never written: the document's
// method is compiled with a private pasteboard in its place. No window is shown.
#import <AppKit/AppKit.h>
#import <WebKit/WebKit.h>
#import "TSStyledCopy.h"
#import "TSSyntaxTeXScanner.h"
#import "TSColorSupport.h"

static int failures;
static void Require(NSString *label, BOOL ok)
{
    if (!ok) {
        failures++;
        fprintf(stderr, "FAIL: %s\n", label.UTF8String);
    }
}

static NSPasteboard *TestPasteboard;
@interface NSPasteboard (StyledCopyTest)
+ (NSPasteboard *)styledCopyTestPasteboard;
@end
@implementation NSPasteboard (StyledCopyTest)
+ (NSPasteboard *)styledCopyTestPasteboard { return TestPasteboard; }
@end

// The theme colors TSColorSupport gives: the color the theme has, or black text on white (white on black in Dark).
@implementation TSColorSupport
+ (instancetype)sharedInstance
{
    static TSColorSupport *shared;
    if (!shared)
        shared = [TSColorSupport new];
    return shared;
}
- (NSColor *)colorFromDictionary:(NSDictionary *)theme andKey:(NSString *)key
{
    NSArray *a = theme[key];
    if (a.count < 3 && [key hasPrefix:@"SyntaxMarker"])
        a = theme[@"SyntaxMarker"];
    return a.count >= 3 ? [NSColor colorWithRed:[a[0] doubleValue] green:[a[1] doubleValue] blue:[a[2] doubleValue] alpha:1] : nil;
}
- (NSColor *)colorAndAlphaFromDictionary:(NSDictionary *)theme andKey:(NSString *)key
{
    NSArray *a = theme[key];
    return a.count >= 3 ? [NSColor colorWithRed:[a[0] doubleValue] green:[a[1] doubleValue] blue:[a[2] doubleValue]
                                           alpha:a.count >= 4 ? [a[3] doubleValue] : 1] : nil;
}
- (NSColor *)liteColorAndAlphaWithKey:(NSString *)key { return nil; }
- (NSColor *)darkColorAndAlphaWithKey:(NSString *)key { return nil; }
- (NSColor *)opaqueColorForKey:(NSString *)key fromDictionary:(NSDictionary *)theme isWindowDark:(BOOL)dark
{
    NSColor *color = [self colorFromDictionary:theme andKey:key];
    if (color)
        return color;
    BOOL text = ![key containsString:@"Background"];
    return (text != dark) ? NSColor.blackColor : NSColor.whiteColor;
}
@end

NSDictionary *liteColors, *darkColors;

@interface KeyWindow : NSWindow
@property BOOL key;
@end
@implementation KeyWindow
- (BOOL)isKeyWindow { return self.key; }
@end

// A stand-in document with what the production method uses.
@interface TSDocument : NSObject {
@public
    BOOL fileIsTex;
}
@property BOOL syntaxColor;
@property BOOL marksFullwidth;
@property BOOL xml;
@end
@implementation TSDocument
- (TSMutableSyntaxTeXOptions *)sourceScannerOptionsWithScheme:(TSSyntaxColorScheme *)scheme
{
    TSMutableSyntaxTeXOptions *options = [TSMutableSyntaxTeXOptions new];
    options.texCharacter = '\\';
    options.colorsFootnote = YES;
    options.isXML = self.xml;
    options.marksFullwidthSymbols = self.marksFullwidth && [scheme attributesForRole:TSSyntaxRoleFullwidthSymbol].count > 0;
    return options;
}
#define generalPasteboard styledCopyTestPasteboard
#include "StyledCopyDocumentMethod.inc"
#undef generalPasteboard
@end

#pragma mark Reading back

static NSAttributedString *ReadRTF(NSPasteboard *pasteboard)
{
    NSData *rtf = [pasteboard dataForType:NSPasteboardTypeRTF];
    return rtf ? [[NSAttributedString alloc] initWithRTF:rtf documentAttributes:NULL] : nil;
}

static NSColor *SRGB(NSColor *color) { return [color colorUsingColorSpace:NSColorSpace.sRGBColorSpace]; }

static BOOL SameColor(NSColor *a, NSColor *b)
{
    if (!a || !b)
        return a == b;
    a = SRGB(a); b = SRGB(b);
    return fabs(a.redComponent - b.redComponent) < 0.004 && fabs(a.greenComponent - b.greenComponent) < 0.004 &&
           fabs(a.blueComponent - b.blueComponent) < 0.004 && fabs(a.alphaComponent - b.alphaComponent) < 0.004;
}

static NSColor *ThemeColor(NSDictionary *theme, NSString *key)
{
    return [[TSColorSupport sharedInstance] colorFromDictionary:theme andKey:key];
}

static id ColorAt(NSAttributedString *string, NSString *substring, NSAttributedStringKey key)
{
    NSRange range = [string.string rangeOfString:substring];
    if (range.location == NSNotFound)
        return nil;
    return [string attribute:key atIndex:range.location effectiveRange:NULL];
}

static NSDictionary *Theme(NSString *path)
{
    NSDictionary *theme = [NSDictionary dictionaryWithContentsOfFile:path];
    Require([@"theme " stringByAppendingString:path], theme.count > 0);
    return theme;
}

#pragma mark Checks

static NSTextView *SourceView(NSString *text, NSFont *font)
{
    NSTextView *view = [[NSTextView alloc] initWithFrame:NSMakeRect(0, 0, 400, 30)];
    view.richText = NO;
    view.string = text;
    [view.textStorage addAttribute:NSFontAttributeName value:font range:NSMakeRange(0, text.length)];
    NSMutableParagraphStyle *style = [NSMutableParagraphStyle new];
    style.defaultTabInterval = 37;
    style.tabStops = @[];
    [view.textStorage addAttribute:NSParagraphStyleAttributeName value:style range:NSMakeRange(0, text.length)];
    return view;
}

static void CheckDocumentCommands(NSString *themes)
{
    liteColors = Theme([themes stringByAppendingPathComponent:@"LiteTheme.plist"]);
    darkColors = Theme([themes stringByAppendingPathComponent:@"DarkTheme.plist"]);
    // Every color of the check is a distinct theme color, so that a wrong theme or role is seen.
    NSString *text = @"before \\section{Intro} % note\nplain text\nlast line";
    NSFont *font = [NSFont fontWithName:@"Menlo-Regular" size:15] ?: [NSFont userFixedPitchFontOfSize:15];
    NSTextView *view = SourceView(text, font);
    // The selection starts inside \section: the command still has its color (whole lines are scanned).
    NSRange selection = NSMakeRange([text rangeOfString:@"ection"].location, [text rangeOfString:@"plain"].location + 5 - [text rangeOfString:@"ection"].location);
    view.selectedRange = selection;
    TSDocument *document = [TSDocument new];
    document->fileIsTex = YES;
    document.syntaxColor = YES;

    struct { SEL action; BOOL dark, background; } commands[] = {
        {@selector(copyWithLightTheme:), NO, NO}, {@selector(copyWithLightThemeAndBackground:), NO, YES},
        {@selector(copyWithDarkTheme:), YES, NO}, {@selector(copyWithDarkThemeAndBackground:), YES, YES},
    };
    for (int i = 0; i < 4; i++) {
        BOOL dark = !commands[i].dark, background = !commands[i].background;
        NSString *name = NSStringFromSelector(commands[i].action);
        Require([name stringByAppendingString:@" is a command"], TSStyledCopyAction(commands[i].action, &dark, &background));
        Require([name stringByAppendingString:@" theme and background"], dark == commands[i].dark && background == commands[i].background);
        [TestPasteboard clearContents];
        Require([name stringByAppendingString:@" copies"], [document copyStyledSelectionOfTextView:view darkTheme:dark withBackground:background]);
        NSDictionary *theme = dark ? darkColors : liteColors;
        NSAttributedString *rtf = ReadRTF(TestPasteboard);
        NSString *expected = [text substringWithRange:selection];
        Require([name stringByAppendingString:@": RTF text"], [rtf.string isEqualToString:expected]);
        Require([name stringByAppendingString:@": plain text"], [[TestPasteboard stringForType:NSPasteboardTypeString] isEqualToString:expected]);
        Require([name stringByAppendingString:@": HTML"], [[[NSString alloc] initWithData:[TestPasteboard dataForType:NSPasteboardTypeHTML] encoding:NSUTF8StringEncoding] containsString:@"Intro"]);
        Require([name stringByAppendingString:@": command color"], SameColor(ColorAt(rtf, @"ection", NSForegroundColorAttributeName), ThemeColor(theme, @"SyntaxCommand")));
        Require([name stringByAppendingString:@": comment color"], SameColor(ColorAt(rtf, @"% note", NSForegroundColorAttributeName), ThemeColor(theme, @"SyntaxComment")));
        Require([name stringByAppendingString:@": brace color"], SameColor(ColorAt(rtf, @"{", NSForegroundColorAttributeName), ThemeColor(theme, @"SyntaxMarkerCurly")));
        Require([name stringByAppendingString:@": text color"], SameColor(ColorAt(rtf, @"plain", NSForegroundColorAttributeName), ThemeColor(theme, @"EditorText")));
        NSColor *paper = background ? ThemeColor(theme, @"EditorBackground") : nil;
        Require([name stringByAppendingString:@": background of text"], SameColor(ColorAt(rtf, @"plain", NSBackgroundColorAttributeName), paper));
        Require([name stringByAppendingString:@": background of command"], SameColor(ColorAt(rtf, @"ection", NSBackgroundColorAttributeName), paper));
        NSFont *copied = ColorAt(rtf, @"plain", NSFontAttributeName);
        Require([name stringByAppendingString:@": font"], [copied.fontName isEqualToString:font.fontName] && copied.pointSize == 15);
    }
    // The light theme differs from the dark one in these colors, or the checks above prove nothing.
    Require(@"themes differ", !SameColor(ThemeColor(liteColors, @"EditorText"), ThemeColor(darkColors, @"EditorText")) &&
            !SameColor(ThemeColor(liteColors, @"SyntaxComment"), ThemeColor(darkColors, @"SyntaxComment")));

    // Coloring off (or not TeX): the text color only.
    document.syntaxColor = NO;
    [TestPasteboard clearContents];
    [document copyStyledSelectionOfTextView:view darkTheme:NO withBackground:NO];
    Require(@"coloring off: no command color", SameColor(ColorAt(ReadRTF(TestPasteboard), @"ection", NSForegroundColorAttributeName), ThemeColor(liteColors, @"EditorText")));
    document.syntaxColor = YES;
    document->fileIsTex = NO;
    [TestPasteboard clearContents];
    [document copyStyledSelectionOfTextView:view darkTheme:NO withBackground:NO];
    Require(@"not TeX: no comment color", SameColor(ColorAt(ReadRTF(TestPasteboard), @"% note", NSForegroundColorAttributeName), ThemeColor(liteColors, @"EditorText")));
    document->fileIsTex = YES;

    // Nothing selected: nothing is copied, and the pasteboard keeps what it had.
    view.selectedRange = NSMakeRange(3, 0);
    [TestPasteboard clearContents];
    [TestPasteboard setString:@"kept" forType:NSPasteboardTypeString];
    Require(@"empty selection is refused", ![document copyStyledSelectionOfTextView:view darkTheme:NO withBackground:NO]);
    Require(@"empty selection keeps the pasteboard", [[TestPasteboard stringForType:NSPasteboardTypeString] isEqualToString:@"kept"]);
    // The commands copy only from where typing goes: the first responder of the key window (a window that says it
    // is key; none is shown). A source behind a find field, or in a window that is not key, is not copied from.
    KeyWindow *window = [[KeyWindow alloc] initWithContentRect:NSMakeRect(0, 0, 400, 100) styleMask:NSWindowStyleMaskTitled
                                                       backing:NSBackingStoreBuffered defer:YES];
    NSTextView *field = [[NSTextView alloc] initWithFrame:NSMakeRect(0, 50, 400, 20)];
    [window.contentView addSubview:view];
    [window.contentView addSubview:field];
    view.selectedRange = NSMakeRange(0, 5);
    window.key = YES;
    [window makeFirstResponder:view];
    Require(@"key window, first responder, selection: enabled", TSStyledCopyCanCopy(view));
    view.selectedRange = NSMakeRange(3, 0);
    Require(@"no selection: disabled", !TSStyledCopyCanCopy(view));
    view.selectedRange = NSMakeRange(0, 5);
    [window makeFirstResponder:field];
    Require(@"a find field in front: disabled", !TSStyledCopyCanCopy(view));
    [window makeFirstResponder:view];
    window.key = NO;
    Require(@"not the key window: disabled", !TSStyledCopyCanCopy(view));
    [view removeFromSuperview];
    Require(@"other commands are not Copy with Style", !TSStyledCopyAction(@selector(copy:), NULL, NULL) && !TSStyledCopyAction(NULL, NULL, NULL));

    // Several selected ranges are joined by line feeds, each with its own colors.
    NSRange first = [text rangeOfString:@"\\section"], second = [text rangeOfString:@"last"];
    view.selectedRanges = @[[NSValue valueWithRange:first], [NSValue valueWithRange:second]];
    [TestPasteboard clearContents];
    [document copyStyledSelectionOfTextView:view darkTheme:YES withBackground:YES];
    NSAttributedString *joined = ReadRTF(TestPasteboard);
    Require(@"ranges joined", [joined.string isEqualToString:@"\\section\nlast"]);
    Require(@"joined: command color", SameColor(ColorAt(joined, @"\\section", NSForegroundColorAttributeName), ThemeColor(darkColors, @"SyntaxCommand")));
    Require(@"joined: text color", SameColor(ColorAt(joined, @"last", NSForegroundColorAttributeName), ThemeColor(darkColors, @"EditorText")));
    Require(@"joined: line feed background", SameColor([joined attribute:NSBackgroundColorAttributeName atIndex:8 effectiveRange:NULL], ThemeColor(darkColors, @"EditorBackground")));

    // A construct over several lines keeps its color when only a later line of it is selected: the whole text is
    // scanned, not the selected lines.
    NSColor *footnote = ThemeColor(darkColors, @"FootnoteColor") ?: ThemeColor(darkColors, @"SyntaxCommand");
    NSTextView *note = SourceView(@"text \\footnote{first line\nsecond line\nthird} after", font);
    note.selectedRange = [note.string rangeOfString:@"second"];
    [TestPasteboard clearContents];
    [document copyStyledSelectionOfTextView:note darkTheme:YES withBackground:NO];
    Require(@"middle line of a footnote", SameColor(ColorAt(ReadRTF(TestPasteboard), @"second", NSForegroundColorAttributeName), footnote));
    Require(@"footnote differs from text", !SameColor(footnote, ThemeColor(darkColors, @"EditorText")));
    document.xml = YES;
    NSTextView *comment = SourceView(@"<a>\n<!-- one\ntwo\nthree -->\n<b/>", font);
    comment.selectedRanges = @[[NSValue valueWithRange:[comment.string rangeOfString:@"two"]], [NSValue valueWithRange:[comment.string rangeOfString:@"<b/>"]]];
    [TestPasteboard clearContents];
    [document copyStyledSelectionOfTextView:comment darkTheme:NO withBackground:NO];
    Require(@"middle line of an XML comment", SameColor(ColorAt(ReadRTF(TestPasteboard), @"two", NSForegroundColorAttributeName), ThemeColor(liteColors, @"XMLComment")));
    document.xml = NO;

    // The HTML has the colors in sRGB, the size in points, the tab width of the source and the background behind
    // the characters only, as WebKit reads it back.
    NSMutableDictionary *gray = [darkColors mutableCopy];
    gray[@"EditorBackground"] = @[@0.2, @0.2, @0.2, @1];
    NSDictionary *savedDark = darkColors;
    darkColors = gray;
    view.selectedRange = selection;
    [view.window makeFirstResponder:view];
    [TestPasteboard clearContents];
    [document copyStyledSelectionOfTextView:view darkTheme:YES withBackground:YES];
    NSString *html = [[NSString alloc] initWithData:[TestPasteboard dataForType:NSPasteboardTypeHTML] encoding:NSUTF8StringEncoding];
    Require(@"HTML size in points", [html containsString:@"font-size:15pt"]);
    Require(@"HTML tab width", [html containsString:@"tab-size:37pt"]);
    Require(@"HTML background #333333", [html containsString:@"background-color:#333333"] && ![html containsString:@"background-color:#262626"]);
    Require(@"HTML background on spans only", ![[html substringToIndex:[html rangeOfString:@"<span"].location] containsString:@"background"]);
    NSAttributedString *read = [[NSAttributedString alloc] initWithData:[html dataUsingEncoding:NSUTF8StringEncoding]
        options:@{NSDocumentTypeDocumentOption: NSHTMLTextDocumentType, NSCharacterEncodingDocumentOption: @(NSUTF8StringEncoding)} documentAttributes:NULL error:NULL];
    Require(@"HTML text", [read.string containsString:@"ection{Intro}"]);
    Require(@"HTML command color", SameColor(ColorAt(read, @"ection", NSForegroundColorAttributeName), ThemeColor(darkColors, @"SyntaxCommand")));
    Require(@"HTML background read back", SameColor(ColorAt(read, @"plain", NSBackgroundColorAttributeName), [NSColor colorWithSRGBRed:0.2 green:0.2 blue:0.2 alpha:1]));
    // AppKit's HTML reader counts a CSS pixel as a point, so 15pt (20 CSS pixels) comes back as 20; AppKit's own HTML
    // said 15px, which browsers and word processors show as 11.25pt.
    Require(@"HTML font size read back", fabs(((NSFont *)ColorAt(read, @"plain", NSFontAttributeName)).pointSize - 20) < 0.01);
    Require(@"HTML escapes", [TSStyledCopyHTML([[NSAttributedString alloc] initWithString:@"a<b&c"]) containsString:@"a&lt;b&amp;c"]);
    // A selection that ends with its line break keeps it in the HTML; a break inside, an empty line and a selection
    // of the break alone are kept too.
    NSDictionary *plainText = @{NSFontAttributeName: font};
    // Read as a browser shows it: the text of the page in a WKWebView that is never put in a window. (AppKit's own
    // HTML reader adds a line break at the end of everything.)
    NSString *(^Read)(NSString *) = ^NSString *(NSString *text) {
        NSString *written = TSStyledCopyHTML([[NSAttributedString alloc] initWithString:text attributes:plainText]);
        WKWebView *web = [[WKWebView alloc] initWithFrame:NSMakeRect(0, 0, 400, 300)];
        __block NSString *shown = nil;
        [web loadHTMLString:written baseURL:nil];
        NSDate *limit = [NSDate dateWithTimeIntervalSinceNow:10];
        while (web.isLoading && limit.timeIntervalSinceNow > 0)
            [NSRunLoop.currentRunLoop runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
        [web evaluateJavaScript:@"document.body.innerText" completionHandler:^(id value, NSError *error) { shown = value ?: @"(error)"; }];
        while (!shown && limit.timeIntervalSinceNow > 0)
            [NSRunLoop.currentRunLoop runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
        return shown ?: @"(timeout)";
    };
    Require(@"HTML final line break kept", ![TSStyledCopyHTML([[NSAttributedString alloc] initWithString:@"abc" attributes:plainText])
                                               isEqualToString:TSStyledCopyHTML([[NSAttributedString alloc] initWithString:@"abc\n" attributes:plainText])]);
    Require(@"HTML without a final line break", [Read(@"abc") isEqualToString:@"abc"]);
    Require(@"HTML final line break read back", [Read(@"abc\n") isEqualToString:@"abc\n"]);
    Require(@"HTML line breaks inside", [Read(@"a\n\nb") isEqualToString:@"a\n\nb"]);
    Require(@"HTML a line break alone", [Read(@"\n") isEqualToString:@"\n"]);

    // Each paragraph keeps the indents and the line spacing of the source; the default layout adds none.
    NSMutableParagraphStyle *indented = [NSMutableParagraphStyle new];
    indented.headIndent = 11;
    indented.firstLineHeadIndent = 5;
    indented.lineSpacing = 3;
    indented.defaultTabInterval = 37;
    NSFont *menlo = [NSFont fontWithName:@"Menlo-Regular" size:15] ?: [NSFont userFixedPitchFontOfSize:15];
    NSAttributedString *layout = [[NSAttributedString alloc] initWithString:@"one\n\ttwo" attributes:@{NSFontAttributeName: menlo, NSParagraphStyleAttributeName: indented}];
    NSString *indentedHTML = TSStyledCopyHTML(layout);
    CGFloat lineHeight = [[NSLayoutManager new] defaultLineHeightForFont:menlo] + 3;
    Require(@"HTML indent of wrapped lines", [indentedHTML containsString:@"padding-left:11pt;"]);
    Require(@"HTML indent of the first line", [indentedHTML containsString:@"text-indent:-6pt;"]);
    Require(@"HTML line spacing", [indentedHTML containsString:[NSString stringWithFormat:@"line-height:%gpt;", lineHeight]]);
    Require(@"HTML one block per paragraph", [indentedHTML componentsSeparatedByString:@"<div "].count == 3);
    NSMutableParagraphStyle *plain = [NSMutableParagraphStyle new];
    plain.defaultTabInterval = 37;
    NSString *plainHTML = TSStyledCopyHTML([[NSAttributedString alloc] initWithString:@"one\n\ttwo" attributes:@{NSFontAttributeName: menlo, NSParagraphStyleAttributeName: plain}]);
    Require(@"HTML default layout", ![plainHTML isEqualToString:indentedHTML] && ![plainHTML containsString:@"padding-left"] &&
            ![plainHTML containsString:@"text-indent"] && ![plainHTML containsString:@"line-height"]);
    // A light face keeps its weight and its name.
    NSFont *light = [NSFont fontWithName:@"HelveticaNeue-Light" size:15], *regular = [NSFont fontWithName:@"HelveticaNeue" size:15];
    if (light && regular) {
        NSString *lightHTML = TSStyledCopyHTML([[NSAttributedString alloc] initWithString:@"x" attributes:@{NSFontAttributeName: light}]);
        NSString *regularHTML = TSStyledCopyHTML([[NSAttributedString alloc] initWithString:@"x" attributes:@{NSFontAttributeName: regular}]);
        Require(@"HTML light face", [lightHTML containsString:@"'HelveticaNeue-Light'"] && [lightHTML containsString:@"font-weight:300;"]);
        Require(@"HTML regular face", [regularHTML containsString:@"font-weight:400;"] && ![lightHTML isEqualToString:regularHTML]);
    } else
        Require(@"Helvetica Neue Light and Regular are installed", NO);
    darkColors = savedDark;

    // Fullwidth letters keep the theme's fullwidth colors in every command; a translucent background is blended
    // onto the paper: the theme's background, or white.
    NSMutableDictionary *translucent = [liteColors mutableCopy];
    translucent[@"EditorHighlightZenkakuSymbol"] = @[@0.2, @0.4, @0.6, @1];
    translucent[@"EditorHighlightZenkakuSymbolBackground"] = @[@1, @0, @0, @0.5];
    translucent[@"EditorBackground"] = @[@0, @0, @1, @1];
    liteColors = translucent;
    document.marksFullwidth = YES;
    NSTextView *fullwidth = SourceView(@"ａｂ ab", font);
    fullwidth.selectedRange = NSMakeRange(0, 5);
    [TestPasteboard clearContents];
    [document copyStyledSelectionOfTextView:fullwidth darkTheme:NO withBackground:NO];
    NSAttributedString *onWhite = ReadRTF(TestPasteboard);
    Require(@"fullwidth color", SameColor(ColorAt(onWhite, @"ａ", NSForegroundColorAttributeName), [NSColor colorWithRed:0.2 green:0.4 blue:0.6 alpha:1]));
    Require(@"fullwidth background on white", SameColor(ColorAt(onWhite, @"ａ", NSBackgroundColorAttributeName), [NSColor colorWithRed:1 green:0.5 blue:0.5 alpha:1]));
    Require(@"no background beside fullwidth", ColorAt(onWhite, @"ab", NSBackgroundColorAttributeName) == nil);
    [TestPasteboard clearContents];
    [document copyStyledSelectionOfTextView:fullwidth darkTheme:NO withBackground:YES];
    NSAttributedString *onTheme = ReadRTF(TestPasteboard);
    Require(@"fullwidth background on the theme's", SameColor(ColorAt(onTheme, @"ａ", NSBackgroundColorAttributeName), [NSColor colorWithRed:0.5 green:0 blue:0.5 alpha:1]));
    Require(@"theme background beside fullwidth", SameColor(ColorAt(onTheme, @"ab", NSBackgroundColorAttributeName), [NSColor colorWithRed:0 green:0 blue:1 alpha:1]));
}

// The four commands come right after Copy in the Edit menu of every compiled menu, without key equivalents.
static void CheckMenu(NSString *path)
{
    NSNib *nib = [[NSNib alloc] initWithNibData:[NSData dataWithContentsOfFile:path] bundle:nil];
    NSArray *objects = nil;
    if (![nib instantiateWithOwner:NSApp topLevelObjects:&objects]) {
        Require(path, NO);
        return;
    }
    NSMenu *menu = nil;
    for (id object in objects)
        if ([object isKindOfClass:NSMenu.class] && [object itemArray].count > 5)
            menu = object;
    NSMenuItem *copy = nil;
    for (NSMenuItem *top in menu.itemArray)
        for (NSMenuItem *item in top.submenu.itemArray)
            if (item.action == @selector(copy:))
                copy = item;
    NSMenu *edit = copy.menu;
    NSInteger index = [edit indexOfItem:copy];
    NSMenuItem *parent = index >= 0 && index + 1 < edit.numberOfItems ? [edit itemAtIndex:index + 1] : nil;
    Require([path stringByAppendingString:@": Copy with Style after Copy"], parent.submenu.numberOfItems == 4 && parent.title.length > 0 && parent.keyEquivalent.length == 0);
    Require([path stringByAppendingString:@": Paste after Copy with Style"], [edit itemAtIndex:index + 2].action == @selector(paste:));
    SEL actions[] = {@selector(copyWithLightTheme:), @selector(copyWithLightThemeAndBackground:), @selector(copyWithDarkTheme:), @selector(copyWithDarkThemeAndBackground:)};
    NSMutableSet *titles = [NSMutableSet set];
    for (NSInteger i = 0; i < 4 && i < parent.submenu.numberOfItems; i++) {
        NSMenuItem *item = [parent.submenu itemAtIndex:i];
        NSString *label = [NSString stringWithFormat:@"%@: item %ld", path, (long)i];
        Require([label stringByAppendingString:@" action"], item.action == actions[i] && item.target == nil);
        Require([label stringByAppendingString:@" no key"], item.keyEquivalent.length == 0);
        Require([label stringByAppendingString:@" identifier"], [item.identifier isEqualToString:[NSString stringWithFormat:@"TSShortcut.%@.0", NSStringFromSelector(actions[i])]]);
        if (item.title.length)
            [titles addObject:item.title];
    }
    Require([path stringByAppendingString:@": four titles"], titles.count == 4);
}

int main(int argc, const char *argv[])
{
    @autoreleasepool {
        [NSApplication sharedApplication];
        TestPasteboard = [NSPasteboard pasteboardWithUniqueName];
        CheckDocumentCommands([NSString stringWithUTF8String:argv[1]]);
        for (int i = 2; i < argc; i++)
            CheckMenu([NSString stringWithUTF8String:argv[i]]);
        [TestPasteboard releaseGlobally];
        if (failures)
            return 1;
        printf("PASS: Copy with Style, Lite and Dark themes, %d compiled menus\n", argc - 2);
    }
    return 0;
}
