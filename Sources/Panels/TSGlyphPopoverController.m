/*
 ==============================================================================
 TSGlyphPopoverController
 Created on 2014-08-24 by Yusuke Terada

 TSGlyphPopoverController is based on CEGlyphPopoverController.

 CotEditor
 http://coteditor.github.io

 Created on 2014-05-01 by 1024jp
 encoding="UTF-8"
 ------------------------------------------------------------------------------

 © 2014-2015 1024jp

 This program is free software; you can redistribute it and/or modify it under
 the terms of the GNU General Public License as published by the Free Software
 Foundation; either version 2 of the License, or (at your option) any later
 version.

 This program is distributed in the hope that it will be useful, but WITHOUT
 ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
 FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details.

 You should have received a copy of the GNU General Public License along with
 this program; if not, write to the Free Software Foundation, Inc., 59 Temple
 Place - Suite 330, Boston, MA  02111-1307, USA.

 ==============================================================================
 */

// One character is shown as CotEditor's character inspector shows it: the glyph,
// the name, and a table of the code point, block, general category and the
// Unicode version that added it. A character of several code points lists them,
// each with its block and category under a disclosure triangle. A selection of
// several characters shows their number, words and lines, and their code points.
// The properties come from ICU (unicode/uchar.h of the SDK).

#import "TSGlyphPopoverController.h"
#import "TSUnicodeBlockNames.h"
#import "TSStatusBarCounting.h"
#import <unicode/uchar.h>

static const CGFloat kInset = 14;
static const CGFloat kGlyphFontSize = 64;
static const CGFloat kGlyphMinWidth = 64;
static const CGFloat kScalarGlyphFontSize = 28;
static const CGFloat kScalarGlyphMinWidth = 30;
// Longer names and values wrap at these widths, so that the popover stays narrow.
static const CGFloat kNameMaxWidth = 360;
static const CGFloat kScalarNameMaxWidth = 260;
static const CGFloat kValueMaxWidth = 300;
static const CGFloat kTableColumnSpacing = 6;
// The selection of several characters.
static const CGFloat kMultiWidth = 320;
static const CGFloat kMultiMaxCodePointsHeight = 300;

#pragma mark - Unicode properties

static NSString *CodePointString(UTF32Char c)
{
    return [NSString stringWithFormat:@"U+%04X", (unsigned)c];
}

/// "(U+D83D U+DE00)" for a code point that UTF-16 writes as a surrogate pair.
static NSString *SurrogatesString(UTF32Char c)
{
    if (c < 0x10000 || c > 0x10FFFF)
        return nil;
    UniChar surrogates[2];
    CFStringGetSurrogatePairForLongCharacter(c, surrogates);
    return [NSString stringWithFormat:@"(U+%04X U+%04X)", surrogates[0], surrogates[1]];
}

/// The names of the control characters (NameAliases.txt), which have no Unicode name.
static NSString *ControlCharacterName(UTF32Char c)
{
    static NSString *const c0[] = {
        @"NULL", @"START OF HEADING", @"START OF TEXT", @"END OF TEXT", @"END OF TRANSMISSION", @"ENQUIRY",
        @"ACKNOWLEDGE", @"BELL", @"BACKSPACE", @"HORIZONTAL TABULATION", @"LINE FEED", @"VERTICAL TABULATION",
        @"FORM FEED", @"CARRIAGE RETURN", @"SHIFT OUT", @"SHIFT IN", @"DATA LINK ESCAPE", @"DEVICE CONTROL ONE",
        @"DEVICE CONTROL TWO", @"DEVICE CONTROL THREE", @"DEVICE CONTROL FOUR", @"NEGATIVE ACKNOWLEDGE",
        @"SYNCHRONOUS IDLE", @"END OF TRANSMISSION BLOCK", @"CANCEL", @"END OF MEDIUM", @"SUBSTITUTE", @"ESCAPE",
        @"FILE SEPARATOR", @"GROUP SEPARATOR", @"RECORD SEPARATOR", @"UNIT SEPARATOR",
    };
    static NSString *const c1[] = {
        @"PADDING CHARACTER", @"HIGH OCTET PRESET", @"BREAK PERMITTED HERE", @"NO BREAK HERE", @"INDEX",
        @"NEXT LINE", @"START OF SELECTED AREA", @"END OF SELECTED AREA", @"CHARACTER TABULATION SET",
        @"CHARACTER TABULATION WITH JUSTIFICATION", @"LINE TABULATION SET", @"PARTIAL LINE FORWARD",
        @"PARTIAL LINE BACKWARD", @"REVERSE LINE FEED", @"SINGLE SHIFT TWO", @"SINGLE SHIFT THREE",
        @"DEVICE CONTROL STRING", @"PRIVATE USE ONE", @"PRIVATE USE TWO", @"SET TRANSMIT STATE",
        @"CANCEL CHARACTER", @"MESSAGE WAITING", @"START OF PROTECTED AREA", @"END OF PROTECTED AREA",
        @"START OF STRING", @"SINGLE GRAPHIC CHARACTER INTRODUCER", @"SINGLE CHARACTER INTRODUCER",
        @"CONTROL SEQUENCE INTRODUCER", @"STRING TERMINATOR", @"OPERATING SYSTEM COMMAND", @"PRIVACY MESSAGE",
        @"APPLICATION PROGRAM COMMAND",
    };
    if (c < 0x20)
        return c0[c];
    if (c == 0x7F)
        return @"DELETE";
    if (c >= 0x80 && c <= 0x9F)
        return c1[c - 0x80];
    return nil;
}

