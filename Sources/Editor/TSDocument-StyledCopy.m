// SPDX-License-Identifier: GPL-2.0-or-later
// Edit › Copy with Style for the sources of a document: the source, the parts of a split window and the
// Experiment source. TSStyledCopy makes the RTF and HTML; this finds the theme and the syntax coloring.
#import "TSDocument.h"
#import "globals.h"
#import "TSColorSupport.h"
#import "TSSyntaxColorScheme.h"
#import "TSSyntaxTeXScanner.h"
#import "TSStyledCopy.h"

@implementation TSDocument (StyledCopy)

- (BOOL)copyStyledSelectionOfTextView:(NSTextView *)sourceView darkTheme:(BOOL)dark withBackground:(BOOL)withBackground
{
    NSDictionary *theme = (dark ? darkColors : liteColors) ?: @{};
    TSColorSupport *support = [TSColorSupport sharedInstance];
    NSColor *textColor = [support opaqueColorForKey:@"EditorText" fromDictionary:theme isWindowDark:dark];
    NSColor *backgroundColor = withBackground ? [support opaqueColorForKey:@"EditorBackground" fromDictionary:theme isWindowDark:dark] : nil;
    // The syntax colors of the source, as it would show them in that mode: none when coloring is off.
    TSSyntaxColorScheme *scheme = nil;
    TSSyntaxTeXScanner *texScanner = nil;
    if (fileIsTex && self.syntaxColor) {
        scheme = [[TSSyntaxColorScheme alloc] initWithTheme:theme dark:dark];
        texScanner = [[TSSyntaxTeXScanner alloc] initWithOptions:[self sourceScannerOptionsWithScheme:scheme]];
    }
    NSAppearance *appearance = [NSAppearance appearanceNamed:dark ? NSAppearanceNameDarkAqua : NSAppearanceNameAqua];
    NSTextStorage *storage = sourceView.textStorage;
    if (!storage)
        return NO;
    NSAttributedString *styled = TSStyledCopyString(storage, sourceView.selectedRanges, texScanner, scheme,
                                                    textColor, backgroundColor, appearance);
    if (!styled)
        return NO;
    return TSStyledCopyWriteToPasteboard(styled, [NSPasteboard generalPasteboard]);
}

@end
