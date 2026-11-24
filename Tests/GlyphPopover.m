// Character Info (TSGlyphPopoverController), as the application builds it, in
// each language given:
//   * one character: the name, and the table of code point, block, category and
//     version, from ICU, for letters, kana, CJK ideographs, emoji, variation
//     sequences, surrogate pairs, combining sequences, control characters,
//     private use, unassigned and deprecated code points; each code point of a
//     character made of several, with its block and category when opened;
//   * several characters: their number, words and lines and their code points;
//   * the colors: every text is in a system label color, readable in light and
//     dark appearance (contrast against the popover background);
//   * the whole text of every label shows (LayoutChecks.inc), also with long
//     names, long translations, opened code points and the block name of Unicode;
//   * the popover takes the size of what it shows.
// Nothing is shown on screen; AppKit defaults stay in memory.
// Usage: GlyphPopover [--images DIR] [--mutation NAME] <language>|<Localizable.strings> ...
#import <Cocoa/Cocoa.h>
#import <objc/runtime.h>
#import "TestAppKitIsolation.h"
#import "TSGlyphPopoverController.h"
#import "TSStatusBarCounting.h"
#import "TSUnicodeBlockNames.h"
#import <unicode/uchar.h>
#include "LayoutChecks.inc"

@interface TSGlyphPopoverController (Test)
- (void)toggleCodePoint:(NSButton *)sender;
- (void)toggleBlockName:(NSClickGestureRecognizer *)sender;
@end

static int failures;
static void Fail(NSString *line) { printf("FAIL %s\n", line.UTF8String); failures++; }

static NSView *Find(NSView *view, NSString *identifier) {
    if ([view.identifier isEqualToString:identifier]) return view;
    for (NSView *subview in view.subviews) { NSView *found = Find(subview, identifier); if (found) return found; }
    return nil;
}
static NSString *Text(NSView *root, NSString *identifier) {
    NSView *view = Find(root, identifier);
    if ([view isKindOfClass:NSTextField.class]) return ((NSTextField *)view).stringValue;
    if ([view isKindOfClass:NSTextView.class]) return ((NSTextView *)view).string;
    return nil;
}
static void Expect(NSView *root, NSString *where, NSString *identifier, NSString *expected) {
    NSString *text = Text(root, identifier);
    if (!(expected ? [text isEqualToString:expected] : text == nil))
        Fail([NSString stringWithFormat:@"%@ %@ is \"%@\", not \"%@\"", where, identifier, text ?: @"(none)", expected ?: @"(none)"]);
}

// The relative luminance and contrast ratio of WCAG 2.
static CGFloat Luminance(NSColor *color) {
    NSColor *rgb = [color colorUsingColorSpace:NSColorSpace.sRGBColorSpace];
    CGFloat c[3] = {rgb.redComponent, rgb.greenComponent, rgb.blueComponent};
    for (int i = 0; i < 3; i++) c[i] = c[i] <= 0.04045 ? c[i] / 12.92 : pow((c[i] + 0.055) / 1.055, 2.4);
    return 0.2126 * c[0] + 0.7152 * c[1] + 0.0722 * c[2];
}
static NSColor *Over(NSColor *top, NSColor *bottom) {
    NSColor *t = [top colorUsingColorSpace:NSColorSpace.sRGBColorSpace], *b = [bottom colorUsingColorSpace:NSColorSpace.sRGBColorSpace];
    CGFloat a = t.alphaComponent;
    return [NSColor colorWithSRGBRed:t.redComponent * a + b.redComponent * (1 - a) green:t.greenComponent * a + b.greenComponent * (1 - a)
                                blue:t.blueComponent * a + b.blueComponent * (1 - a) alpha:1];
}
static CGFloat Contrast(NSColor *a, NSColor *b) {
    CGFloat la = Luminance(a), lb = Luminance(b);
    return (MAX(la, lb) + 0.05) / (MIN(la, lb) + 0.05);
}

// The background drawn behind the popover in the images and used for contrast:
// a light or dark popover over an editor, as close as drawing offscreen allows
// (the Liquid Glass material needs a window on screen).
static NSColor *PopoverBackground(BOOL dark) {
    return dark ? [NSColor colorWithSRGBRed:0.16 green:0.16 blue:0.17 alpha:1] : [NSColor colorWithSRGBRed:0.965 green:0.965 blue:0.97 alpha:1];
}

static void CollectFields(NSView *view, NSMutableArray<NSView *> *out) {
    if (view.isHidden) return;
    if ([view isKindOfClass:NSTextField.class] || [view isKindOfClass:NSTextView.class]) [out addObject:view];
    for (NSView *subview in view.subviews) CollectFields(subview, out);
}

static void CheckColors(NSView *root, NSString *where) {
    NSMutableArray<NSView *> *fields = [NSMutableArray array];
    CollectFields(root, fields);
    for (NSView *field in fields) {
        NSColor *color = [field isKindOfClass:NSTextField.class] ? ((NSTextField *)field).textColor
                                                                  : [((NSTextView *)field).textStorage attribute:NSForegroundColorAttributeName atIndex:0 effectiveRange:NULL];
        if (color != NSColor.labelColor && color != NSColor.secondaryLabelColor) {
            Fail([NSString stringWithFormat:@"%@ %@ is drawn in %@, not a label color", where, field.identifier, color]);
            continue;
        }
        for (NSAppearanceName name in @[NSAppearanceNameAqua, NSAppearanceNameDarkAqua]) {
            __block NSColor *resolved;
            [[NSAppearance appearanceNamed:name] performAsCurrentDrawingAppearance:^{ resolved = [color colorUsingColorSpace:NSColorSpace.sRGBColorSpace]; }];
            NSColor *background = PopoverBackground(name == NSAppearanceNameDarkAqua);
            CGFloat contrast = Contrast(Over(resolved, background), background);
            // The secondary color is that of the headings, as in CotEditor: lighter than the values but far from
            // the disabled text the details used to have (about 2).
            CGFloat needed = color == NSColor.labelColor ? 7 : 3.5;
            if (contrast < needed)
                Fail([NSString stringWithFormat:@"%@ %@ has contrast %.1f in %@, needs %.1f", where, field.identifier, contrast, name, needed]);
        }
    }
}