static NSString *ICUName(UTF32Char c, UCharNameChoice choice)
{
    char buffer[256];
    UErrorCode error = U_ZERO_ERROR;
    int32_t length = u_charName((UChar32)c, choice, buffer, sizeof buffer, &error);
    if (U_FAILURE(error) || length <= 0)
        return nil;
    return [[NSString alloc] initWithBytes:buffer length:(NSUInteger)length encoding:NSASCIIStringEncoding];
}

/// The Unicode name (its correction, where Unicode corrected it), or the name of a
/// control character, or nil, as for a private-use or unassigned code point.
static NSString *ScalarName(UTF32Char c)
{
    if (c > 0x10FFFF)
        return nil;
    return ICUName(c, U_CHAR_NAME_ALIAS) ?: ICUName(c, U_UNICODE_CHAR_NAME) ?: ControlCharacterName(c);
}

/// What a variation selector or an emoji skin tone modifier does to the code point before it.
static NSString *VariantDescription(UTF32Char c)
{
    switch (c) {
        case 0xFE0E: return NSLocalizedString(@"Text Style", @"Character Info: the variation selector that draws the character as text");
        case 0xFE0F: return NSLocalizedString(@"Emoji Style", @"Character Info: the variation selector that draws the character as emoji");
        case 0x1F3FB: return NSLocalizedString(@"Skin Tone I-II", @"Character Info: emoji modifier, light skin tone");
        case 0x1F3FC: return NSLocalizedString(@"Skin Tone III", @"Character Info: emoji modifier, medium-light skin tone");
        case 0x1F3FD: return NSLocalizedString(@"Skin Tone IV", @"Character Info: emoji modifier, medium skin tone");
        case 0x1F3FE: return NSLocalizedString(@"Skin Tone V", @"Character Info: emoji modifier, medium-dark skin tone");
        case 0x1F3FF: return NSLocalizedString(@"Skin Tone VI", @"Character Info: emoji modifier, dark skin tone");
    }
    if (c <= 0x10FFFF && u_hasBinaryProperty((UChar32)c, UCHAR_VARIATION_SELECTOR))
        return NSLocalizedString(@"Variant", @"Character Info: a variation selector");
    return nil;
}

/// The control picture (U+2400...) that stands for an invisible control character or the space.
static NSString *PictureCharacter(UTF32Char c)
{
    if (c <= 0x20)
        return [NSString stringWithFormat:@"%C", (unichar)(0x2400 + c)];
    if (c == 0x7F)
        return @"␡";
    return nil;
}

/// "Lowercase Letter (Ll)": the general category, by its long and short names.
static NSString *CategoryString(UTF32Char c)
{
    int8_t category = u_charType((UChar32)c);
    const char *longName = u_getPropertyValueName(UCHAR_GENERAL_CATEGORY, category, U_LONG_PROPERTY_NAME);
    const char *shortName = u_getPropertyValueName(UCHAR_GENERAL_CATEGORY, category, U_SHORT_PROPERTY_NAME);
    if (!longName || !shortName)
        return nil;
    NSString *name = [@(longName) stringByReplacingOccurrencesOfString:@"_" withString:@" "];
    return [NSString stringWithFormat:@"%@ (%s)", name, shortName];
}

/// "Unicode 1.1": the version of Unicode that added the code point, or nil if none did.
static NSString *VersionString(UTF32Char c)
{
    UVersionInfo age;
    u_charAge((UChar32)c, age);
    if (age[0] == 0 && age[1] == 0)
        return nil;
    return [NSString stringWithFormat:@"Unicode %d.%d", age[0], age[1]];
}

static NSArray<NSNumber *> *CodePoints(NSString *string)
{
    NSMutableArray<NSNumber *> *codePoints = [NSMutableArray array];
    NSUInteger length = string.length;
    for (NSUInteger i = 0; i < length; i++) {
        unichar c = [string characterAtIndex:i];
        if (CFStringIsSurrogateHighCharacter(c) && i + 1 < length && CFStringIsSurrogateLowCharacter([string characterAtIndex:i + 1])) {
            [codePoints addObject:@(CFStringGetLongCharacterForSurrogatePair(c, [string characterAtIndex:i + 1]))];
            i++;
        } else {
            [codePoints addObject:@(c)];
        }
    }
    return codePoints;
}

static NSString *StringOfCodePoint(UTF32Char c)
{
    if (c > 0xFFFF && c <= 0x10FFFF) {
        UniChar surrogates[2];
        CFStringGetSurrogatePairForLongCharacter(c, surrogates);
        return [NSString stringWithCharacters:surrogates length:2];
    }
    unichar single = (unichar)c;
    return [NSString stringWithCharacters:&single length:1];
}

#pragma mark - Views

