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

// The selected text with the fonts and paragraph styles it has in the source, the text color, and the background
// under all of it when one is given.
static NSMutableAttributedString *TSStyledCopyPiece(NSAttributedString *text, NSRange range, NSColor *textColor, NSColor *backgroundColor)
{
    NSMutableAttributedString *piece = [[NSMutableAttributedString alloc] initWithString:[text.string substringWithRange:range]];
    NSRange whole = NSMakeRange(0, piece.length);
    for (NSAttributedStringKey key in TSStyledCopyTextKeys())
        [text enumerateAttribute:key inRange:range options:0 usingBlock:^(id value, NSRange effective, BOOL *stop) {
            if (value)
                [piece addAttribute:key value:value range:NSMakeRange(effective.location - range.location, effective.length)];
        }];
    if (backgroundColor)
        [piece addAttribute:NSBackgroundColorAttributeName value:backgroundColor range:whole];
    [piece addAttribute:NSForegroundColorAttributeName value:textColor range:whole];
    return piece;
}

NSAttributedString *TSStyledCopyString(NSAttributedString *text, NSArray<NSValue *> *ranges, id<TSSyntaxScanner> scanner,
                                       TSSyntaxColorScheme *scheme, NSColor *textColor, NSColor *backgroundColor,
                                       NSAppearance *appearance)
{
    NSString *string = text.string;
    NSUInteger length = string.length;
    NSMutableAttributedString *styled = [NSMutableAttributedString new];
    // Where each selected range starts in the copy.
    NSMutableArray<NSValue *> *selected = [NSMutableArray array];
    NSMutableArray<NSNumber *> *starts = [NSMutableArray array];
    for (NSValue *value in ranges) {
        NSRange range = value.rangeValue;
        if (range.length == 0 || range.location >= length)
            continue;
        range.length = MIN(range.length, length - range.location);
        if (styled.length)
            [styled appendAttributedString:[[NSAttributedString alloc] initWithString:@"\n"
                attributes:[styled attributesAtIndex:styled.length - 1 effectiveRange:NULL]]];
        [selected addObject:[NSValue valueWithRange:range]];
        [starts addObject:@(styled.length)];
        [styled appendAttributedString:TSStyledCopyPiece(text, range, textColor, backgroundColor)];
    }
    if (styled.length == 0)
        return nil;
    if (scanner && scheme) {
        // The whole text is scanned, so that a construct that starts before the selection, even lines before it (a
        // footnote, an XML comment), keeps its color, whatever part of the source is shown.
        NSRange scanned = [scanner lineAlignedRangeForEditedRange:NSMakeRange(0, length) inString:string];
        NSArray<NSAttributedStringKey> *keys = TSStyledCopySchemeKeys();
        NSMutableDictionary<NSNumber *, NSDictionary<NSAttributedStringKey, id> *> *roles = [NSMutableDictionary dictionary];
        [scanner enumerateTokensInString:string range:scanned usingBlock:^(NSRange token, TSSyntaxRole role, TSSyntaxTokenFlags flags) {
            if (role == TSSyntaxRoleNone)
                return;
            NSDictionary<NSAttributedStringKey, id> *shown = roles[@(role)];
            if (!shown) {
                NSMutableDictionary<NSAttributedStringKey, id> *attributes = [NSMutableDictionary dictionary];
                [[[scheme attributesForRole:role] dictionaryWithValuesForKeys:keys] enumerateKeysAndObjectsUsingBlock:^(NSAttributedStringKey key, id value, BOOL *stop) {
                    if (value != NSNull.null)
                        attributes[key] = value;
                }];
                shown = roles[@(role)] = [attributes copy];
            }
            if (shown.count == 0)
                return;
            for (NSUInteger i = 0; i < selected.count; i++) {
                NSRange range = selected[i].rangeValue;
                NSRange shared = NSIntersectionRange(token, range);
                if (shared.length)
                    [styled addAttributes:shown range:NSMakeRange(starts[i].unsignedIntegerValue + shared.location - range.location, shared.length)];
            }
        }];
    }
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

#pragma mark HTML

static NSString *TSStyledCopyHex(NSColor *color)
{
    NSColor *srgb = [color colorUsingColorSpace:NSColorSpace.sRGBColorSpace] ?: color;
    return [NSString stringWithFormat:@"#%02X%02X%02X", (int)lround(MIN(MAX(srgb.redComponent, 0), 1) * 255),
            (int)lround(MIN(MAX(srgb.greenComponent, 0), 1) * 255), (int)lround(MIN(MAX(srgb.blueComponent, 0), 1) * 255)];
}

static NSString *TSStyledCopyEscaped(NSString *string)
{
    NSMutableString *escaped = [NSMutableString stringWithCapacity:string.length];
    [string enumerateSubstringsInRange:NSMakeRange(0, string.length) options:NSStringEnumerationByComposedCharacterSequences
                            usingBlock:^(NSString *character, NSRange range, NSRange enclosing, BOOL *stop) {
        if ([character isEqualToString:@"&"]) [escaped appendString:@"&amp;"];
        else if ([character isEqualToString:@"<"]) [escaped appendString:@"&lt;"];
        else if ([character isEqualToString:@">"]) [escaped appendString:@"&gt;"];
        else if ([character isEqualToString:@"\""]) [escaped appendString:@"&quot;"];
        else if ([character isEqualToString:@"\r"] || [character isEqualToString:@"\r\n"]) [escaped appendString:@"\n"];
        else [escaped appendString:character];
    }];
    return escaped;
}

static NSString *TSStyledCopyFontStyle(NSFont *font)
{
    if (!font)
        return @"";
    NSString *family = [font.familyName ?: font.fontName stringByReplacingOccurrencesOfString:@"'" withString:@"\\'"];
    NSFontSymbolicTraits traits = font.fontDescriptor.symbolicTraits;
    return [NSString stringWithFormat:@"font-family:'%@',monospace;font-size:%gpt;font-weight:%@;font-style:%@;", family, font.pointSize,
            (traits & NSFontDescriptorTraitBold) ? @"bold" : @"normal", (traits & NSFontDescriptorTraitItalic) ? @"italic" : @"normal"];
}

// The tab width of the source: its tab stops are evenly spaced (or the default interval is used).
static CGFloat TSStyledCopyTabWidth(NSParagraphStyle *style)
{
    if (style.tabStops.count)
        return style.tabStops.firstObject.location;
    return style.defaultTabInterval;
}

// HTML of its own rather than AppKit's: AppKit writes sizes in CSS pixels (3/4 of the size in points), colors in
// another color space, a background that fills the paragraph and no tab width. Here every run is a span with the
// sRGB colors, the font and its size in points, and only the characters get the background; the tab width is that of
// the source.
NSString *TSStyledCopyHTML(NSAttributedString *styled)
{
    NSRange whole = NSMakeRange(0, styled.length);
    NSParagraphStyle *style = whole.length ? [styled attribute:NSParagraphStyleAttributeName atIndex:0 effectiveRange:NULL] : nil;
    CGFloat tab = TSStyledCopyTabWidth(style);
    NSMutableString *html = [NSMutableString stringWithString:@"<!DOCTYPE html>\n<html><head><meta charset=\"utf-8\"></head><body>"];
    [html appendFormat:@"<pre style=\"margin:0;white-space:pre-wrap;%@\">", tab > 0 ? [NSString stringWithFormat:@"tab-size:%gpt;-moz-tab-size:%gpt;", tab, tab] : @""];
    [styled enumerateAttributesInRange:whole options:0 usingBlock:^(NSDictionary<NSAttributedStringKey, id> *attributes, NSRange range, BOOL *stop) {
        NSMutableString *css = [NSMutableString stringWithString:TSStyledCopyFontStyle(attributes[NSFontAttributeName])];
        if (attributes[NSForegroundColorAttributeName])
            [css appendFormat:@"color:%@;", TSStyledCopyHex(attributes[NSForegroundColorAttributeName])];
        if (attributes[NSBackgroundColorAttributeName])
            [css appendFormat:@"background-color:%@;", TSStyledCopyHex(attributes[NSBackgroundColorAttributeName])];
        if ([attributes[NSUnderlineStyleAttributeName] integerValue] != 0) {
            [css appendString:@"text-decoration:underline;"];
            if (attributes[NSUnderlineColorAttributeName])
                [css appendFormat:@"text-decoration-color:%@;", TSStyledCopyHex(attributes[NSUnderlineColorAttributeName])];
        }
        [html appendFormat:@"<span style=\"%@\">%@</span>", css, TSStyledCopyEscaped([styled.string substringWithRange:range])];
    }];
    [html appendString:@"</pre></body></html>\n"];
    return html;
}

BOOL TSStyledCopyWriteToPasteboard(NSAttributedString *styled, NSPasteboard *pasteboard)
{
    NSRange whole = NSMakeRange(0, styled.length);
    NSData *rtf = [styled dataFromRange:whole documentAttributes:@{NSDocumentTypeDocumentAttribute: NSRTFTextDocumentType} error:NULL];
    NSData *html = [TSStyledCopyHTML(styled) dataUsingEncoding:NSUTF8StringEncoding];
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