static void SavePopoverImage(NSView *view, NSString *name, BOOL dark) {
    if (!imagesDirectory) return;
    CGFloat margin = 28, arrow = 9;
    NSSize size = NSMakeSize(NSWidth(view.bounds) + 2 * margin, NSHeight(view.bounds) + 2 * margin + arrow);
    NSBitmapImageRep *content = [view bitmapImageRepForCachingDisplayInRect:view.bounds];
    [view cacheDisplayInRect:view.bounds toBitmapImageRep:content];
    NSBitmapImageRep *rep = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL pixelsWide:(NSInteger)size.width * 2 pixelsHigh:(NSInteger)size.height * 2
                                                                 bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES isPlanar:NO
                                                                colorSpaceName:NSCalibratedRGBColorSpace bytesPerRow:0 bitsPerPixel:0];
    rep.size = size;
    [NSGraphicsContext saveGraphicsState];
    NSGraphicsContext.currentContext = [NSGraphicsContext graphicsContextWithBitmapImageRep:rep];
    // The editor behind: its background and a few lines of source.
    [(dark ? [NSColor colorWithSRGBRed:0.12 green:0.12 blue:0.13 alpha:1] : NSColor.whiteColor) setFill];
    NSRectFill(NSMakeRect(0, 0, size.width, size.height));
    [[NSColor colorWithWhite:dark ? 1 : 0 alpha:0.12] setFill];
    for (CGFloat y = size.height - 12; y > 0; y -= 17)
        NSRectFillUsingOperation(NSMakeRect(10, y - 6, fmod(y * 7.3, size.width - 40) + 30, 6), NSCompositingOperationSourceOver);
    // The popover: shadow, body with its arrow at the top, hairline border.
    NSRect body = NSMakeRect(margin, margin, NSWidth(view.bounds), NSHeight(view.bounds));
    NSBezierPath *shape = [NSBezierPath bezierPathWithRoundedRect:body xRadius:12 yRadius:12];
    NSBezierPath *tip = [NSBezierPath bezierPath];
    [tip moveToPoint:NSMakePoint(NSMidX(body) - arrow, NSMaxY(body) - 1)];
    [tip lineToPoint:NSMakePoint(NSMidX(body), NSMaxY(body) + arrow)];
    [tip lineToPoint:NSMakePoint(NSMidX(body) + arrow, NSMaxY(body) - 1)];
    [tip closePath];
    [shape appendBezierPath:tip];
    NSShadow *shadow = [NSShadow new];
    shadow.shadowColor = [NSColor colorWithWhite:0 alpha:dark ? 0.6 : 0.25];
    shadow.shadowBlurRadius = 14; shadow.shadowOffset = NSMakeSize(0, -4);
    [NSGraphicsContext saveGraphicsState];
    [shadow set];
    [[PopoverBackground(dark) colorWithAlphaComponent:0.94] setFill];
    [shape fill];
    [NSGraphicsContext restoreGraphicsState];
    [[NSColor colorWithWhite:dark ? 1 : 0 alpha:0.12] setStroke];
    shape.lineWidth = 1;
    [shape stroke];
    [content drawInRect:body fromRect:NSZeroRect operation:NSCompositingOperationSourceOver fraction:1 respectFlipped:YES hints:nil];
    [NSGraphicsContext restoreGraphicsState];
    NSString *file = [[name stringByReplacingOccurrencesOfString:@"/" withString:@"-"] stringByAppendingPathExtension:@"png"];
    [[rep representationUsingType:NSBitmapImageFileTypePNG properties:@{}] writeToFile:[imagesDirectory stringByAppendingPathComponent:file] atomically:YES];
}

// The view as it is shown, in an appearance; laid out again in it, as fonts and colors resolve there.
static NSView *Shown(TSGlyphPopoverController *controller, BOOL dark) {
    NSView *view = controller.view;
    view.appearance = [NSAppearance appearanceNamed:dark ? NSAppearanceNameDarkAqua : NSAppearanceNameAqua];
    [view layoutSubtreeIfNeeded];
    return view;
}

static void CheckSize(TSGlyphPopoverController *controller, NSString *where) {
    NSView *view = controller.view;
    NSSize fitting = view.fittingSize;
    if (fabs(NSWidth(view.frame) - ceil(fitting.width)) > 0.5 || fabs(NSHeight(view.frame) - ceil(fitting.height)) > 0.5
        || !NSEqualSizes(controller.preferredContentSize, view.frame.size))
        Fail([NSString stringWithFormat:@"%@ the popover is %@ (preferred %@), not its contents' %@", where,
              NSStringFromSize(view.frame.size), NSStringFromSize(controller.preferredContentSize), NSStringFromSize(fitting)]);
    // Every view lies inside the popover, with the inset around the contents.
    NSView *content = view.subviews.firstObject;
    if (NSMinX(content.frame) < 13.5 || NSMinY(content.frame) < 13.5 || NSMaxX(content.frame) > NSWidth(view.bounds) - 13.5 || NSMaxY(content.frame) > NSHeight(view.bounds) - 13.5)
        Fail([NSString stringWithFormat:@"%@ the contents %@ are not inset in %@", where, NSStringFromRect(content.frame), NSStringFromRect(view.bounds)]);
}

