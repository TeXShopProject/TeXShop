// SPDX-License-Identifier: GPL-2.0-or-later
// Copy with Style: the selection of a source with the font and the colors of a theme, as RTF and HTML beside the
// plain text. The colors are found again by the scanner of syntax coloring, not read from the view, so that text
// out of sight and the theme of the other mode get them too. Only what the theme gives the text is copied: the
// text color, the syntax colors and the fullwidth highlight, and the theme's background when it is asked for; never
// the active line, the brace and find highlights or the selection.
#import <AppKit/AppKit.h>
#import <objc/runtime.h>
#import "TSSyntaxScanner.h"
#import "TSSyntaxColorScheme.h"

NS_ASSUME_NONNULL_BEGIN

/// The selected ranges of text (empty ones are left out), each with the fonts and paragraph styles it has there,
/// the color textColor, the attributes that scheme gives the tokens of scanner, and backgroundColor under all of it
/// when it is not nil; joined by line feeds. Colors are given in sRGB as they look in appearance. nil when no range
/// has text. Without a scanner or a scheme the text only has textColor (syntax coloring is off). Every color is made
/// opaque: one that is partly transparent (a fullwidth background may be) is blended onto backgroundColor, or onto
/// white without it.
NSAttributedString *_Nullable TSStyledCopyString(NSAttributedString *text, NSArray<NSValue *> *ranges,
                                                 id<TSSyntaxScanner> _Nullable scanner, TSSyntaxColorScheme *_Nullable scheme,
                                                 NSColor *textColor, NSColor *_Nullable backgroundColor,
                                                 NSAppearance *appearance);

/// The four commands of Copy with Style: -copyWithLightTheme:, -copyWithLightThemeAndBackground:,
/// -copyWithDarkTheme: and -copyWithDarkThemeAndBackground:. YES for one of them, with its theme and background.
/// Inline, so that the views that validate the commands need nothing else of Copy with Style.
static inline BOOL TSStyledCopyAction(SEL _Nullable action, BOOL *_Nullable dark, BOOL *_Nullable withBackground)
{
    static const struct { const char *name; BOOL dark, background; } commands[] = {
        {"copyWithLightTheme:", NO, NO}, {"copyWithLightThemeAndBackground:", NO, YES},
        {"copyWithDarkTheme:", YES, NO}, {"copyWithDarkThemeAndBackground:", YES, YES},
    };
    if (!action)
        return NO;
    SEL given = (SEL _Nonnull)action;
    for (size_t i = 0; i < sizeof(commands) / sizeof(commands[0]); i++)
        if (sel_isEqual(given, sel_registerName(commands[i].name))) {
            if (dark)
                *dark = commands[i].dark;
            if (withBackground)
                *withBackground = commands[i].background;
            return YES;
        }
    return NO;
}

/// Whether the commands can copy from view: it is where typing goes (the first responder of the key window), and
/// some text is selected. A source behind a find field or another panel is not copied from.
static inline BOOL TSStyledCopyCanCopy(NSTextView *view)
{
    NSWindow *window = view.window;
    if (!window.isKeyWindow || window.firstResponder != view)
        return NO;
    for (NSValue *range in view.selectedRanges)
        if (range.rangeValue.length > 0)
            return YES;
    return NO;
}

/// The string as an HTML document: a block for each paragraph, with the tab width, indents and line spacing of the
/// source, and in it spans with sRGB colors, the face and its size in points, and the background behind the
/// characters only.
NSString *TSStyledCopyHTML(NSAttributedString *styled);

/// Puts the string on the pasteboard as RTF, HTML and plain text. NO when it could not be written.
BOOL TSStyledCopyWriteToPasteboard(NSAttributedString *styled, NSPasteboard *pasteboard);

NS_ASSUME_NONNULL_END
