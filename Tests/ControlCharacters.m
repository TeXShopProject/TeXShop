// Control characters in the source take the width of the U+FFFD marker drawn
// over them, whether or not invisible characters are shown. Nothing is displayed.
#import <Cocoa/Cocoa.h>
#import <objc/runtime.h>
#import "TSLayoutManager.h"
#import "MarkerKeys.h"
#import "MemoryDefaults.h"
#import "TSInvisibleCharacters.h"
static TSMemoryDefaults *settings;
static id MemoryStandardDefaults(id self, SEL cmd) { return settings; }
NSColor *InvisibleColor;
static int failures;
static void Require(NSString *name, BOOL condition) { if (!condition) { printf("FAIL %s\n", name.UTF8String); failures++; } }

static NSMutableArray<NSString *> *drawn;
static void (*originalDrawMarker)(id, SEL, NSString *, NSUInteger, NSPoint, NSDictionary *, NSMutableDictionary *);
static void RecordMarker(TSLayoutManager *layout, SEL cmd, NSString *marker, NSUInteger glyph, NSPoint origin, NSDictionary *attributes, NSMutableDictionary *cache)
{
    unichar character = [layout.textStorage.string characterAtIndex:[layout characterIndexForGlyphAtIndex:glyph]];
    [drawn addObject:[NSString stringWithFormat:@"%04X%@", character, marker]];
    originalDrawMarker(layout, cmd, marker, glyph, origin, attributes, cache);
}

static CGFloat Advance(NSLayoutManager *layout, NSUInteger index)
{
    NSUInteger glyph = [layout glyphIndexForCharacterAtIndex:index];
    return [layout locationForGlyphAtIndex:glyph + 1].x - [layout locationForGlyphAtIndex:glyph].x;
}

int main(void)
{
    @autoreleasepool {
        settings = [TSMemoryDefaults new];
        method_setImplementation(class_getClassMethod(NSUserDefaults.class, @selector(standardUserDefaults)), (IMP)MemoryStandardDefaults);
        [NSApplication sharedApplication];
        InvisibleColor = NSColor.systemRedColor;
        Method draw = class_getInstanceMethod(TSLayoutManager.class, @selector(drawInvisibleCharacter:atGlyphIndex:containerOrigin:attributes:cache:));
        Require(@"marker drawing method exists", draw != NULL);
        originalDrawMarker = (void *)method_getImplementation(draw);
        method_setImplementation(draw, (IMP)RecordMarker);

        // a, SOH, b, VT, c, FF, d, ZWJ, e, ESC, f, tab, g, newline, h
        NSString *text = @"a\x01" @"b\x0B" @"c\x0C" @"d‍e\x1B" @"f\tg\nh";
        NSTextStorage *storage = [[NSTextStorage alloc] initWithString:text attributes:@{NSFontAttributeName: [NSFont userFixedPitchFontOfSize:12]}];
        TSLayoutManager *layout = [TSLayoutManager new];
        NSTextContainer *container = [[NSTextContainer alloc] initWithContainerSize:NSMakeSize(1000, 1000)];
        [layout addTextContainer:container];
        [storage addLayoutManager:layout];
        [layout ensureLayoutForTextContainer:container];

        CGFloat marker = [TSControlCharacterMarker sizeWithAttributes:@{NSFontAttributeName: [NSFont userFixedPitchFontOfSize:12]}].width;
        for (NSNumber *index in @[@1, @3, @5, @9]) {
            CGFloat width = Advance(layout, index.unsignedIntegerValue);
            Require([NSString stringWithFormat:@"control character at %@ has the marker width", index], fabs(width - marker) < 0.5 && width > 1);
        }
        Require(@"zero width joiner stays without width", Advance(layout, 7) < 0.5);
        NSUInteger last = [layout glyphIndexForCharacterAtIndex:text.length - 1];
        Require(@"text after a form feed is laid out", [layout textContainerForGlyphAtIndex:last effectiveRange:NULL] == container);
        NSRect first = [layout lineFragmentRectForGlyphAtIndex:0 effectiveRange:NULL];
        NSRect afterVT = [layout lineFragmentRectForGlyphAtIndex:[layout glyphIndexForCharacterAtIndex:4] effectiveRange:NULL];
        Require(@"vertical tab no longer breaks the line", NSEqualRects(first, afterVT));

        NSImage *image = [[NSImage alloc] initWithSize:NSMakeSize(400, 100)];
        for (NSNumber *showing in @[@NO, @YES]) {
            [layout setInvisibleCharactersEnabled:showing.boolValue];
            drawn = [NSMutableArray array];
            [image lockFocus];
            [layout drawGlyphsForGlyphRange:NSMakeRange(0, layout.numberOfGlyphs) atPoint:NSZeroPoint];
            [image unlockFocus];
            NSArray *controls = [drawn filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"SELF ENDSWITH %@", TSControlCharacterMarker]];
            Require([NSString stringWithFormat:@"markers with invisible characters %@", showing],
                     [controls isEqual:@[@"0001�", @"000B�", @"000C�", @"001B�"]]);
        }
        for (unichar c = 0; c < 0x20; c++)
            Require([NSString stringWithFormat:@"set membership U+%04X", c], TSIsShownControlCharacter(c) == !(c == '\t' || c == '\n' || c == '\r'));
        Require(@"no other characters", !TSIsShownControlCharacter(0x20) && !TSIsShownControlCharacter(0x7F) && !TSIsShownControlCharacter(0x200D));
        if (failures) return 1;
        printf("PASS: control characters get the marker width and marker, other zero-width characters are untouched\n");
    }
    return 0;
}