static void CheckEverything(TSGlyphPopoverController *controller, NSString *where, NSString *imageName) {
    for (int dark = 0; dark < 2; dark++) {
        NSView *view = Shown(controller, dark);
        NSString *in = [where stringByAppendingString:dark ? @" (dark)" : @""];
        CheckRoot(view, in);
        CheckSize(controller, in);
        if (imageName) SavePopoverImage(view, [imageName stringByAppendingString:dark ? @"-dark" : @"-light"], dark);
    }
    CheckColors(controller.view, where);
}

// The table starts below the name, at its leading edge, as in CotEditor: its widest heading there.
static void CheckTableEdge(NSView *view, NSString *where) {
    CGFloat headings = CGFLOAT_MAX;
    for (NSString *key in @[@"codePoint", @"block", @"category", @"version"]) {
        NSView *label = Find(view, [key stringByAppendingString:@".label"]);
        if (label) headings = MIN(headings, NSMinX([view convertRect:label.bounds fromView:label]));
    }
    NSView *name = Find(view, @"name");
    CGFloat nameX = NSMinX([view convertRect:name.bounds fromView:name]);
    if (fabs(headings - nameX) > 1)
        Fail([NSString stringWithFormat:@"%@ the table starts at %.1f, the name at %.1f", where, headings, nameX]);
}

typedef struct { NSString *name, *text; } Case;

// --dump-blocks TABLE LANGUAGE: the name Character Info shows for every block of ICU, read from TABLE (the
// Character Viewer's table, a copy of it, or a missing or broken file) in LANGUAGE, as JSON {English name: shown}.
static int DumpBlocks(NSString *table, NSString *language) {
    TSUseUnicodeBlockTable(table, language);
    NSMutableDictionary<NSString *, NSString *> *shown = [NSMutableDictionary dictionary];
    NSMutableSet<NSNumber *> *seen = [NSMutableSet set];
    for (UChar32 c = 0; c <= 0x10FFFF; c++) {
        UBlockCode block = ublock_getCode(c);
        if (block == UBLOCK_NO_BLOCK || [seen containsObject:@(block)]) continue;
        [seen addObject:@(block)];
        NSString *name = TSUnicodeBlockName((UInt32)c);
        shown[name] = TSLocalizedUnicodeBlockName(name);
    }
    NSData *json = [NSJSONSerialization dataWithJSONObject:shown options:NSJSONWritingSortedKeys error:NULL];
    fwrite(json.bytes, 1, json.length, stdout);
    return 0;
}