/// The large glyph, centered on what it draws, as CotEditor's CharacterField does:
/// a tall stack of marks is not cut off by the line height.
@interface TSGlyphPopoverGlyphView : NSView
@property (nonatomic, copy) NSAttributedString *glyph;
@property (nonatomic) BOOL bordered;
@end

@implementation TSGlyphPopoverGlyphView

- (BOOL)isFlipped
{
    return YES;
}

- (NSRect)typographicBounds
{
    return [self.glyph boundingRectWithSize:NSZeroSize options:0];
}

- (NSRect)inkBounds
{
    return [self.glyph boundingRectWithSize:NSZeroSize options:NSStringDrawingUsesDeviceMetrics];
}

- (NSSize)intrinsicContentSize
{
    NSRect ink = self.inkBounds;
    return NSMakeSize(ceil(NSWidth(ink)), ceil(MAX(NSHeight(ink), NSHeight(self.typographicBounds))));
}

- (void)drawRect:(NSRect)dirtyRect
{
    if (self.bordered) {
        [NSColor.separatorColor setStroke];
        [NSBezierPath strokeRect:NSInsetRect(self.bounds, 0.5, 0.5)];
    }
    NSRect ink = self.inkBounds, typographic = self.typographicBounds;
    NSPoint point;
    if (NSIsEmptyRect(ink)) {
        // Nothing to center on, such as a space: center the line.
        point = NSMakePoint(NSMidX(self.bounds) - NSWidth(typographic) / 2, NSMidY(self.bounds) - NSHeight(typographic) / 2);
    } else {
        // The top left of the line, from the top left of the ink centered in the view.
        point = NSMakePoint(NSMidX(self.bounds) - NSWidth(ink) / 2 - NSMinX(ink),
                            NSMidY(self.bounds) - NSHeight(ink) / 2 + NSMaxY(ink) - NSMaxY(typographic));
    }
    [self.glyph drawAtPoint:point];
}

- (BOOL)isAccessibilityElement { return YES; }
- (NSAccessibilityRole)accessibilityRole { return NSAccessibilityStaticTextRole; }
- (id)accessibilityValue { return self.glyph.string; }

@end


/// "deprecated", outlined, after the code point of a character that Unicode deprecates.
@interface TSGlyphPopoverBadge : NSView
@property (nonatomic, strong) NSTextField *label;
@end

@implementation TSGlyphPopoverBadge

