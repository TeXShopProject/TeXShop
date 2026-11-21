// SPDX-License-Identifier: GPL-2.0-or-later
#import "TSStyledCopy.h"

// The attributes of the text kept in the copy: everything else (links, glyph info, marks of other features) stays.
static NSArray<NSAttributedStringKey> *TSStyledCopyTextKeys(void)
{
    return @[NSFontAttributeName, NSParagraphStyleAttributeName];
}

// The attributes of the scheme kept in the copy: those that a token can have in the source.
static NSArray<NSAttributedStringKey> *TSStyledCopySchemeKeys(void)
{
    return @[NSForegroundColorAttributeName, NSBackgroundColorAttributeName, NSUnderlineStyleAttributeName,
             NSUnderlineColorAttributeName];
}

// An opaque sRGB color: one that is partly transparent is blended onto paper, as it is drawn on the source's
// background (applications read the opacity of RTF and HTML colors differently, or not at all).
static NSColor *TSStyledCopyColor(NSColor *color, NSColor *paper)
{
    NSColor *srgb = [color colorUsingColorSpace:NSColorSpace.sRGBColorSpace] ?: color;
    CGFloat alpha = srgb.alphaComponent;
    if (alpha >= 1)
        return srgb;
    NSColor *under = [paper colorUsingColorSpace:NSColorSpace.sRGBColorSpace] ?: NSColor.whiteColor;
    return [NSColor colorWithSRGBRed:srgb.redComponent * alpha + under.redComponent * (1 - alpha)
                               green:srgb.greenComponent * alpha + under.greenComponent * (1 - alpha)
                                blue:srgb.blueComponent * alpha + under.blueComponent * (1 - alpha)
                               alpha:1];
}

static NSMutableAttributedString *TSStyledCopyPiece(NSAttributedString *text, NSRange range, id<TSSyntaxScanner> scanner,
                                                    TSSyntaxColorScheme *scheme, NSColor *textColor, NSColor *backgroundColor)
{
    NSString *string = text.string;
    NSMutableAttributedString *piece = [[NSMutableAttributedString alloc] initWithString:[string substringWithRange:range]];
    NSRange whole = NSMakeRange(0, piece.length);
    for (NSAttributedStringKey key in TSStyledCopyTextKeys())
        [text enumerateAttribute:key inRange:range options:0 usingBlock:^(id value, NSRange effective, BOOL *stop) {
            if (value)
                [piece addAttribute:key value:value range:NSMakeRange(effective.location - range.location, effective.length)];
        }];
    if (backgroundColor)
        [piece addAttribute:NSBackgroundColorAttributeName value:backgroundColor range:whole];
    [piece addAttribute:NSForegroundColorAttributeName value:textColor range:whole];
    if (!scanner || !scheme)
        return piece;
    // Whole lines are scanned, as in the source, so that a token that starts before the selection keeps its color.
    NSRange scanned = [scanner lineAlignedRangeForEditedRange:range inString:string];
    NSArray<NSAttributedStringKey> *keys = TSStyledCopySchemeKeys();
    [scanner enumerateTokensInString:string range:scanned usingBlock:^(NSRange token, TSSyntaxRole role, TSSyntaxTokenFlags flags) {
        if (role == TSSyntaxRoleNone)
            return;
        NSRange shared = NSIntersectionRange(token, range);
        if (shared.length == 0)
            return;
        NSDictionary<NSAttributedStringKey, id> *attributes = [[scheme attributesForRole:role] dictionaryWithValuesForKeys:keys];
        NSMutableDictionary<NSAttributedStringKey, id> *shown = [NSMutableDictionary dictionary];
        [attributes enumerateKeysAndObjectsUsingBlock:^(NSAttributedStringKey key, id value, BOOL *stop) {
            if (value != NSNull.null)
                shown[key] = value;
        }];
        if (shown.count)
            [piece addAttributes:shown range:NSMakeRange(shared.location - range.location, shared.length)];
    }];
    return piece;
}

NSAttributedString *TSStyledCopyString(NSAttributedString *text, NSArray<NSValue *> *ranges, id<TSSyntaxScanner> scanner,
                                       TSSyntaxColorScheme *scheme, NSColor *textColor, NSColor *backgroundColor,
                                       NSAppearance *appearance)
{
    NSMutableAttributedString *styled = [NSMutableAttributedString new];
    NSUInteger length = text.length;
    for (NSValue *value in ranges) {
        NSRange range = value.rangeValue;
        if (range.length == 0 || range.location >= length)
            continue;
        range.length = MIN(range.length, length - range.location);
        if (styled.length)
            [styled appendAttributedString:[[NSAttributedString alloc] initWithString:@"\n"
                attributes:[styled attributesAtIndex:styled.length - 1 effectiveRange:NULL]]];
        [styled appendAttributedString:TSStyledCopyPiece(text, range, scanner, scheme, textColor, backgroundColor)];
    }
    if (styled.length == 0)
        return nil;
    // The colors of the theme as they look in its mode, written as plain sRGB colors that any application reads; the
    // paper is the theme's background when it is copied, and white otherwise.
    [appearance performAsCurrentDrawingAppearance:^{
        NSColor *paper = TSStyledCopyColor(backgroundColor ?: NSColor.whiteColor, NSColor.whiteColor);
        NSRange whole = NSMakeRange(0, styled.length);
        for (NSAttributedStringKey key in @[NSForegroundColorAttributeName, NSBackgroundColorAttributeName, NSUnderlineColorAttributeName])
            [styled enumerateAttribute:key inRange:whole options:0 usingBlock:^(id color, NSRange effective, BOOL *stop) {
                if ([color isKindOfClass:NSColor.class])
                    [styled addAttribute:key value:TSStyledCopyColor(color, paper) range:effective];
            }];
    }];
    return [styled copy];
}

BOOL TSStyledCopyWriteToPasteboard(NSAttributedString *styled, NSPasteboard *pasteboard)
{
    NSRange whole = NSMakeRange(0, styled.length);
    NSData *rtf = [styled dataFromRange:whole documentAttributes:@{NSDocumentTypeDocumentAttribute: NSRTFTextDocumentType} error:NULL];
    NSData *html = [styled dataFromRange:whole documentAttributes:@{NSDocumentTypeDocumentAttribute: NSHTMLTextDocumentType,
                                                                     NSCharacterEncodingDocumentAttribute: @(NSUTF8StringEncoding)} error:NULL];
    if (!rtf)
        return NO;
    NSMutableArray<NSPasteboardType> *types = [NSMutableArray arrayWithObject:NSPasteboardTypeRTF];
    if (html)
        [types addObject:NSPasteboardTypeHTML];
    [types addObject:NSPasteboardTypeString];
    [pasteboard declareTypes:types owner:nil];
    BOOL written = [pasteboard setData:rtf forType:NSPasteboardTypeRTF];
    if (html)
        written = [pasteboard setData:html forType:NSPasteboardTypeHTML] && written;
    return [pasteboard setString:styled.string forType:NSPasteboardTypeString] && written;
}