int main(int argc, char **argv) { @autoreleasepool {
    if (argc == 4 && !strcmp(argv[1], "--dump-blocks")) return DumpBlocks(@(argv[2]), @(argv[3]));
    if (argc == 3 && !strcmp(argv[1], "--read-once")) {
        // A copy of the table, removed after the first name: the second name still comes from it.
        TSUseUnicodeBlockTable(@(argv[2]), @"ja");
        NSString *first = TSLocalizedUnicodeBlockName(@"Basic Latin");
        [NSFileManager.defaultManager removeItemAtPath:@(argv[2]) error:NULL];
        NSString *second = TSLocalizedUnicodeBlockName(@"Hiragana");
        printf("%s\n", [first isEqual:@"Basic Latin"] || [second isEqual:@"Hiragana"] ? "read again or not at all" : "read once");
        return 0;
    }
    TSInstallAppKitIsolation();
    InstallLocalizedStrings();
    [NSApplication sharedApplication];
    [NSApp setActivationPolicy:NSApplicationActivationPolicyProhibited];
    NSMutableArray<NSString *> *entries = [NSMutableArray array];
    for (int i = 1; i < argc; i++) {
        if (!strcmp(argv[i], "--images") && i + 1 < argc) { imagesDirectory = @(argv[++i]); continue; }
        [entries addObject:@(argv[i])];
    }
    NSString *variation = @"葛\U000E0100";
    NSString *longName = @"ﯹ";
    for (NSString *entry in entries) {
        NSArray<NSString *> *parts = [entry componentsSeparatedByString:@"|"];
        NSString *language = parts[0];
        UseLocalizedStrings(parts[1]);
        // The block names of the Character Viewer of this Mac, in the language; the runner gives the names it expects.
        TSUseUnicodeBlockTable(nil, language);
        NSDictionary<NSString *, NSString *> *expectedBlocks = parts.count > 2 ? [NSJSONSerialization JSONObjectWithData:[NSData dataWithContentsOfFile:parts[2]] options:0 error:NULL] : @{};
        BOOL english = [language isEqual:@"en"], japanese = [language isEqual:@"ja"];
        BOOL images = imagesDirectory && (english || japanese);

        // One code point: the name and the whole table.
        struct { NSString *name, *text, *title, *codePoint, *block, *category, *version; } singles[] = {
            {@"latin", @"a", @"LATIN SMALL LETTER A", @"U+0061", @"Basic Latin", @"Lowercase Letter (Ll)", @"Unicode 1.1"},
            {@"kana", @"あ", @"HIRAGANA LETTER A", @"U+3042", @"Hiragana", @"Other Letter (Lo)", @"Unicode 1.1"},
            {@"kanji", @"蛙", @"CJK UNIFIED IDEOGRAPH-86D9", @"U+86D9", @"CJK Unified Ideographs", @"Other Letter (Lo)", @"Unicode 1.1"},
            {@"emoji", @"\U0001F600", @"GRINNING FACE", @"U+1F600 (U+D83D U+DE00)", @"Emoticons", @"Other Symbol (So)", @"Unicode 6.1"},
            {@"surrogate", @"\U00020BB7", @"CJK UNIFIED IDEOGRAPH-20BB7", @"U+20BB7 (U+D842 U+DFB7)", @"CJK Unified Ideographs Extension B", @"Other Letter (Lo)", @"Unicode 3.1"},
            {@"control", @"\t", @"HORIZONTAL TABULATION", @"U+0009", @"Basic Latin", @"Control (Cc)", @"Unicode 1.1"},
            {@"space", @" ", @"SPACE", @"U+0020", @"Basic Latin", @"Space Separator (Zs)", @"Unicode 1.1"},
            {@"private", @"", nil, @"U+E000", @"Private Use Area", @"Private Use (Co)", @"Unicode 1.1"},
            {@"unassigned", @"͸", nil, @"U+0378", @"Greek and Coptic", @"Unassigned (Cn)", nil},
            {@"noblock", @"⿠", nil, @"U+2FE0", nil, @"Unassigned (Cn)", nil},
            {@"corrected", @"︘", @"PRESENTATION FORM FOR VERTICAL RIGHT WHITE LENTICULAR BRACKET", @"U+FE18", @"Vertical Forms", @"Close Punctuation (Pe)", @"Unicode 4.1"},
            {@"longname", longName, @"ARABIC LIGATURE UIGHUR KIRGHIZ YEH WITH HAMZA ABOVE WITH ALEF MAKSURA ISOLATED FORM", @"U+FBF9", @"Arabic Presentation Forms-A", @"Other Letter (Lo)", @"Unicode 1.1"},
            {@"longblock", @"ᢰ", @"CANADIAN SYLLABICS OY", @"U+18B0", @"Unified Canadian Aboriginal Syllabics Extended", @"Other Letter (Lo)", @"Unicode 5.2"},
            {@"deprecated", @"ឣ", @"KHMER INDEPENDENT VOWEL QAQ", @"U+17A3", @"Khmer", @"Other Letter (Lo)", @"Unicode 3.0"},
        };
        NSString *unknown = LocalizedStrings[@"Unknown"] ?: @"Unknown", *noBlock = LocalizedStrings[@"No Block"] ?: @"No Block";
        for (size_t i = 0; i < sizeof singles / sizeof singles[0]; i++) {
            NSString *where = [NSString stringWithFormat:@"%@ %@", language, singles[i].name];
            TSGlyphPopoverController *controller = [[TSGlyphPopoverController alloc] initWithCharacter:singles[i].text];
            NSView *view = controller.view;
            Expect(view, where, @"name", singles[i].title ?: unknown);
            Expect(view, where, @"codePoint", singles[i].codePoint);
            NSString *block = singles[i].block ? (expectedBlocks[singles[i].block] ?: singles[i].block) : noBlock;
            Expect(view, where, @"block", block);
            Expect(view, where, @"category", singles[i].category);
            Expect(view, where, @"version", singles[i].version);
            for (NSString *key in @[@"codePoint", @"block", @"category", @"version"]) {
                NSString *heading = [key isEqual:@"codePoint"] ? @"Code Point:" : [[key capitalizedString] stringByAppendingString:@":"];
                if (Find(view, key)) Expect(view, where, [key stringByAppendingString:@".label"], LocalizedStrings[heading] ?: heading);
            }
            if (Find(view, @"scalars")) Fail([where stringByAppendingString:@" lists code points for a single one"]);
            if ((Find(view, @"deprecated") != nil) != [singles[i].name isEqual:@"deprecated"])
                Fail([where stringByAppendingString:@" shows the deprecated badge wrongly"]);
            NSTextField *nameField = (NSTextField *)Find(view, @"name");
            if ((nameField.textColor == NSColor.secondaryLabelColor) != (singles[i].title == nil))
                Fail([where stringByAppendingString:@" the name is not in the label color, or Unknown not in the secondary color"]);
            if (singles[i].title && nameField.font.fontDescriptor.symbolicTraits & NSFontDescriptorTraitBold) {} else if (singles[i].title) {
                CGFloat weight = [[nameField.font.fontDescriptor objectForKey:NSFontTraitsAttribute][NSFontWeightTrait] doubleValue];
                if (weight < NSFontWeightSemibold - 0.01) Fail([where stringByAppendingString:@" the name is not semibold"]);
            }
            // The picture of an invisible control character or space, in the tertiary color.
            NSView *glyph = Find(view, @"glyph");
            NSAttributedString *drawn = [glyph valueForKey:@"glyph"];
            BOOL invisible = [singles[i].name isEqual:@"control"] || [singles[i].name isEqual:@"space"];
            NSString *glyphText = invisible ? ([singles[i].name isEqual:@"control"] ? @"␉" : @"␠") : singles[i].text;
            if (![drawn.string isEqualToString:glyphText] || ([drawn attribute:NSForegroundColorAttributeName atIndex:0 effectiveRange:NULL] == NSColor.tertiaryLabelColor) != invisible)
                Fail([NSString stringWithFormat:@"%@ the glyph is \"%@\"", where, drawn.string]);
            // A long name wraps instead of widening the popover beyond its limit.
            if (NSWidth(view.frame) > 64 + 8 + 360 + 2 * 14 + 1)
                Fail([NSString stringWithFormat:@"%@ the popover is %.0f wide", where, NSWidth(view.frame)]);
            if ([singles[i].name isEqual:@"longname"] && NSHeight(nameField.frame) < 2 * nameField.font.pointSize)
                Fail([where stringByAppendingString:@" the long name does not wrap"]);
            NSString *image = nil;
            if (images && ([@[@"latin", @"kana", @"kanji", @"emoji", @"surrogate", @"control", @"longname", @"deprecated"] containsObject:singles[i].name]))
                image = [NSString stringWithFormat:@"%@-single-%@", language, singles[i].name];
            CheckEverything(controller, where, image);
            CheckTableEdge(view, where);
            // The block name of Unicode, as a click shows it, also fits; another click brings the translation back.
            NSTextField *blockField = (NSTextField *)Find(view, @"block");
            NSClickGestureRecognizer *click = nil;
            for (NSGestureRecognizer *recognizer in blockField.gestureRecognizers)
                if ([recognizer isKindOfClass:NSClickGestureRecognizer.class]) click = (NSClickGestureRecognizer *)recognizer;
            BOOL translated = singles[i].block && ![block isEqualToString:singles[i].block];
            if ((click != nil) != translated) Fail([where stringByAppendingString:@" the block name toggles where it has no translation, or not where it has"]);
            if (click) {
                if (![blockField.toolTip isEqualToString:singles[i].block]) Fail([where stringByAppendingString:@" the tooltip of the block is not the name of Unicode"]);
                [controller toggleBlockName:click];
                Expect(view, [where stringByAppendingString:@" clicked"], @"block", singles[i].block);
                CheckEverything(controller, [where stringByAppendingString:@" with the block name of Unicode"], nil);
                [controller toggleBlockName:click];
                Expect(view, [where stringByAppendingString:@" clicked twice"], @"block", block);
            }
        }

        // One character of several code points: a variation sequence, an emoji with a skin tone, a combining
        // sequence, a ZWJ sequence, CR LF. A variation sequence keeps the table of its base, with what the selector does.
        NSString *style = LocalizedStrings[@"Emoji Style"] ?: @"Emoji Style", *variant = LocalizedStrings[@"Variant"] ?: @"Variant", *tone = LocalizedStrings[@"Skin Tone IV"] ?: @"Skin Tone IV";
        NSString *(^consisting)(int) = ^(int n) {
            NSString *format = LocalizedStrings[@"<a character consisting of %1$@ code points>"] ?: @"<a character consisting of %1$@ code points>";
            return [NSString stringWithFormat:format, TSStatusBarFormattedNumber((NSUInteger)n), n];
        };
        struct { NSString *name, *text, *title, *codePoint; NSArray<NSString *> *rows; } multiples[] = {
            {@"variation", variation, [NSString stringWithFormat:@"CJK UNIFIED IDEOGRAPH-845B (%@)", variant], @"U+845B",
             @[@"U+845B|CJK UNIFIED IDEOGRAPH-845B", @"U+E0100|(U+DB40 U+DD00)|VARIATION SELECTOR-17"]},
            {@"emojistyle", @"☺️", [NSString stringWithFormat:@"WHITE SMILING FACE (%@)", style], @"U+263A",
             @[@"U+263A|WHITE SMILING FACE", @"U+FE0F|VARIATION SELECTOR-16"]},
            {@"skintone", @"\U0001F44D\U0001F3FD", [NSString stringWithFormat:@"THUMBS UP SIGN (%@)", tone], @"U+1F44D (U+D83D U+DC4D)",
             @[@"U+1F44D|(U+D83D U+DC4D)|THUMBS UP SIGN", @"U+1F3FD|(U+D83C U+DFFD)|EMOJI MODIFIER FITZPATRICK TYPE-4"]},
            {@"combining", @"é", consisting(2), nil, @[@"U+0065|LATIN SMALL LETTER E", @"U+0301|COMBINING ACUTE ACCENT"]},
            {@"zwj", @"\U0001F468‍\U0001F469‍\U0001F467", consisting(5), nil,
             @[@"U+1F468|(U+D83D U+DC68)|MAN", @"U+200D|ZERO WIDTH JOINER", @"U+1F469|(U+D83D U+DC69)|WOMAN", @"U+200D|ZERO WIDTH JOINER", @"U+1F467|(U+D83D U+DC67)|GIRL"]},
            {@"family", @"\U0001F9D1\u200D\U0001F9D1\u200D\U0001F9D2\u200D\U0001F9D2", consisting(7), nil,
             @[@"U+1F9D1|(U+D83E U+DDD1)|ADULT", @"U+200D|ZERO WIDTH JOINER", @"U+1F9D1|(U+D83E U+DDD1)|ADULT", @"U+200D|ZERO WIDTH JOINER",
               @"U+1F9D2|(U+D83E U+DDD2)|CHILD", @"U+200D|ZERO WIDTH JOINER", @"U+1F9D2|(U+D83E U+DDD2)|CHILD"]},
            {@"flag", @"\U0001F1EF\U0001F1F5", consisting(2), nil,
             @[@"U+1F1EF|(U+D83C U+DDEF)|REGIONAL INDICATOR SYMBOL LETTER J", @"U+1F1F5|(U+D83C U+DDF5)|REGIONAL INDICATOR SYMBOL LETTER P"]},
        };
        for (size_t i = 0; i < sizeof multiples / sizeof multiples[0]; i++) {
            NSString *where = [NSString stringWithFormat:@"%@ %@", language, multiples[i].name];
            TSGlyphPopoverController *controller = [[TSGlyphPopoverController alloc] initWithCharacter:multiples[i].text];
            NSView *view = controller.view;
            Expect(view, where, @"name", multiples[i].title);
            Expect(view, where, @"codePoint", multiples[i].codePoint);
            if (!multiples[i].codePoint && Find(view, @"block")) Fail([where stringByAppendingString:@" shows a table for a character of several code points"]);
            NSTextField *nameField = (NSTextField *)Find(view, @"name");
            CGFloat weight = [[nameField.font.fontDescriptor objectForKey:NSFontTraitsAttribute][NSFontWeightTrait] doubleValue];
            if ((weight > NSFontWeightRegular + 0.01) != (multiples[i].codePoint != nil)) Fail([where stringByAppendingString:@" the name has the wrong weight"]);
            NSArray *rows = multiples[i].rows;
            for (NSUInteger r = 0; r < rows.count; r++) {
                NSArray<NSString *> *row = [rows[r] componentsSeparatedByString:@"|"];
                NSString *prefix = [NSString stringWithFormat:@"scalar.%lu.", (unsigned long)r];
                Expect(view, where, [prefix stringByAppendingString:@"codePoint"], row[0]);
                Expect(view, where, [prefix stringByAppendingString:@"surrogates"], row.count == 3 ? row[1] : nil);
                Expect(view, where, [prefix stringByAppendingString:@"name"], row.lastObject);
                if (Find(view, [prefix stringByAppendingString:@"detail"])) Fail([where stringByAppendingString:@" a code point is open before it is clicked"]);
            }
            if (Find(view, [NSString stringWithFormat:@"scalar.%lu.codePoint", (unsigned long)rows.count])) Fail([where stringByAppendingString:@" lists too many code points"]);
            NSString *image = images ? [NSString stringWithFormat:@"%@-single-%@", language, multiples[i].name] : nil;
            CheckEverything(controller, where, image);
            if (multiples[i].codePoint) CheckTableEdge(view, where);
            // Opened, each code point shows its glyph, block and category, and the popover grows to show them.
            CGFloat closedHeight = NSHeight(view.frame);
            for (NSUInteger r = 0; r < rows.count; r++) {
                NSButton *disclosure = (NSButton *)Find(view, [NSString stringWithFormat:@"scalar.%lu.disclosure", (unsigned long)r]);
                disclosure.state = NSControlStateValueOn;
                [controller toggleCodePoint:disclosure];
            }
            if (NSHeight(view.frame) < closedHeight + 20 * rows.count) Fail([where stringByAppendingString:@" the popover does not grow when the code points are opened"]);
            Expect(view, where, @"scalar.0.category", [rows[0] hasPrefix:@"U+0065"] ? @"Lowercase Letter (Ll)" : [rows[0] hasPrefix:@"U+000D"] ? @"Control (Cc)"
                   : [rows[0] hasPrefix:@"U+263A"] || [rows[0] hasPrefix:@"U+1F"] ? @"Other Symbol (So)" : @"Other Letter (Lo)");
            if (Find(view, @"scalar.0.version")) Fail([where stringByAppendingString:@" an opened code point shows its version"]);
            BOOL drawn = [@[@"family", @"variation", @"flag", @"combining"] containsObject:multiples[i].name];
            CheckEverything(controller, [where stringByAppendingString:@" opened"], nil);
            CGFloat openHeight = NSHeight(view.frame);
            // Each code point opens and closes by itself: close one in the middle (the fourth of the family, as in
            // CotEditor's picture, or the last), and only its details go.
            NSUInteger closed = rows.count > 3 ? 3 : rows.count - 1;
            NSButton *one = (NSButton *)Find(view, [NSString stringWithFormat:@"scalar.%lu.disclosure", (unsigned long)closed]);
            one.state = NSControlStateValueOff;
            [controller toggleCodePoint:one];
            for (NSUInteger r = 0; r < rows.count; r++) {
                BOOL open = (r != closed);
                NSButton *disclosure = (NSButton *)Find(view, [NSString stringWithFormat:@"scalar.%lu.disclosure", (unsigned long)r]);
                if ((Find(view, [NSString stringWithFormat:@"scalar.%lu.detail", (unsigned long)r]) != nil) != open || (disclosure.state == NSControlStateValueOn) != open)
                    Fail([NSString stringWithFormat:@"%@ code point %lu is %@ after closing only code point %lu", where, (unsigned long)r, open ? @"closed" : @"open", (unsigned long)closed]);
            }
            if (!(NSHeight(view.frame) < openHeight - 10 && NSHeight(view.frame) > closedHeight + 10))
                Fail([NSString stringWithFormat:@"%@ with one code point closed the popover is %.0f high (closed %.0f, open %.0f)", where, NSHeight(view.frame), closedHeight, openHeight]);
            // Drawn as it first opens (all closed, above) and with some code points open and one closed.
            CheckEverything(controller, [where stringByAppendingString:@" one closed"], images && drawn ? [NSString stringWithFormat:@"%@-single-%@-mixed", language, multiples[i].name] : nil);
            for (NSUInteger r = 0; r < rows.count; r++) {
                NSButton *disclosure = (NSButton *)Find(view, [NSString stringWithFormat:@"scalar.%lu.disclosure", (unsigned long)r]);
                disclosure.state = NSControlStateValueOff;
                [controller toggleCodePoint:disclosure];
            }
            if (fabs(NSHeight(view.frame) - closedHeight) > 0.5) Fail([where stringByAppendingString:@" the popover does not shrink when the code points are closed"]);
        }

        // Several characters: the counts and the code points; a long selection scrolls.
        NSString *lettersFormat = LocalizedStrings[@"%1$@ characters, %2$@ words, %3$@ lines"] ?: @"%1$@ characters, %2$@ words, %3$@ lines";
        NSString *(^Counts)(NSUInteger, NSUInteger, NSUInteger) = ^(NSUInteger c, NSUInteger w, NSUInteger l) {
            return [NSString stringWithFormat:lettersFormat, TSStatusBarFormattedNumber(c), TSStatusBarFormattedNumber(w), TSStatusBarFormattedNumber(l), (int)c, (int)w, (int)l];
        };
        // The numbers the status bar shows for a selection (TSStatusBarCount, as TSSourceStatusBar calls it),
        // and, for the plain cases, the numbers themselves: "あああ" is one word, not none.
        NSString *(^statusBar)(NSString *, NSRange) = ^(NSString *text, NSRange range) {
            TSStatusBarCounts counts = TSStatusBarCountsUnknown();
            TSStatusBarCount(text, @[[NSValue valueWithRange:range]], YES, YES, &counts, nil);
            return Counts(counts.selectedCharacters, counts.selectedWords, counts.selectedLines);
        };
        NSString *(^whole)(NSString *) = ^(NSString *text) { return statusBar(text, NSMakeRange(0, text.length)); };
        NSString *kana = @"\u3042\u3042\u3042", *mixed = @"TeX \U0001F600\n\u845B\U000E0100", *crlf = @"a\r\nb";
        NSString *japaneseText = @"\u543E\u8F29\u306F\u732B\u3067\u3042\u308B\u3002", *englishText = @"The quick brown fox.";
        NSString *emoji = @"\U0001F600\U0001F44D\U0001F3FD \U0001F1EF\U0001F1F5", *combining = @"e\u0301te\u0301", *lines = @"one\ntwo\n\nthree\n";
        struct { NSString *name, *text, *counts, *codePoints; } several[] = {
            {@"kana", kana, Counts(3, 1, 1), @"U+3042  U+3042  U+3042"},
            {@"mixed", mixed, Counts(7, 3, 2), @"U+0054  U+0065  U+0058  U+0020  U+1F600 (U+D83D U+DE00)  U+000A  U+845B  U+E0100 (U+DB40 U+DD00)"},
            {@"crlf", crlf, Counts(3, 2, 2), @"U+0061  U+000D  U+000A  U+0062"},
            {@"japanese", japaneseText, whole(japaneseText), nil},
            {@"english", englishText, Counts(20, 4, 1), nil},
            {@"emoji", emoji, whole(emoji), nil},
            {@"combining", combining, Counts(3, 1, 1), nil},
            {@"lines", lines, Counts(15, 3, 4), nil},
        };
        for (size_t i = 0; i < sizeof several / sizeof several[0]; i++) {
            NSString *where = [NSString stringWithFormat:@"%@ several %@", language, several[i].name];
            TSGlyphPopoverController *controller = [[TSGlyphPopoverController alloc] initWithCharacter:several[i].text];
            NSView *view = controller.view;
            Expect(view, where, @"counts", several[i].counts);
            Expect(view, where, @"counts", whole(several[i].text));
            if (several[i].codePoints) Expect(view, where, @"codePoints", several[i].codePoints);
            NSScrollView *scroll = (NSScrollView *)Find(view, @"codePointsScroll");
            NSTextView *textView = (NSTextView *)Find(view, @"codePoints");
            [textView.layoutManager ensureLayoutForTextContainer:textView.textContainer];
            CGFloat used = NSHeight([textView.layoutManager usedRectForTextContainer:textView.textContainer]);
            if (NSHeight(scroll.frame) + 0.5 < used) Fail([NSString stringWithFormat:@"%@ the code points need %.0f, have %.0f", where, used, NSHeight(scroll.frame)]);
            // No line breaks inside a code point.
            NSUInteger glyphs = textView.layoutManager.numberOfGlyphs;
            for (NSUInteger g = 0; g < glyphs;) {
                NSRange line;
                [textView.layoutManager lineFragmentRectForGlyphAtIndex:g effectiveRange:&line];
                NSRange chars = [textView.layoutManager characterRangeForGlyphRange:line actualGlyphRange:NULL];
                NSString *text = [textView.string substringWithRange:chars];
                NSUInteger opening = [text componentsSeparatedByString:@"("].count, closing = [text componentsSeparatedByString:@")"].count;
                if (![text hasPrefix:@"U+"] || opening != closing)
                    Fail([NSString stringWithFormat:@"%@ a line starts \"%@\"", where, [text substringToIndex:MIN(10u, text.length)]]);
                g = NSMaxRange(line);
            }
            CheckEverything(controller, where, images && i < 2 ? [NSString stringWithFormat:@"%@-several-%@", language, several[i].name] : nil);
        }
        // A selection inside a document, as Character Info gets it: the same numbers as the status bar for that
        // selection, also where it starts or ends inside a word or a cluster.
        NSString *document = [NSString stringWithFormat:@"%@\r\n%@ %@\n%@ %@", japaneseText, englishText, emoji, combining, kana];
        NSRange selections[] = {[document rangeOfString:englishText], [document rangeOfString:@"quick brown"], NSMakeRange(2, 12),
                                NSMakeRange(0, document.length), [document rangeOfString:@"\r\n"], NSMakeRange(document.length - 5, 5)};
        for (size_t s = 0; s < sizeof selections / sizeof selections[0]; s++) {
            NSString *where = [NSString stringWithFormat:@"%@ selection %@", language, NSStringFromRange(selections[s])];
            TSGlyphPopoverController *controller = [[TSGlyphPopoverController alloc] initWithText:document range:selections[s]];
            TSStatusBarCounts counts = TSStatusBarCountsUnknown();
            TSStatusBarCount(document, @[[NSValue valueWithRange:selections[s]]], YES, YES, &counts, nil);
            if (counts.selectedCharacters == 1) {
                if (!Find(controller.view, @"name") || Find(controller.view, @"counts"))
                    Fail([where stringByAppendingString:@" one character for the status bar is not shown as one character"]);
            } else {
                Expect(controller.view, where, @"counts", statusBar(document, selections[s]));
            }
        }
        // Several selected ranges of a text view, as Character Info gets them: the numbers of the status bar for all of
        // them (TSSourceStatusBar counts selectedRanges), and the code points of every range, in order.
        NSTextView *textView = [[NSTextView alloc] initWithFrame:NSMakeRect(0, 0, 400, 200)];
        textView.string = @"one\ntwo\nthree \u3042\u3042 \U0001F600 e\u0301\nfour";
        NSString *shown = textView.string;
        NSArray<NSArray<NSValue *> *> *selections2 = @[
            @[[NSValue valueWithRange:NSMakeRange(0, 3)], [NSValue valueWithRange:NSMakeRange(8, 5)]],   // two lines apart
            @[[NSValue valueWithRange:NSMakeRange(8, 2)], [NSValue valueWithRange:NSMakeRange(11, 2)]],  // the same line
            @[[NSValue valueWithRange:NSMakeRange(2, 7)], [NSValue valueWithRange:NSMakeRange(14, 6)], [NSValue valueWithRange:NSMakeRange(shown.length - 4, 4)]],  // over lines
            @[[NSValue valueWithRange:NSMakeRange(0, 1)], [NSValue valueWithRange:NSMakeRange(4, 1)]],   // one character each
        ];
        for (NSArray<NSValue *> *ranges in selections2) {
            textView.selectedRanges = ranges;
            NSArray<NSValue *> *selected = textView.selectedRanges;
            NSString *where = [NSString stringWithFormat:@"%@ ranges %@", language, [[selected valueForKey:@"description"] componentsJoinedByString:@" "]];
            TSGlyphPopoverController *controller = [[TSGlyphPopoverController alloc] initWithText:shown ranges:selected];
            TSStatusBarCounts counts = TSStatusBarCountsUnknown();
            TSStatusBarCount(shown, selected, YES, YES, &counts, nil);
            Expect(controller.view, where, @"counts", Counts(counts.selectedCharacters, counts.selectedWords, counts.selectedLines));
            NSMutableString *every = [NSMutableString string];
            for (NSValue *value in selected) [every appendString:[shown substringWithRange:value.rangeValue]];
            TSGlyphPopoverController *together = [[TSGlyphPopoverController alloc] initWithCharacter:every];
            Expect(controller.view, where, @"codePoints", Text(together.view, @"codePoints"));
        }
        if (![Text([[TSGlyphPopoverController alloc] initWithText:shown ranges:selections2[0]].view, @"counts") isEqualToString:Counts(8, 2, 2)])
            Fail([language stringByAppendingString:@" two ranges are not counted as 8 characters, 2 words and 2 lines"]);
        // CR LF is one character, as in the status bar and in CotEditor.
        TSGlyphPopoverController *crlfController = [[TSGlyphPopoverController alloc] initWithCharacter:@"\r\n"];
        Expect(crlfController.view, [language stringByAppendingString:@" CR LF"], @"name", consisting(2));
        // A long combining sequence is one character; its number of code points is written as the status bar writes numbers.
        NSString *longCombining = [@"a" stringByPaddingToLength:1234 withString:@"\u0301" startingAtIndex:0];
        Expect([[TSGlyphPopoverController alloc] initWithCharacter:longCombining].view, [language stringByAppendingString:@" long combining sequence"], @"name", consisting(1234));
        Expect(crlfController.view, [language stringByAppendingString:@" CR LF"], @"scalar.1.name", @"LINE FEED");
        if ([[TSGlyphPopoverController alloc] initWithText:document range:NSMakeRange(3, 0)]) Fail(@"an empty selection in a document makes a popover");
        NSString *many = [@"" stringByPaddingToLength:2000 withString:@"あ" startingAtIndex:0];
        TSGlyphPopoverController *controller = [[TSGlyphPopoverController alloc] initWithCharacter:many];
        NSScrollView *scroll = (NSScrollView *)Find(controller.view, @"codePointsScroll");
        if (NSHeight(scroll.frame) > 300.5 || !scroll.hasVerticalScroller)
            Fail([NSString stringWithFormat:@"%@ 2000 characters: the code points are %.0f high, %@scrolling", language, NSHeight(scroll.frame), scroll.hasVerticalScroller ? @"" : @"not "]);
        CheckSize(controller, [language stringByAppendingString:@" 2000 characters"]);
        if ([[TSGlyphPopoverController alloc] initWithCharacter:@""]) Fail(@"an empty selection makes a popover");
    }
    printf("%s: %lu languages, %d layout problems, %d failures\n", problems || failures ? "FAIL" : "PASS", (unsigned long)entries.count, problems, failures);
    return problems || failures ? 1 : 0;
}}