- (instancetype)initWithTitle:(NSString *)title font:(NSFont *)font
{
    if ((self = [super initWithFrame:NSZeroRect])) {
        _label = [NSTextField labelWithString:title];
        _label.font = font;
        _label.textColor = NSColor.secondaryLabelColor;
        _label.translatesAutoresizingMaskIntoConstraints = NO;
        [self addSubview:_label];
        [NSLayoutConstraint activateConstraints:@[
            [_label.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:3],
            [_label.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-3],
            [_label.topAnchor constraintEqualToAnchor:self.topAnchor],
            [_label.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
        ]];
    }
    return self;
}

- (NSView *)viewForLastBaselineLayout { return self.label; }
- (NSView *)viewForFirstBaselineLayout { return self.label; }

- (void)drawRect:(NSRect)dirtyRect
{
    NSBezierPath *outline = [NSBezierPath bezierPathWithRoundedRect:NSInsetRect(self.bounds, 0.5, 0.5) xRadius:3 yRadius:3];
    [NSColor.secondaryLabelColor setStroke];
    [outline stroke];
}

@end


/// The code points of several characters, broken into lines between them, not inside "U+...".
@interface TSGlyphPopoverUnicodesTextStorage : NSTextStorage
@end

@implementation TSGlyphPopoverUnicodesTextStorage
{
    NSMutableAttributedString *contents;
}

- (instancetype)init
{
    if ((self = [super init]))
        contents = [NSMutableAttributedString new];
    return self;
}

- (instancetype)initWithAttributedString:(NSAttributedString *)string
{
    if ((self = [self init]))
        [contents setAttributedString:string];
    return self;
}

- (NSString *)string
{
    return contents.string;
}

- (NSDictionary<NSAttributedStringKey, id> *)attributesAtIndex:(NSUInteger)location effectiveRange:(NSRangePointer)range
{
    return [contents attributesAtIndex:location effectiveRange:range];
}

- (void)replaceCharactersInRange:(NSRange)range withString:(NSString *)string
{
    [contents replaceCharactersInRange:range withString:string];
    [self edited:NSTextStorageEditedCharacters range:range changeInLength:(NSInteger)string.length - (NSInteger)range.length];
}

- (void)setAttributes:(NSDictionary<NSAttributedStringKey, id> *)attributes range:(NSRange)range
{
    [contents setAttributes:attributes range:range];
    [self edited:NSTextStorageEditedAttributes range:range changeInLength:0];
}

// Lines break only after the two spaces between code points, so that "U+1F600 (U+D83D U+DE00)" stays on one line.
- (NSUInteger)lineBreakBeforeIndex:(NSUInteger)index withinRange:(NSRange)range
{
    NSRange separator = [self.string rangeOfString:@"  " options:NSBackwardsSearch range:NSMakeRange(range.location, index - range.location)];
    if (separator.location != NSNotFound && NSMaxRange(separator) > range.location)
        return NSMaxRange(separator);
    return [super lineBreakBeforeIndex:index withinRange:range];
}

@end

#pragma mark - Building the views

/// The locale for the counts and the plural forms: the current one, except when TeXShop runs in a localization
/// for a region of its own, such as Portuguese of Portugal, and the region chosen in System Settings is another.
/// Then the localization's region gives the plural forms ("0 palavras", not the Brazilian "0 palavra"). The counts
/// are written by the status bar's formatter, in the current locale.
static NSLocale *CountsLocale(void)
{
    NSLocale *current = NSLocale.currentLocale;
    NSString *localization = NSBundle.mainBundle.preferredLocalizations.firstObject;
    NSString *region = localization ? [NSLocale componentsFromLocaleIdentifier:localization][NSLocaleCountryCode] : nil;
    if (region.length && ![region isEqualToString:current.countryCode ?: @""])
        return [NSLocale localeWithLocaleIdentifier:localization];
    return current;
}

static NSFont *SmallFont(void)
{
    return [NSFont systemFontOfSize:NSFont.smallSystemFontSize];
}

static NSFont *CodePointFont(void)
{
    return [NSFont monospacedDigitSystemFontOfSize:NSFont.smallSystemFontSize weight:NSFontWeightRegular];
}

/// Makes a label show its whole text: on one line, or wrapped at maxWidth when longer.
static void FitLabel(NSTextField *field, CGFloat maxWidth)
{
    NSFont *font = field.font ?: [NSFont systemFontOfSize:NSFont.systemFontSize];
    CGFloat width = [field.stringValue sizeWithAttributes:@{NSFontAttributeName: font}].width;
    BOOL wraps = (width > maxWidth);
    field.lineBreakMode = wraps ? NSLineBreakByWordWrapping : NSLineBreakByClipping;
    field.usesSingleLineMode = !wraps;
    field.cell.scrollable = !wraps;
    field.cell.wraps = wraps;
    field.maximumNumberOfLines = wraps ? 0 : 1;
    field.preferredMaxLayoutWidth = wraps ? maxWidth : 0;
    [field invalidateIntrinsicContentSize];
}

static NSTextField *Label(NSString *text, NSFont *font, NSColor *color, CGFloat maxWidth, BOOL selectable, NSString *identifier)
{
    NSTextField *field = [NSTextField labelWithString:text];
    field.font = font;
    field.textColor = color;
    field.selectable = selectable;
    field.identifier = identifier;
    field.translatesAutoresizingMaskIntoConstraints = NO;
    FitLabel(field, maxWidth);
    [field setContentCompressionResistancePriority:NSLayoutPriorityRequired forOrientation:NSLayoutConstraintOrientationHorizontal];
    [field setContentCompressionResistancePriority:NSLayoutPriorityRequired forOrientation:NSLayoutConstraintOrientationVertical];
    return field;
}

static NSAttributedString *GlyphString(NSString *text, CGFloat size, NSColor *color)
{
    NSFont *system = [NSFont systemFontOfSize:size];
    NSFontDescriptor *serif = [system.fontDescriptor fontDescriptorWithDesign:NSFontDescriptorSystemDesignSerif];
    NSFont *font = (serif ? [NSFont fontWithDescriptor:serif size:size] : nil) ?: system;
    return [[NSAttributedString alloc] initWithString:text attributes:@{NSFontAttributeName: font, NSForegroundColorAttributeName: color}];
}

static NSStackView *Stack(NSUserInterfaceLayoutOrientation orientation, NSArray<NSView *> *views, CGFloat spacing, NSLayoutAttribute alignment)
{
    NSStackView *stack = [NSStackView stackViewWithViews:views];
    stack.orientation = orientation;
    stack.spacing = spacing;
    stack.alignment = alignment;
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    return stack;
}

static TSGlyphPopoverGlyphView *GlyphView(NSString *text, CGFloat size, NSColor *color, CGFloat minWidth, NSString *identifier)
{
    TSGlyphPopoverGlyphView *glyph = [TSGlyphPopoverGlyphView new];
    glyph.glyph = GlyphString(text, size, color);
    glyph.identifier = identifier;
    glyph.translatesAutoresizingMaskIntoConstraints = NO;
    [glyph.widthAnchor constraintGreaterThanOrEqualToConstant:minWidth].active = YES;
    for (NSNumber *orientation in @[@(NSLayoutConstraintOrientationHorizontal), @(NSLayoutConstraintOrientationVertical)]) {
        [glyph setContentHuggingPriority:NSLayoutPriorityRequired forOrientation:orientation.integerValue];
        [glyph setContentCompressionResistancePriority:NSLayoutPriorityRequired forOrientation:orientation.integerValue];
    }
    return glyph;
}

#pragma mark - Controller

@interface TSGlyphPopoverController ()
@property (nonatomic, copy) NSString *character;
@property (nonatomic) BOOL singleLetter;
// The selection counted as the status bar under the source counts it.
@property (nonatomic) TSStatusBarCounts counts;
@property (nonatomic, weak) NSPopover *popover;
// What a click changed, kept while the views are built again: the code points opened
// ("scalar.N.") and the block names shown as Unicode names them (the identifiers of their fields).
@property (nonatomic, strong) NSMutableSet<NSString *> *openCodePoints;
@property (nonatomic, strong) NSMutableSet<NSString *> *unicodeBlockNames;
@end

@implementation TSGlyphPopoverController

- (instancetype)initWithText:(NSString *)text ranges:(NSArray<NSValue *> *)ranges
{
    // Characters, words and lines as the status bar counts the selection (TSStatusBarCount): each range,
    // and the lines that the ranges touch, so that both show the same numbers, also for several ranges.
    TSStatusBarCounts counts = TSStatusBarCountsUnknown();
    NSUInteger characters = 0, words = 0;
    NSMutableString *selected = [NSMutableString string];
    for (NSValue *value in ranges) {
        NSRange range = value.rangeValue;
        if (range.location > text.length || range.length > text.length - range.location)
            return nil;
        if (range.length == 0)
            continue;
        characters += TSStatusBarCharacterCount(text, range, nil);
        words += TSStatusBarWordCount(text, range, nil);
        // What is shown is what is counted: the code points of every range, in order.
        [selected appendString:[text substringWithRange:range]];
    }
    if (characters == 0)
        return nil;
    counts.selectedCharacters = characters;
    counts.selectedWords = words;
    counts.selectedLines = TSStatusBarSelectedLineCount(text, ranges);
    if ((self = [super initWithNibName:nil bundle:nil])) {
        _character = [selected copy];
        _counts = counts;
        _singleLetter = (characters == 1);
        _openCodePoints = [NSMutableSet set];
        _unicodeBlockNames = [NSMutableSet set];
    }
    return self;
}

- (instancetype)initWithText:(NSString *)text range:(NSRange)range
{
    return [self initWithText:text ranges:@[[NSValue valueWithRange:range]]];
}

- (instancetype)initWithCharacter:(NSString *)character
{
    return [self initWithText:character range:NSMakeRange(0, character.length)];
}

/// The table of a code point: the headings right-aligned in the secondary color, the values in the label color.
- (NSGridView *)tableForCodePoint:(UTF32Char)c prefix:(NSString *)prefix codePoint:(BOOL)withCodePoint version:(BOOL)withVersion
{
    NSFont *font = SmallFont();
    // The values wrap where the table would be wider than the name may be.
    CGFloat headingWidth = 0;
    for (NSString *heading in @[NSLocalizedString(@"Code Point:", nil), NSLocalizedString(@"Block:", nil), NSLocalizedString(@"Category:", nil), NSLocalizedString(@"Version:", nil)])
        headingWidth = MAX(headingWidth, ceil([heading sizeWithAttributes:@{NSFontAttributeName: font}].width));
    CGFloat valueMaxWidth = MIN(kValueMaxWidth, kNameMaxWidth - headingWidth - kTableColumnSpacing);
    NSMutableArray<NSArray<NSView *> *> *rows = [NSMutableArray array];
    void (^addRow)(NSString *, NSString *, NSView *) = ^(NSString *key, NSString *heading, NSView *value) {
        NSTextField *label = Label(heading, font, NSColor.secondaryLabelColor, CGFLOAT_MAX, NO, [prefix stringByAppendingFormat:@"%@.label", key]);
        label.alignment = NSTextAlignmentRight;
        [rows addObject:@[label, value]];
    };

    if (withCodePoint) {
        NSString *codePoint = CodePointString(c);
        NSString *surrogates = SurrogatesString(c);
        if (surrogates)
            codePoint = [NSString stringWithFormat:@"%@ %@", codePoint, surrogates];
        NSView *value = Label(codePoint, CodePointFont(), NSColor.labelColor, CGFLOAT_MAX, YES, [prefix stringByAppendingString:@"codePoint"]);
        if (c <= 0x10FFFF && u_hasBinaryProperty((UChar32)c, UCHAR_DEPRECATED)) {
            TSGlyphPopoverBadge *badge = [[TSGlyphPopoverBadge alloc] initWithTitle:NSLocalizedString(@"deprecated", @"Character Info: badge after the code point of a character that Unicode deprecates") font:font];
            badge.identifier = [prefix stringByAppendingString:@"deprecated"];
            badge.translatesAutoresizingMaskIntoConstraints = NO;
            value = Stack(NSUserInterfaceLayoutOrientationHorizontal, @[value, badge], 6, NSLayoutAttributeLastBaseline);
        }
        addRow(@"codePoint", NSLocalizedString(@"Code Point:", @"Character Info: heading of the code point, such as U+0061"), value);
    }

    NSString *block = TSUnicodeBlockName(c);
    NSTextField *blockField;
    if (block) {
        NSString *localized = TSLocalizedUnicodeBlockName(block), *identifier = [prefix stringByAppendingString:@"block"];
        // As in CotEditor, a click shows the name of Unicode, and another the translation again.
        BOOL unicodeName = [self.unicodeBlockNames containsObject:identifier];
        blockField = Label(unicodeName ? block : localized, font, NSColor.labelColor, valueMaxWidth, NO, identifier);
        if (![localized isEqualToString:block]) {
            blockField.toolTip = unicodeName ? localized : block;
            [blockField addGestureRecognizer:[[NSClickGestureRecognizer alloc] initWithTarget:self action:@selector(toggleBlockName:)]];
        }
    } else {
        blockField = Label(NSLocalizedString(@"No Block", @"Character Info: the code point is in no Unicode block"),
                           font, NSColor.secondaryLabelColor, valueMaxWidth, NO, [prefix stringByAppendingString:@"block"]);
    }
    addRow(@"block", NSLocalizedString(@"Block:", @"Character Info: heading of the Unicode block, such as Basic Latin"), blockField);

    NSString *category = CategoryString(c);
    if (category)
        addRow(@"category", NSLocalizedString(@"Category:", @"Character Info: heading of the general category, such as Lowercase Letter (Ll)"),
               Label(category, font, NSColor.labelColor, valueMaxWidth, YES, [prefix stringByAppendingString:@"category"]));

    NSString *version = withVersion ? VersionString(c) : nil;
    if (version)
        addRow(@"version", NSLocalizedString(@"Version:", @"Character Info: heading of the Unicode version that added the character, such as Unicode 1.1"),
               Label(version, font, NSColor.labelColor, valueMaxWidth, YES, [prefix stringByAppendingString:@"version"]));

    NSGridView *grid = [NSGridView gridViewWithViews:rows];
    grid.translatesAutoresizingMaskIntoConstraints = NO;
    grid.rowSpacing = 3;
    grid.columnSpacing = kTableColumnSpacing;
    grid.rowAlignment = NSGridRowAlignmentLastBaseline;
    [grid columnAtIndex:0].xPlacement = NSGridCellPlacementTrailing;
    [grid columnAtIndex:1].xPlacement = NSGridCellPlacementLeading;
    // As wide as its columns, at the leading edge below the name.
    [grid setContentHuggingPriority:NSLayoutPriorityDefaultHigh + 1 forOrientation:NSLayoutConstraintOrientationHorizontal];
    return grid;
}

- (void)toggleBlockName:(NSClickGestureRecognizer *)click
{
    NSString *identifier = click.view.identifier;
    if ([self.unicodeBlockNames containsObject:identifier])
        [self.unicodeBlockNames removeObject:identifier];
    else
        [self.unicodeBlockNames addObject:identifier];
    [self rebuild];
}

/// A row of the code points of a character: the disclosure triangle, the code point and its name;
/// opened, the glyph of the code point with its block and category.
- (NSView *)rowForCodePoint:(UTF32Char)c index:(NSUInteger)index
{
    NSString *prefix = [NSString stringWithFormat:@"scalar.%lu.", (unsigned long)index];
    BOOL open = [self.openCodePoints containsObject:prefix];
    NSButton *disclosure = [NSButton buttonWithTitle:@"" target:self action:@selector(toggleCodePoint:)];
    disclosure.bezelStyle = NSBezelStyleDisclosure;
    [disclosure setButtonType:NSButtonTypePushOnPushOff];
    disclosure.state = open ? NSControlStateValueOn : NSControlStateValueOff;
    disclosure.controlSize = NSControlSizeSmall;
    disclosure.identifier = [prefix stringByAppendingString:@"disclosure"];
    disclosure.translatesAutoresizingMaskIntoConstraints = NO;

    NSTextField *codePointField = Label(CodePointString(c), CodePointFont(), NSColor.labelColor, CGFLOAT_MAX, YES, [prefix stringByAppendingString:@"codePoint"]);
    [codePointField.widthAnchor constraintGreaterThanOrEqualToConstant:44].active = YES;
    NSMutableArray<NSView *> *header = [NSMutableArray arrayWithObjects:disclosure, codePointField, nil];
    NSString *surrogates = SurrogatesString(c);
    if (surrogates)
        [header addObject:Label(surrogates, CodePointFont(), NSColor.secondaryLabelColor, CGFLOAT_MAX, YES, [prefix stringByAppendingString:@"surrogates"])];
    NSString *name = ScalarName(c);
    [header addObject:name ? Label(name, [NSFont systemFontOfSize:NSFont.smallSystemFontSize weight:NSFontWeightMedium], NSColor.labelColor, kScalarNameMaxWidth, YES, [prefix stringByAppendingString:@"name"])
                           : Label(NSLocalizedString(@"Unknown", @"Character Info: the character has no Unicode name"), SmallFont(), NSColor.secondaryLabelColor, CGFLOAT_MAX, NO, [prefix stringByAppendingString:@"name"])];
    NSStackView *headerStack = Stack(NSUserInterfaceLayoutOrientationHorizontal, header, 4, NSLayoutAttributeFirstBaseline);
    if (!open)
        return headerStack;

    NSString *picture = PictureCharacter(c);
    TSGlyphPopoverGlyphView *glyph = GlyphView(picture ?: StringOfCodePoint(c), kScalarGlyphFontSize, picture ? NSColor.tertiaryLabelColor : NSColor.labelColor,
                                               kScalarGlyphMinWidth, [prefix stringByAppendingString:@"glyph"]);
    glyph.bordered = YES;
    NSGridView *table = [self tableForCodePoint:c prefix:prefix codePoint:NO version:NO];
    NSStackView *detail = Stack(NSUserInterfaceLayoutOrientationHorizontal, @[glyph, table], 8, NSLayoutAttributeTop);
    detail.identifier = [prefix stringByAppendingString:@"detail"];
    detail.edgeInsets = NSEdgeInsetsMake(2, 20, 6, 0);
    return Stack(NSUserInterfaceLayoutOrientationVertical, @[headerStack, detail], 0, NSLayoutAttributeLeading);
}

- (void)toggleCodePoint:(NSButton *)disclosure
{
    NSString *prefix = [disclosure.identifier substringToIndex:disclosure.identifier.length - @"disclosure".length];
    if (disclosure.state == NSControlStateValueOn)
        [self.openCodePoints addObject:prefix];
    else
        [self.openCodePoints removeObject:prefix];
    [self rebuild];
}

- (NSView *)singleCharacterView
{
    NSArray<NSNumber *> *codePoints = CodePoints(self.character);
    UTF32Char first = codePoints.firstObject.unsignedIntValue;
    NSString *variant = (codePoints.count == 2) ? VariantDescription(codePoints[1].unsignedIntValue) : nil;
    BOOL complex = (codePoints.count > 1 && !variant);

    // The glyph, or the picture of an invisible control character or space.
    NSString *picture = (codePoints.count == 1) ? PictureCharacter(first) : nil;
    NSView *glyph = GlyphView(picture ?: self.character, kGlyphFontSize, picture ? NSColor.tertiaryLabelColor : NSColor.labelColor, kGlyphMinWidth, @"glyph");

    // The name of the code point, with what a variation selector or skin tone adds,
    // or the number of code points of a character made of several.
    NSTextField *nameField;
    NSString *name = ScalarName(first);
    if (complex) {
        // The number as the status bar writes it (%1$@), and again for the plural form (%2$#@…@ in Localizable.stringsdict).
        NSString *consistingFormat = NSLocalizedString(@"<a character consisting of %1$@ code points>", @"Character Info: the name line of a character made of several code points, such as an accented letter or an emoji sequence");
        name = [[NSString alloc] initWithFormat:consistingFormat locale:CountsLocale(), TSStatusBarFormattedNumber(codePoints.count), (int)codePoints.count];
        nameField = Label(name, [NSFont systemFontOfSize:NSFont.systemFontSize], NSColor.labelColor, kNameMaxWidth, YES, @"name");
    } else if (name) {
        if (variant)
            name = [NSString stringWithFormat:@"%@ (%@)", name, variant];
        nameField = Label(name, [NSFont systemFontOfSize:NSFont.systemFontSize weight:NSFontWeightSemibold], NSColor.labelColor, kNameMaxWidth, YES, @"name");
    } else {
        nameField = Label(NSLocalizedString(@"Unknown", @"Character Info: the character has no Unicode name"),
                          [NSFont systemFontOfSize:NSFont.systemFontSize], NSColor.secondaryLabelColor, kNameMaxWidth, NO, @"name");
    }

    NSStackView *details = Stack(NSUserInterfaceLayoutOrientationVertical, @[nameField], 0, NSLayoutAttributeLeading);
    if (!complex) {
        [details addArrangedSubview:[self tableForCodePoint:first prefix:@"" codePoint:YES version:YES]];
        [details setCustomSpacing:4 afterView:nameField];
    }
    if (codePoints.count > 1) {
        NSMutableArray<NSView *> *rows = [NSMutableArray array];
        [codePoints enumerateObjectsUsingBlock:^(NSNumber *codePoint, NSUInteger index, BOOL *stop) {
            [rows addObject:[self rowForCodePoint:codePoint.unsignedIntValue index:index]];
        }];
        // A little room between the rows, so that their lines of text do not touch.
        NSStackView *list = Stack(NSUserInterfaceLayoutOrientationVertical, rows, 1, NSLayoutAttributeLeading);
        list.identifier = @"scalars";
        NSView *last = details.arrangedSubviews.lastObject;
        if (last)
            [details setCustomSpacing:6 afterView:last];
        [details addArrangedSubview:list];
    }

    return Stack(NSUserInterfaceLayoutOrientationHorizontal, @[glyph, details], 8, NSLayoutAttributeTop);
}

- (NSView *)multipleCharactersView
{
    NSString *character = self.character;
    // The numbers as the status bar writes them (%1$@ to %3$@), and the same numbers for the plural forms
    // (%4$#@…@ to %6$#@…@ in Localizable.stringsdict), which the locale of the language chooses.
    // The format names only the first three in languages without plural forms, so it is not a literal here.
    TSStatusBarCounts selectedCounts = self.counts;
    NSString *countsFormat = NSLocalizedString(@"%1$@ characters, %2$@ words, %3$@ lines", @"Character Info: the characters, words and lines of the selection, counted and written as the status bar does");
    NSString *counts = [[NSString alloc] initWithFormat:countsFormat locale:CountsLocale(),
                        TSStatusBarFormattedNumber(selectedCounts.selectedCharacters), TSStatusBarFormattedNumber(selectedCounts.selectedWords), TSStatusBarFormattedNumber(selectedCounts.selectedLines),
                        (int)selectedCounts.selectedCharacters, (int)selectedCounts.selectedWords, (int)selectedCounts.selectedLines];
    NSTextField *countsField = Label(counts, [NSFont systemFontOfSize:NSFont.systemFontSize], NSColor.labelColor, kMultiWidth, YES, @"counts");

    NSMutableArray<NSString *> *list = [NSMutableArray array];
    for (NSNumber *codePoint in CodePoints(character)) {
        UTF32Char c = codePoint.unsignedIntValue;
        NSString *surrogates = SurrogatesString(c);
        [list addObject:surrogates ? [NSString stringWithFormat:@"%@ %@", CodePointString(c), surrogates] : CodePointString(c)];
    }
    NSAttributedString *text = [[NSAttributedString alloc] initWithString:[list componentsJoinedByString:@"  "]
                                                               attributes:@{NSFontAttributeName: CodePointFont(), NSForegroundColorAttributeName: NSColor.labelColor}];

    NSScrollView *scroll = [[NSScrollView alloc] initWithFrame:NSMakeRect(0, 0, kMultiWidth, 30)];
    scroll.identifier = @"codePointsScroll";
    scroll.drawsBackground = NO;
    scroll.borderType = NSNoBorder;
    scroll.hasHorizontalScroller = NO;
    scroll.autohidesScrollers = YES;
    scroll.translatesAutoresizingMaskIntoConstraints = NO;
    NSTextView *textView = [[NSTextView alloc] initWithFrame:NSMakeRect(0, 0, kMultiWidth, 30)];
    textView.identifier = @"codePoints";
    textView.editable = NO;
    textView.selectable = YES;
    textView.drawsBackground = NO;
    textView.richText = NO;
    textView.textContainerInset = NSZeroSize;
    textView.textContainer.lineFragmentPadding = 0;
    textView.verticallyResizable = YES;
    textView.horizontallyResizable = NO;
    textView.autoresizingMask = NSViewWidthSizable;
    textView.textContainer.widthTracksTextView = YES;
    [textView.layoutManager replaceTextStorage:[[TSGlyphPopoverUnicodesTextStorage alloc] initWithAttributedString:text]];
    scroll.documentView = textView;
    NSLayoutManager *layoutManager = textView.layoutManager;
    NSTextContainer *container = textView.textContainer;
    CGFloat used = 0;
    if (layoutManager && container) {
        [layoutManager ensureLayoutForTextContainer:container];
        used = ceil(NSHeight([layoutManager usedRectForTextContainer:container]));
    }
    CGFloat height = MIN(used, kMultiMaxCodePointsHeight);
    scroll.hasVerticalScroller = (used > kMultiMaxCodePointsHeight);
    [NSLayoutConstraint activateConstraints:@[
        [scroll.widthAnchor constraintEqualToConstant:kMultiWidth],
        [scroll.heightAnchor constraintEqualToConstant:height],
    ]];
    [textView setFrameSize:NSMakeSize(kMultiWidth, MAX(used, height))];

    NSStackView *content = Stack(NSUserInterfaceLayoutOrientationVertical, @[countsField, scroll], 6, NSLayoutAttributeLeading);
    [content.widthAnchor constraintEqualToConstant:kMultiWidth].active = YES;
    return content;
}

- (void)loadView
{
    self.view = [[NSView alloc] initWithFrame:NSZeroRect];
    [self rebuild];
}

/// Builds the views for the character, with the code points opened and the block names chosen so far.
- (void)rebuild
{
    NSView *root = self.view;
    for (NSView *subview in root.subviews.copy)
        [subview removeFromSuperview];
    NSView *content = self.singleLetter ? [self singleCharacterView] : [self multipleCharactersView];
    [root addSubview:content];
    [NSLayoutConstraint activateConstraints:@[
        [content.leadingAnchor constraintEqualToAnchor:root.leadingAnchor constant:kInset],
        [content.trailingAnchor constraintEqualToAnchor:root.trailingAnchor constant:-kInset],
        [content.topAnchor constraintEqualToAnchor:root.topAnchor constant:kInset],
        [content.bottomAnchor constraintEqualToAnchor:root.bottomAnchor constant:-kInset],
    ]];
    [self fitToContents];
}

/// The popover takes the size of what it shows, also after a disclosure triangle or a block name is clicked.
- (void)fitToContents
{
    // The size the contents need, measured on them: the view itself is held at the
    // preferred content size it had (NSViewController constrains it so).
    NSView *root = self.view;
    NSSize inner = root.subviews.firstObject.fittingSize;
    NSSize size = NSMakeSize(ceil(inner.width + 2 * kInset), ceil(inner.height + 2 * kInset));
    self.preferredContentSize = size;
    [root setFrameSize:size];
    [root layoutSubtreeIfNeeded];
    self.popover.contentSize = size;
}

#pragma mark Public Methods

- (void)showPopoverRelativeToRect:(NSRect)positioningRect ofView:(NSView *)parentView
{
    NSPopover *popover = [NSPopover new];
    popover.contentViewController = self;
    popover.behavior = NSPopoverBehaviorSemitransient;
    self.popover = popover;
    [self fitToContents];
    [popover showRelativeToRect:positioningRect ofView:parentView preferredEdge:NSMinYEdge];
    [parentView.window makeFirstResponder:parentView];
}

@end
