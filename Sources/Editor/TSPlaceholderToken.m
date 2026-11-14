// SPDX-License-Identifier: GPL-2.0-or-later
#import "TSPlaceholderToken.h"

NSString *TSPlaceholderTokenTitle(NSString *symbol)
{
    if ([symbol isEqualToString:@"#SEL#"]) return NSLocalizedString(@"Selected Text", @"Key binding token for #SEL#");
    if ([symbol isEqualToString:@"#INS#"]) return NSLocalizedString(@"Insertion Point", @"Key binding token for #INS#: where the insertion point is placed after the output");
    if ([symbol isEqualToString:@"#PASTE#"]) return NSLocalizedString(@"Clipboard Text", @"Key binding token for #PASTE#");
    if ([symbol isEqualToString:@"\n"]) return NSLocalizedString(@"Line Break", @"Key binding token for a line break in the output");
    if ([symbol isEqualToString:@"\t"]) return NSLocalizedString(@"Tab", @"Key binding token for a tab in the output");
    // An AppleScript macro is given the paths of the document's files and its name, each in quotes.
    if ([symbol isEqualToString:@"#FILEPATH#"]) return NSLocalizedString(@"File Path", @"Macro token for #FILEPATH#: the path of the document's file");
    if ([symbol isEqualToString:@"#PDFPATH#"]) return NSLocalizedString(@"PDF Path", @"Macro token for #PDFPATH#: the path of the document's PDF");
    if ([symbol isEqualToString:@"#DVIPATH#"]) return NSLocalizedString(@"DVI Path", @"Macro token for #DVIPATH#: the path of the document's .dvi file");
    if ([symbol isEqualToString:@"#PSPATH#"]) return NSLocalizedString(@"PS Path", @"Macro token for #PSPATH#: the path of the document's .ps file");
    if ([symbol isEqualToString:@"#LOGPATH#"]) return NSLocalizedString(@"Log Path", @"Macro token for #LOGPATH#: the path of the document's .log file");
    if ([symbol isEqualToString:@"#AUXPATH#"]) return NSLocalizedString(@"AUX Path", @"Macro token for #AUXPATH#: the path of the document's .aux file");
    if ([symbol isEqualToString:@"#INDPATH#"]) return NSLocalizedString(@"IND Path", @"Macro token for #INDPATH#: the path of the document's .ind file");
    if ([symbol isEqualToString:@"#BBLPATH#"]) return NSLocalizedString(@"BBL Path", @"Macro token for #BBLPATH#: the path of the document's .bbl file");
    if ([symbol isEqualToString:@"#HTMLPATH#"]) return NSLocalizedString(@"HTML Path", @"Macro token for #HTMLPATH#: the path of the document's .html file");
    if ([symbol isEqualToString:@"#NAMEPATH#"]) return NSLocalizedString(@"Path Without Extension", @"Macro token for #NAMEPATH#: the path of the document's file without its extension");
    if ([symbol isEqualToString:@"#TEXPATH#"]) return NSLocalizedString(@"TeX Path", @"Macro token for #TEXPATH#: the path of the document's .tex file");
    if ([symbol isEqualToString:@"#DOCUMENTNAME#"]) return NSLocalizedString(@"Document Name", @"Macro token for #DOCUMENTNAME#: the name of the document");
    if ([symbol isEqualToString:@"#FOLDERPATH#"]) return NSLocalizedString(@"Folder Path", @"Macro token for #FOLDERPATH#: the path of the document's folder");
    return NSLocalizedString(@"Mark", @"Key binding token for •");
}

static NSFont *TSPlaceholderTokenLabelFont(NSFont *font)
{
    return [NSFont systemFontOfSize:round(font.pointSize * 0.85)];
}

NSSize TSPlaceholderTokenSize(NSString *title, NSFont *font)
{
    NSSize text = [title sizeWithAttributes:@{NSFontAttributeName: TSPlaceholderTokenLabelFont(font)}];
    return NSMakeSize(ceil(text.width) + 14, ceil(font.ascender - font.descender) + 2);
}

void TSDrawPlaceholderToken(NSString *title, NSFont *font, NSRect rect)
{
    NSFont *labelFont = TSPlaceholderTokenLabelFont(font);
    NSSize text = [title sizeWithAttributes:@{NSFontAttributeName: labelFont}];
    NSRect pill = NSInsetRect(rect, 1.5, 0.5);
    CGFloat radius = NSHeight(pill) / 2;
    NSBezierPath *path = [NSBezierPath bezierPathWithRoundedRect:pill xRadius:radius yRadius:radius];
    [[NSColor.controlAccentColor colorWithAlphaComponent:0.16] setFill];
    [path fill];
    [[NSColor.controlAccentColor colorWithAlphaComponent:0.55] setStroke];
    path.lineWidth = 1;
    [path stroke];
    [title drawAtPoint:NSMakePoint(NSMinX(rect) + 7, NSMinY(rect) + floor((NSHeight(rect) - text.height) / 2))
        withAttributes:@{NSFontAttributeName: labelFont, NSForegroundColorAttributeName: NSColor.labelColor}];
}

NSImage *TSPlaceholderTokenImage(NSString *title, NSFont *font)
{
    NSSize size = TSPlaceholderTokenSize(title, font);
    NSImage *image = [NSImage imageWithSize:size flipped:NO drawingHandler:^BOOL(NSRect rect) {
        TSDrawPlaceholderToken(title, font, rect);
        return YES;
    }];
    image.accessibilityDescription = title;
    return image;
}
