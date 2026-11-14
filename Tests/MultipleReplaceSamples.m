// SPDX-License-Identifier: GPL-2.0-or-later
// The bundled sample sets of multiple replacement (Resources/MultipleReplaceSamples), made from Edit > Character Type
// Conversion's ajmacros tables (NSString-CharacterConversion), and the tests that the sets do what the menu does.
// Built by Tests/run-multiple-replace-samples.py; nothing is shown.
//
//   generate DIR      records every table entry the two menu conversions use, in their order, and writes the sets
//   equivalence DIR   applies the sets in DIR with the multiple replacement engine and compares with the menu
//   install DIR       writes the sets of DIR into new folders of sets: when, translated, never over the user's sets
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import "NSString-CharacterConversion.h"
#import "NSMutableString-Extras.h"
#import "TSRegexMultipleReplace.h"
#import "TSMultipleReplaceLibrary.h"

/// Needed by the conversions of utf.sty, which are not tested here.
NSInteger g_texChar = '\\';
static int failures;

static void Check(BOOL ok, NSString *name)
{
    if (!ok) {
        printf("FAIL %s\n", name.UTF8String);
        failures++;
    }
}

#pragma mark Recording the tables

/// One replacement of a conversion: -replaceAllOccurrencesOfString:withString:addingPercentForEndOfLine: (plain text,
/// not literal), or -replaceAllOccurrencesOfPattern:withString: (an NSRegularExpression without options, the
/// replacement taken as it is). These are the only ways the ajmacros conversions replace; the block form of the
/// pattern method cannot become a rule, and is recorded so that making the samples fails.
@interface TSTableEntry : NSObject
@property (nonatomic, copy) NSString *target;
@property (nonatomic, copy) NSString *replacement;
@property (nonatomic) BOOL addsPercent;
@property (nonatomic) BOOL isPattern;
@property (nonatomic) BOOL isBlock;
@end
@implementation TSTableEntry
- (BOOL)isEqual:(id)other
{
    TSTableEntry *entry = other;
    return [other isKindOfClass:[TSTableEntry class]] && [entry.target isEqualToString:self.target] && [entry.replacement isEqualToString:self.replacement]
        && entry.addsPercent == self.addsPercent && entry.isPattern == self.isPattern && entry.isBlock == self.isBlock;
}
- (NSUInteger)hash { return self.target.hash; }
@end

static NSMutableArray<TSTableEntry *> *TSRecording;
static IMP TSOriginalReplace, TSOriginalPattern, TSOriginalPatternBlock;

static void TSRecordEntry(NSString *target, NSString *replacement, BOOL addsPercent, BOOL isPattern, BOOL isBlock)
{
    if (!TSRecording)
        return;
    TSTableEntry *entry = [TSTableEntry new];
    entry.target = target;
    entry.replacement = replacement;
    entry.addsPercent = addsPercent;
    entry.isPattern = isPattern;
    entry.isBlock = isBlock;
    [TSRecording addObject:entry];
}

static void TSRecordingReplace(NSMutableString *receiver, SEL selector, NSString *target, NSString *replacement, BOOL addsPercent)
{
    TSRecordEntry(target, replacement, addsPercent, NO, NO);
    ((void (*)(id, SEL, NSString *, NSString *, BOOL))TSOriginalReplace)(receiver, selector, target, replacement, addsPercent);
}

static void TSRecordingPattern(NSMutableString *receiver, SEL selector, NSString *pattern, NSString *replacement)
{
    TSRecordEntry(pattern, replacement, NO, YES, NO);
    ((void (*)(id, SEL, NSString *, NSString *))TSOriginalPattern)(receiver, selector, pattern, replacement);
}

static void TSRecordingPatternBlock(NSMutableString *receiver, SEL selector, NSString *pattern, id block)
{
    TSRecordEntry(pattern, @"", NO, YES, YES);
    ((void (*)(id, SEL, NSString *, id))TSOriginalPatternBlock)(receiver, selector, pattern, block);
}

static void TSInstallRecorder(void)
{
    Class string = [NSMutableString class];
    TSOriginalReplace = method_setImplementation(class_getInstanceMethod(string, @selector(replaceAllOccurrencesOfString:withString:addingPercentForEndOfLine:)), (IMP)TSRecordingReplace);
    TSOriginalPattern = method_setImplementation(class_getInstanceMethod(string, @selector(replaceAllOccurrencesOfPattern:withString:)), (IMP)TSRecordingPattern);
    TSOriginalPatternBlock = method_setImplementation(class_getInstanceMethod(string, @selector(replaceAllOccurrencesOfPattern:usingBlock:)), (IMP)TSRecordingPatternBlock);
}

/// The entries a conversion uses, in order; every table is tried on any string, even an empty one.
static NSArray<TSTableEntry *> *TSRecord(NSString *(^conversion)(NSString *))
{
    TSRecording = [NSMutableArray array];
    NSString *converted = conversion(@"");
    Check(converted.length == 0, @"an empty string stays empty");
    NSArray<TSTableEntry *> *entries = TSRecording;
    TSRecording = nil;
    return entries;
}

/// The English names of the 18 kinds, which are the notes of the rules. Both directions of a kind share the name.
static NSDictionary<NSString *, NSString *> *TSKindNames(void)
{
    return @{
        @"MaruSujiWithAjMaru": @"Circled numbers", @"AjMaruWithMaruSuji": @"Circled numbers",
        @"KuroMaruSujiWithAjKuroMaru": @"Negative circled numbers", @"AjKuroMaruWithKuroMaruSuji": @"Negative circled numbers",
        @"KakkoSujiWithAjKakko": @"Parenthesized numbers", @"AjKakkoWithKakkoSuji": @"Parenthesized numbers",
        @"MaruAlphWithAjMaruAlph": @"Circled letters", @"AjMaruAlphWithMaruAlph": @"Circled letters",
        @"KakkoAlphWithAjKakkoAlph": @"Parenthesized letters", @"AjKakkoAlphWithKakkoAlph": @"Parenthesized letters",
        @"KuroMaruAlphWithAjKuroMaruAlph": @"Negative circled letters", @"AjKuroMaruAlphWithKuroMaruAlph": @"Negative circled letters",
        @"KakuAlphWithAjKakuAlph": @"Squared letters", @"AjKakuAlphWithKakuAlph": @"Squared letters",
        @"KuroKakuAlphWithAjKuroKakuAlph": @"Negative squared letters", @"AjKuroKakuAlphWithKuroKakuAlph": @"Negative squared letters",
        @"RomanWithAjRoman": @"Roman numerals", @"AjRomanWithRoman": @"Roman numerals",
        @"PeriodWithAjPeriod": @"Numbers with a period", @"AjPeriodWithPeriod": @"Numbers with a period",
        @"KakkoYobiWithAjKakkoYobi": @"Parenthesized days of the week", @"AjKakkoYobiWithKakkoYobi": @"Parenthesized days of the week",
        @"MaruYobiWithAjMaruYobi": @"Circled days of the week", @"AjMaruYobiWithMaruYobi": @"Circled days of the week",
        @"NijuMaruWithAjNijuMaru": @"Double circled numbers", @"AjNijuMaruWithNijuMaru": @"Double circled numbers",
        @"RecycleWithAjRecycle": @"Recycling symbols", @"AjRecycleWithRecycle": @"Recycling symbols",
        @"MaruKataWithAjMaruKata": @"Circled katakana", @"AjMaruKataWithMaruKata": @"Circled katakana",
        @"KakkoKansujiWithAjKakkoKansuji": @"Parenthesized kanji numerals", @"AjKakkoKansujiWithKakkoKansuji": @"Parenthesized kanji numerals",
        @"MaruKansujiWithAjMaruKansuji": @"Circled kanji numerals", @"AjMaruKansujiWithMaruKansuji": @"Circled kanji numerals",
        @"LigWithAjLig": @"Ligatures, symbols and variants", @"AjLigWithLig": @"Ligatures, symbols and variants",
    };
}

/// The conversions of one kind and direction: every NSString method stringByReplacing<Kind>With<Kind>, found in the
/// runtime so that a new kind is not missed. Keyed by the part after stringByReplacing.
static NSDictionary<NSString *, NSArray<TSTableEntry *> *> *TSKindTables(BOOL toMacros)
{
    NSMutableDictionary<NSString *, NSArray<TSTableEntry *> *> *tables = [NSMutableDictionary dictionary];
    unsigned int count = 0;
    Method *methods = class_copyMethodList([NSString class], &count);
    for (unsigned int i = 0; i < count; i++) {
        NSString *name = NSStringFromSelector(method_getName(methods[i]));
        if (![name hasPrefix:@"stringByReplacing"] || [name containsString:@":"])
            continue;
        NSString *kind = [name substringFromIndex:@"stringByReplacing".length];
        BOOL forward = [kind containsString:@"WithAj"], backward = [kind hasPrefix:@"Aj"];
        if ([kind isEqualToString:@"UnicodeCharactersWithAjMacros"] || [kind isEqualToString:@"AjMacrosWithUnicodeCharacters"] || forward == backward)
            continue;
        if (forward != toMacros)
            continue;
        SEL selector = method_getName(methods[i]);
        tables[kind] = TSRecord(^NSString *(NSString *string) { return ((NSString *(*)(id, SEL))objc_msgSend)(string, selector); });
    }
    free(methods);
    return tables;
}

/// The whole conversion of the menu, cut into the kinds it applies one after another.
static NSArray<NSDictionary *> *TSKindsInOrder(BOOL toMacros)
{
    NSArray<TSTableEntry *> *whole = TSRecord(^NSString *(NSString *string) {
        return toMacros ? string.stringByReplacingUnicodeCharactersWithAjMacros : string.stringByReplacingAjMacrosWithUnicodeCharacters;
    });
    NSMutableDictionary<NSString *, NSArray<TSTableEntry *> *> *tables = [TSKindTables(toMacros) mutableCopy];
    NSMutableArray<NSDictionary *> *kinds = [NSMutableArray array];
    NSUInteger position = 0;
    while (position < whole.count) {
        NSString *found = nil;
        for (NSString *kind in tables) {
            NSArray<TSTableEntry *> *table = tables[kind];
            if (table.count > 0 && position + table.count <= whole.count
                && [[whole subarrayWithRange:NSMakeRange(position, table.count)] isEqualToArray:table]) {
                Check(found == nil, [NSString stringWithFormat:@"one kind fits at entry %lu", (unsigned long)position]);
                found = kind;
            }
        }
        if (!found) {
            Check(NO, [NSString stringWithFormat:@"entry %lu (%@) belongs to a kind", (unsigned long)position, whole[position].target]);
            return @[];
        }
        NSString *name = TSKindNames()[found];
        Check(name != nil, [@"a name for the kind " stringByAppendingString:found]);
        [kinds addObject:@{@"kind": found, @"name": name ?: found, @"entries": tables[found]}];
        position += tables[found].count;
        [tables removeObjectForKey:found];
    }
    Check(tables.count == 0, [NSString stringWithFormat:@"every kind is used by the menu: %@", tables.allKeys]);
    Check(kinds.count == 18, [NSString stringWithFormat:@"18 kinds (%lu)", (unsigned long)kinds.count]);
    return kinds;
}

#pragma mark Making the sets

static NSString *const TSToMacrosName = @"Unicode Characters → ajmacros";
static NSString *const TSToCharactersName = @"ajmacros → Unicode Characters";

/// The options of a sample: CotEditor's defaults (ICU replacement syntax, the replacement unescaped), without the yen sign.
static TSRegexFindOptions TSSampleRegexOptions(void)
{
    return TSRegexMultipleReplace.defaultRegularExpressionOptions & ~TSRegexFindYenIsBackslash;
}

/// The user's choice (2026-11-12): an entry that adds % at the end of a line is a regular expression rule for the end
/// of a line, with the backslashes doubled, and then a plain rule for the rest. Other entries are one plain rule.
/// An entry whose text an earlier entry has already replaced everywhere does nothing, unless some replacement of the
/// conversion writes that text again. The menu's tables have such entries (㌃ twice, ㈷ as a day and as a ligature);
/// the samples leave them out (user's decision, 2026-11-14), and the equivalence test shows that nothing changes.
static BOOL TSNeverApplies(TSTableEntry *entry, NSSet<NSString *> *replaced, NSArray<NSDictionary *> *kinds)
{
    if (entry.isPattern || ![replaced containsObject:entry.target])
        return NO;
    for (NSDictionary *kind in kinds)
        for (TSTableEntry *other in kind[@"entries"])
            if ([other.replacement rangeOfString:entry.target].location != NSNotFound)
                return NO;
    return YES;
}

static NSUInteger TSLeftOut;

static TSRegexMultipleReplace *TSMakeSet(NSArray<NSDictionary *> *kinds)
{
    NSMutableArray<TSRegexReplacementRule *> *rules = [NSMutableArray array];
    NSMutableSet<NSString *> *replaced = [NSMutableSet set];
    TSLeftOut = 0;
    for (NSDictionary *kind in kinds) {
        NSString *note = kind[@"name"];
        for (TSTableEntry *entry in kind[@"entries"]) {
            Check(!entry.isBlock, [NSString stringWithFormat:@"%@: the pattern %@ is replaced by a block, which no rule can do", note, entry.target]);
            if (getenv("TS_SAMPLES_KEEP_DUPLICATES") == NULL && TSNeverApplies(entry, replaced, kinds)) {
                TSLeftOut++;
                continue;
            }
            if (!entry.isPattern)
                [replaced addObject:entry.target];
            if (entry.isPattern) {
                // The menu puts the replacement in as it is: a template that gives it back.
                [rules addObject:[[TSRegexReplacementRule alloc] initWithFindString:entry.target replaceString:[NSRegularExpression escapedTemplateForString:entry.replacement]
                                                              usesRegularExpression:YES ignoresCase:NO enabled:YES note:note]];
                continue;
            }
            if (entry.addsPercent) {
                // The menu's search is not literal: a character with a canonical decomposition (ゔ) also matches its
                // other form (う + U+3099) before a line end. A regular expression matches only what it says.
                NSOrderedSet<NSString *> *forms = [NSOrderedSet orderedSetWithObjects:entry.target, entry.target.precomposedStringWithCanonicalMapping,
                                                   entry.target.decomposedStringWithCanonicalMapping, nil];
                NSMutableArray<NSString *> *patterns = [NSMutableArray array];
                for (NSString *form in forms)
                    [patterns addObject:[NSRegularExpression escapedPatternForString:form]];
                NSString *target = patterns.count == 1 ? patterns.firstObject : [NSString stringWithFormat:@"(?:%@)", [patterns componentsJoinedByString:@"|"]];
                NSString *find = [target stringByAppendingString:@"(?=\\r|\\n)"];
                NSString *replace = [[NSRegularExpression escapedTemplateForString:entry.replacement] stringByAppendingString:@"%"];
                [rules addObject:[[TSRegexReplacementRule alloc] initWithFindString:find replaceString:replace usesRegularExpression:YES
                                                                         ignoresCase:NO enabled:YES note:[note stringByAppendingString:@" (end of line)"]]];
            }
            [rules addObject:[[TSRegexReplacementRule alloc] initWithFindString:entry.target replaceString:entry.replacement usesRegularExpression:NO
                                                                     ignoresCase:NO enabled:YES note:note]];
        }
    }
    return [[TSRegexMultipleReplace alloc] initWithRules:rules textualOptions:0 regularExpressionOptions:TSSampleRegexOptions()
                                       replacementSyntax:TSRegexReplacementSyntaxICU];
}

static NSURL *TSSampleURL(NSString *directory, NSString *name)
{
    return [[[NSURL fileURLWithPath:directory isDirectory:YES] URLByAppendingPathComponent:name] URLByAppendingPathExtension:@"json"];
}

static void Generate(NSString *directory)
{
    [NSFileManager.defaultManager createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:nil error:NULL];
    for (NSNumber *toMacros in @[@YES, @NO]) {
        NSArray<NSDictionary *> *kinds = TSKindsInOrder(toMacros.boolValue);
        TSRegexMultipleReplace *set = TSMakeSet(kinds);
        Check([set.JSONData writeToURL:TSSampleURL(directory, toMacros.boolValue ? TSToMacrosName : TSToCharactersName) atomically:YES], @"write a sample");
        NSUInteger entries = 0;
        for (NSDictionary *kind in kinds)
            entries += [kind[@"entries"] count];
        printf("%s: %lu entries that never apply left out\n", (toMacros.boolValue ? TSToMacrosName : TSToCharactersName).UTF8String, (unsigned long)TSLeftOut);
        printf("%s: %lu kinds, %lu entries, %lu rules\n", (toMacros.boolValue ? TSToMacrosName : TSToCharactersName).UTF8String,
               (unsigned long)kinds.count, (unsigned long)entries, (unsigned long)set.rules.count);
    }
}

#pragma mark Equivalence

/// What the user may have around the characters: line ends of every kind, the end of the text, combining marks,
/// a following digit (for the short forms), and the decomposed forms (the menu's search is not literal).
static NSArray<NSString *> *TSContexts(NSString *target)
{
    return @[[NSString stringWithFormat:@"a%@b", target], [target stringByAppendingString:@"\n"], [target stringByAppendingString:@"\r"],
             [target stringByAppendingString:@"\r\n"], [NSString stringWithFormat:@"%@%@\n", target, target], [target stringByAppendingString:@"1\n"],
             [target stringByAppendingString:@"\u0301\n"], [target stringByAppendingString:@"\u3099 "], [@"\n" stringByAppendingString:target],
             [target stringByAppendingString:@" \n"], [target stringByAppendingString:@"\u2028"], [target stringByAppendingString:@"\302\205"],
             [target stringByAppendingString:@"}%\n"], [target stringByAppendingString:@"\n\r"]];
}

/// The characters near the tables, each in the middle of a line and at its end, so that a character that the menu
/// converts but a set does not (or the reverse) is found even if it was not recorded.
static NSString *TSSweep(void)
{
    NSMutableString *sweep = [NSMutableString string];
    UTF32Char ranges[][2] = {{0x2150, 0x24FF}, {0x2600, 0x27BF}, {0x3000, 0x33FF}, {0x1F100, 0x1F1FF}};
    for (size_t r = 0; r < sizeof ranges / sizeof ranges[0]; r++)
        for (UTF32Char c = ranges[r][0]; c <= ranges[r][1]; c++) {
            UTF32Char little = NSSwapHostIntToLittle(c);
            NSString *character = [[NSString alloc] initWithBytes:&little length:4 encoding:NSUTF32LittleEndianStringEncoding];
            if (character)
                [sweep appendFormat:@"%@ %@\n", character, character];
        }
    return sweep;
}

/// Every command the reverse tables know, with numbers and forms around them, also those that are not in a table.
static NSString *TSCommandSweep(NSArray<TSTableEntry *> *entries)
{
    NSMutableOrderedSet<NSString *> *commands = [NSMutableOrderedSet orderedSet];
    // A table's command (\ajMaru{1}), or a pattern's (\\ajMasu\s*).
    NSRegularExpression *command = [NSRegularExpression regularExpressionWithPattern:@"^\\\\(?:\\\\)?(aj[A-Za-z]+)" options:0 error:NULL];
    for (TSTableEntry *entry in entries) {
        NSTextCheckingResult *match = [command firstMatchInString:entry.target options:0 range:NSMakeRange(0, entry.target.length)];
        if (match)
            [commands addObject:[@"\\" stringByAppendingString:[entry.target substringWithRange:[match rangeAtIndex:1]]]];
    }
    Check(commands.count > 50, @"the commands of the tables are found");
    NSMutableString *sweep = [NSMutableString string];
    for (NSString *name in commands) {
        for (NSInteger n = -1; n <= 60; n++)
            [sweep appendFormat:@"%@{%ld} %@%ld %@{0%ld}%@ %@ {%ld}\n%@%ld\n", name, (long)n, name, (long)n, name, (long)n, name, name, (long)n, name, (long)n];
        // The patterns take the white space after the command, line ends too.
        [sweep appendFormat:@"%@\t\u00a0\u3000x\n%@\r\n\r\ny%@\n\n%@x%@{}%@Ab\n", name, name, name, name, name, name];
    }
    return sweep;
}

static NSArray<TSTableEntry *> *TSAllEntries(NSArray<NSDictionary *> *kinds)
{
    NSMutableArray<TSTableEntry *> *entries = [NSMutableArray array];
    for (NSDictionary *kind in kinds)
        [entries addObjectsFromArray:kind[@"entries"]];
    return entries;
}

static NSString *TSVisible(NSString *string)
{
    NSMutableString *visible = [string mutableCopy];
    [visible replaceOccurrencesOfString:@"\r" withString:@"\\r" options:0 range:NSMakeRange(0, visible.length)];
    [visible replaceOccurrencesOfString:@"\n" withString:@"\\n" options:0 range:NSMakeRange(0, visible.length)];
    return visible;
}

/// The first difference, with some text around it.
static NSString *TSDifference(NSString *expected, NSString *actual)
{
    NSUInteger i = 0;
    while (i < expected.length && i < actual.length && [expected characterAtIndex:i] == [actual characterAtIndex:i])
        i++;
    NSUInteger start = i > 30 ? i - 30 : 0;
    NSString *(^around)(NSString *) = ^NSString *(NSString *s) {
        NSRange range = NSMakeRange(MIN(start, s.length), MIN(s.length - MIN(start, s.length), 60));
        return TSVisible([s substringWithRange:[s rangeOfComposedCharacterSequencesForRange:range]]);
    };
    return [NSString stringWithFormat:@"at %lu: menu “%@” set “%@”", (unsigned long)i, around(expected), around(actual)];
}

static NSString *_Nullable TSApply(TSRegexMultipleReplace *set, NSString *string, NSString *_Nullable lineEnding)
{
    return [set applyToString:string selectedRanges:@[[NSValue valueWithRange:NSMakeRange(0, 0)]] inSelection:NO lineEnding:lineEnding cancellation:nil].string;
}

/// A set with other options, which must not change what the samples do: the yen sign, OgreKit's replacement syntax,
/// the replacement not unescaped.
static TSRegexMultipleReplace *TSVariant(TSRegexMultipleReplace *set, TSRegexFindOptions add, TSRegexFindOptions remove, TSRegexReplacementSyntax syntax)
{
    return [[TSRegexMultipleReplace alloc] initWithRules:set.rules textualOptions:(set.textualOptions | add) & ~remove
                                regularExpressionOptions:(set.regularExpressionOptions | add) & ~remove replacementSyntax:syntax];
}

static void Compare(NSString *name, TSRegexMultipleReplace *set, NSString *input, NSString *(^menu)(NSString *), NSString *_Nullable lineEnding)
{
    NSDate *start = NSDate.date;
    NSString *expected = menu(input);
    NSString *actual = TSApply(set, input, lineEnding);
    if (![expected isEqualToString:actual ?: @""]) {
        printf("FAIL %s: %s\n", name.UTF8String, TSDifference(expected, actual ?: @"").UTF8String);
        failures++;
        // The mutation tests only need to know that something differs.
        if (getenv("TS_SAMPLES_STOP_AT_FAILURE"))
            exit(1);
    }
    if (getenv("TS_SAMPLES_TIMING"))
        printf("%.2fs %s (%lu characters)\n", -start.timeIntervalSinceNow, name.UTF8String, (unsigned long)input.length);
}

static TSRegexMultipleReplace *_Nullable TSLoad(NSString *directory, NSString *name)
{
    NSData *data = [NSData dataWithContentsOfURL:TSSampleURL(directory, name)];
    NSError *error = nil;
    TSRegexMultipleReplace *set = data ? [[TSRegexMultipleReplace alloc] initWithJSONData:(NSData *_Nonnull)data error:&error] : nil;
    Check(set != nil, [NSString stringWithFormat:@"read the sample %@ (%@)", name, error.localizedDescription]);
    return set;
}

/// The documents of the equivalence test in one direction.
static NSArray<NSString *> *TSDocuments(NSArray<TSTableEntry *> *entries, BOOL toMacros, NSArray<TSTableEntry *> *otherEntries)
{
    NSMutableString *contexts = [NSMutableString string];
    for (TSTableEntry *entry in entries)
        for (NSString *context in entry.isPattern ? @[] : TSContexts(entry.target))
            [contexts appendFormat:@"%@|", context];
    NSMutableArray<NSString *> *documents = [NSMutableArray arrayWithObjects:contexts, contexts.decomposedStringWithCanonicalMapping,
                                             contexts.precomposedStringWithCanonicalMapping, nil];
    if (toMacros) {
        [documents addObject:TSSweep()];
    } else {
        [documents addObject:TSCommandSweep(entries)];
        // What the other direction writes, back again.
        NSMutableString *written = [NSMutableString string];
        for (TSTableEntry *entry in otherEntries)
            [written appendFormat:@"%@ %@%%\n", entry.replacement, entry.replacement];
        [documents addObject:written];
        [documents addObject:written.decomposedStringWithCanonicalMapping];
    }
    return documents;
}

static void Equivalence(NSString *directory)
{
    NSArray<NSDictionary *> *kindsToMacros = TSKindsInOrder(YES), *kindsToCharacters = TSKindsInOrder(NO);
    NSArray<TSTableEntry *> *toMacros = TSAllEntries(kindsToMacros), *toCharacters = TSAllEntries(kindsToCharacters);
    for (NSNumber *forward in @[@YES, @NO]) {
        BOOL f = forward.boolValue;
        NSString *name = f ? TSToMacrosName : TSToCharactersName;
        TSRegexMultipleReplace *set = TSLoad(directory, name);
        if (!set)
            continue;
        Check(set.replacementSyntax == TSRegexReplacementSyntaxICU && set.textualOptions == 0 && set.regularExpressionOptions == TSSampleRegexOptions(),
              [name stringByAppendingString:@": CotEditor's options without the yen sign"]);
        NSString *(^menu)(NSString *) = f ? ^NSString *(NSString *s) { return s.stringByReplacingUnicodeCharactersWithAjMacros; }
                                          : ^NSString *(NSString *s) { return s.stringByReplacingAjMacrosWithUnicodeCharacters; };
        // No rule repeats an earlier one: the menu's duplicate entries, which never apply, are left out.
        NSMutableSet<NSString *> *finds = [NSMutableSet set];
        for (TSRegexReplacementRule *rule in set.rules) {
            NSString *key = [NSString stringWithFormat:@"%d %@", rule.usesRegularExpression, rule.findString];
            Check(![finds containsObject:key], [NSString stringWithFormat:@"%@: the rule for %@ is there once", name, rule.findString]);
            [finds addObject:key];
        }
        if (!f) {
            // The commands that take the white space after them (\ajMasu) take spaces and tabs, not a line break:
            // the paragraph after them stays a paragraph (user's decision, 2026-11-14), in the menu and in the sample.
            NSDictionary<NSString *, NSString *> *paragraphs = @{
                @"\\ajMasu\n\nNext": @"\u303C\n\nNext", @"\\ajMasu \t \nNext": @"\u303C\nNext",
                @"a\\ajCheckmark\r\n\r\nb": @"a\u2713\r\n\r\nb", @"\\ajMasu  \\ajYori\tx": @"\u303C\u309Fx"};
            for (NSString *input in paragraphs) {
                Check([menu(input) isEqualToString:paragraphs[input]], [NSString stringWithFormat:@"the menu keeps the line break after the command: %@ → %@", TSVisible(input), TSVisible(menu(input))]);
                Check([TSApply(set, input, nil) isEqualToString:paragraphs[input]], [NSString stringWithFormat:@"%@ keeps the line break after the command: %@", name, TSVisible(input)]);
            }
        }
        NSArray<TSTableEntry *> *entries = f ? toMacros : toCharacters;
        NSArray<NSString *> *documents = TSDocuments(entries, f, f ? toCharacters : toMacros);
        NSDictionary<NSString *, TSRegexMultipleReplace *> *variants = @{
            @"as saved": set,
            @"yen sign": TSVariant(set, TSRegexFindYenIsBackslash, 0, TSRegexReplacementSyntaxICU),
            @"OgreKit syntax": TSVariant(set, 0, 0, TSRegexReplacementSyntaxOgreKit),
            @"not unescaped": TSVariant(set, 0, TSRegexFindUnescapesReplacement, TSRegexReplacementSyntaxICU),
        };
        // Every document as saved; the variants with the first one (every entry in every context).
        for (NSString *variant in [variants.allKeys sortedArrayUsingSelector:@selector(compare:)])
            for (NSUInteger d = 0; d < ([variant isEqualToString:@"as saved"] ? documents.count : 1); d++) @autoreleasepool {
                Compare([NSString stringWithFormat:@"%@, %@, document %lu", name, variant, (unsigned long)d], variants[variant], documents[d], menu, nil);
            }
        for (NSString *ending in @[@"\n", @"\r", @"\r\n"])
            Compare([NSString stringWithFormat:@"%@, line ending %@", name, TSVisible(ending)], set, documents[0], menu, ending);
        // The end of the text without a line end: the menu adds no %. A document for the first and the last entry of
        // each kind (each document runs every rule).
        for (NSDictionary *kind in f ? kindsToMacros : kindsToCharacters) {
            NSArray<TSTableEntry *> *kindEntries = kind[@"entries"];
            for (TSTableEntry *entry in [NSOrderedSet orderedSetWithObjects:kindEntries.firstObject, kindEntries.lastObject, nil]) @autoreleasepool {
                Compare([NSString stringWithFormat:@"%@, %@ at the end of the text", name, entry.target], set, [@"x\n" stringByAppendingString:entry.target], menu, nil);
                Compare([NSString stringWithFormat:@"%@, %@ alone", name, entry.target], set, entry.target, menu, nil);
            }
        }
    }
}

#pragma mark Installing

static NSURL *TSTemporaryFolder(void)
{
    NSURL *parent = [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString] isDirectory:YES];
    return [parent URLByAppendingPathComponent:@"MultipleReplace" isDirectory:YES];
}

/// The files in a folder, their names composed: Foundation writes them decomposed (è as e and U+0300).
static NSArray<NSString *> *TSFiles(NSURL *directory)
{
    NSMutableArray<NSString *> *files = [NSMutableArray array];
    for (NSString *file in [NSFileManager.defaultManager contentsOfDirectoryAtPath:directory.path error:NULL] ?: @[])
        [files addObject:file.precomposedStringWithCanonicalMapping];
    return [files sortedArrayUsingSelector:@selector(compare:)];
}

static TSMultipleReplaceLibrary *TSLibrary(NSURL *directory, NSString *samples)
{
    TSMultipleReplaceLibrary *library = [[TSMultipleReplaceLibrary alloc] initWithDirectory:directory];
    library.usesTrash = NO;
    library.samplesDirectory = [NSURL fileURLWithPath:samples isDirectory:YES];
    return library;
}

/// The rules without their notes.
static NSArray<NSArray *> *TSRuleContents(TSRegexMultipleReplace *set)
{
    NSMutableArray<NSArray *> *contents = [NSMutableArray array];
    for (TSRegexReplacementRule *rule in set.rules)
        [contents addObject:@[rule.findString, rule.replaceString, @(rule.usesRegularExpression), @(rule.ignoresCase), @(rule.enabled)]];
    return contents;
}

static void Install(NSString *samples)
{
    NSFileManager *manager = NSFileManager.defaultManager;
    NSBundle *bundle = NSBundle.mainBundle;
    NSString *language = bundle.preferredLocalizations.firstObject ?: @"en";
    NSString *toMacros = [bundle localizedStringForKey:TSToMacrosName value:nil table:@"MultipleReplaceSamples"];
    NSString *toCharacters = [bundle localizedStringForKey:TSToCharactersName value:nil table:@"MultipleReplaceSamples"];
    NSString *expectedFiles = [[@[[toMacros stringByAppendingString:@".json"], [toCharacters stringByAppendingString:@".json"]]
                                sortedArrayUsingSelector:@selector(compare:)] componentsJoinedByString:@", "];

    // The first listing writes the samples, translated, into the folder that did not exist.
    NSURL *directory = TSTemporaryFolder();
    TSMultipleReplaceLibrary *library = TSLibrary(directory, samples);
    NSArray<NSString *> *names = library.setNames;
    Check([[TSFiles(directory) componentsJoinedByString:@", "] isEqualToString:expectedFiles],
          [NSString stringWithFormat:@"%@: the samples are written under their translated names (%@)", language, [TSFiles(directory) componentsJoinedByString:@", "]]);
    Check(names.count == 2 && [names containsObject:toMacros] && [names containsObject:toCharacters], [language stringByAppendingString:@": the first listing shows them"]);
    Check([language isEqualToString:@"en"] || (![toMacros isEqualToString:TSToMacrosName] && ![toCharacters isEqualToString:TSToCharactersName]),
          [language stringByAppendingString:@": the names are translated"]);
    Check([TSFiles(directory.URLByDeletingLastPathComponent) isEqualToArray:@[@"MultipleReplace"]], [language stringByAppendingString:@": no staging folder is left"]);
    for (NSString *pair in @[TSToMacrosName, TSToCharactersName]) {
        TSRegexMultipleReplace *bundled = TSLoad(samples, pair);
        NSString *localized = [pair isEqualToString:TSToMacrosName] ? toMacros : toCharacters;
        TSRegexMultipleReplace *written = [library setNamed:localized error:NULL];
        Check(written && [TSRuleContents(written) isEqualToArray:TSRuleContents(bundled)] && written.textualOptions == bundled.textualOptions
              && written.regularExpressionOptions == bundled.regularExpressionOptions && written.replacementSyntax == bundled.replacementSyntax,
              [NSString stringWithFormat:@"%@: %@ is written with its rules and options", language, localized]);
        NSUInteger translated = 0;
        for (NSUInteger i = 0; i < written.rules.count && i < bundled.rules.count; i++) {
            NSString *english = bundled.rules[i].note ?: @"";
            NSString *expected = [bundle localizedStringForKey:english value:nil table:@"MultipleReplaceSamples"];
            Check([written.rules[i].note isEqualToString:expected], [NSString stringWithFormat:@"%@: the note of rule %lu is translated", language, (unsigned long)i + 1]);
            translated += ![written.rules[i].note isEqualToString:english];
        }
        Check([language isEqualToString:@"en"] || translated == written.rules.count, [language stringByAppendingString:@": every note is translated"]);
    }

    // Once written, the user's changes stay: a changed, a removed and an added set, in this run and in the next.
    TSRegexMultipleReplace *mine = [[TSRegexMultipleReplace alloc] initWithRules:@[[[TSRegexReplacementRule alloc] initWithFindString:@"a" replaceString:@"b"
        usesRegularExpression:NO ignoresCase:NO enabled:YES note:nil]] textualOptions:0 regularExpressionOptions:0 replacementSyntax:TSRegexReplacementSyntaxICU];
    Check([library saveSet:mine named:toMacros error:NULL] && [library removeSetNamed:toCharacters error:NULL] && [library saveSet:mine named:@"Mine" error:NULL],
          [language stringByAppendingString:@": change, remove and add sets"]);
    NSArray<NSString *> *changed = TSFiles(directory);
    NSData *changedData = [NSData dataWithContentsOfURL:[[directory URLByAppendingPathComponent:toMacros] URLByAppendingPathExtension:@"json"]];
    Check(![library installSamples] && [TSFiles(directory) isEqualToArray:changed], [language stringByAppendingString:@": an existing folder is never written again"]);
    TSMultipleReplaceLibrary *next = TSLibrary(directory, samples);
    Check([next.setNames isEqualToArray:library.setNames] && [TSFiles(directory) isEqualToArray:changed]
          && [[NSData dataWithContentsOfURL:[[directory URLByAppendingPathComponent:toMacros] URLByAppendingPathExtension:@"json"]] isEqualToData:changedData],
          [language stringByAppendingString:@": the next launch keeps a changed sample, does not bring back a removed one"]);
    // Every set removed: the empty folder stays empty.
    for (NSString *name in next.setNames)
        [next removeSetNamed:name error:NULL];
    TSMultipleReplaceLibrary *afterEmptying = TSLibrary(directory, samples);
    Check(afterEmptying.setNames.count == 0 && TSFiles(directory).count == 0, [language stringByAppendingString:@": removing every set does not bring the samples back"]);
    [manager removeItemAtURL:directory.URLByDeletingLastPathComponent error:NULL];

    // A folder that already has other files, or is empty, is left as it is.
    NSURL *existing = TSTemporaryFolder();
    [manager createDirectoryAtURL:existing withIntermediateDirectories:YES attributes:nil error:NULL];
    Check(TSLibrary(existing, samples).setNames.count == 0 && TSFiles(existing).count == 0, [language stringByAppendingString:@": an existing empty folder is not filled"]);
    [@"x" writeToURL:[existing URLByAppendingPathComponent:@"notes.txt"] atomically:YES encoding:NSUTF8StringEncoding error:NULL];
    Check(![TSLibrary(existing, samples) installSamples] && [TSFiles(existing) isEqualToArray:@[@"notes.txt"]], [language stringByAppendingString:@": a folder with other files is not filled"]);
    [manager removeItemAtURL:existing.URLByDeletingLastPathComponent error:NULL];

    // A file where the folder would be is not replaced.
    NSURL *file = TSTemporaryFolder();
    [manager createDirectoryAtURL:file.URLByDeletingLastPathComponent withIntermediateDirectories:YES attributes:nil error:NULL];
    [@"x" writeToURL:file atomically:YES encoding:NSUTF8StringEncoding error:NULL];
    Check(![TSLibrary(file, samples) installSamples] && [[NSString stringWithContentsOfURL:file encoding:NSUTF8StringEncoding error:NULL] isEqualToString:@"x"],
          [language stringByAppendingString:@": a file in the folder's place is kept"]);
    [manager removeItemAtURL:file.URLByDeletingLastPathComponent error:NULL];

    // Without samples, or with a broken one, nothing is written: no folder, no staging folder.
    NSURL *none = TSTemporaryFolder();
    TSMultipleReplaceLibrary *plain = [[TSMultipleReplaceLibrary alloc] initWithDirectory:none];
    Check(plain.setNames.count == 0 && ![manager fileExistsAtPath:none.path], [language stringByAppendingString:@": no samples, no folder"]);
    NSString *broken = [NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString];
    [manager copyItemAtPath:samples toPath:broken error:NULL];
    [@"{ not json" writeToURL:TSSampleURL(broken, @"Broken") atomically:YES encoding:NSUTF8StringEncoding error:NULL];
    TSMultipleReplaceLibrary *brokenLibrary = TSLibrary(none, broken);
    Check(brokenLibrary.setNames.count == 0 && ![manager fileExistsAtPath:none.path] && TSFiles(none.URLByDeletingLastPathComponent).count == 0,
          [language stringByAppendingString:@": a broken sample writes nothing, and leaves no staging folder"]);
    [manager removeItemAtPath:broken error:NULL];
    [manager removeItemAtURL:none.URLByDeletingLastPathComponent error:NULL];
}

int main(int argc, const char *argv[])
{
    @autoreleasepool {
        if (argc < 3) {
            fprintf(stderr, "usage: %s generate|equivalence|install DIR | apply SET INPUT OUTPUT | targets - OUTPUT\n", argv[0]);
            return 2;
        }
        setvbuf(stdout, NULL, _IOLBF, 0);
        TSInstallRecorder();
        NSString *mode = @(argv[1]), *directory = @(argv[2]);
        if ([mode isEqualToString:@"generate"])
            Generate(directory);
        else if ([mode isEqualToString:@"equivalence"])
            Equivalence(directory);
        else if ([mode isEqualToString:@"install"])
            Install(directory);
        else if ([mode isEqualToString:@"apply"] && argc > 4) {
            // apply SET.json INPUT OUTPUT: the set applied by the multiple replacement engine (for the TeX check).
            NSData *data = [NSData dataWithContentsOfFile:directory];
            TSRegexMultipleReplace *set = data ? [[TSRegexMultipleReplace alloc] initWithJSONData:(NSData *_Nonnull)data error:NULL] : nil;
            NSString *input = [NSString stringWithContentsOfFile:@(argv[3]) encoding:NSUTF8StringEncoding error:NULL];
            NSString *output = set && input ? TSApply(set, input, nil) : nil;
            Check(output && [output writeToFile:@(argv[4]) atomically:YES encoding:NSUTF8StringEncoding error:NULL], @"apply the set");
        } else if ([mode isEqualToString:@"cids"] && argc > 3) {
            // cids INPUT OUTPUT: the Adobe-Japan1 CID that Hiragino draws for each line's character (0 when none).
            NSMutableArray<NSString *> *lines = [NSMutableArray array];
            for (NSString *line in [[NSString stringWithContentsOfFile:directory encoding:NSUTF8StringEncoding error:NULL] componentsSeparatedByString:@"\n"]) {
                NSUInteger cid = line.length ? TSAdobeJapan1CIDForSequence(line) : NSNotFound;
                [lines addObject:[NSString stringWithFormat:@"%lu", (unsigned long)(cid == NSNotFound ? 0 : cid)]];
            }
            Check([[lines componentsJoinedByString:@"\n"] writeToFile:@(argv[3]) atomically:YES encoding:NSUTF8StringEncoding error:NULL], @"write the CIDs");
        } else if ([mode isEqualToString:@"targets"] && argc > 3) {
            // targets OUTPUT: every character the menu converts to ajmacros, one per line, in the menu's order.
            NSMutableOrderedSet<NSString *> *targets = [NSMutableOrderedSet orderedSet];
            for (TSTableEntry *entry in TSAllEntries(TSKindsInOrder(YES)))
                if (!entry.isPattern)
                    [targets addObject:entry.target];
            Check([[targets.array componentsJoinedByString:@"\n"] writeToFile:@(argv[3]) atomically:YES encoding:NSUTF8StringEncoding error:NULL], @"write the targets");
        }
        else
            return 2;
        if (failures)
            return 1;
        printf("PASS %s (%s)\n", mode.UTF8String, (NSBundle.mainBundle.preferredLocalizations.firstObject ?: @"en").UTF8String);
    }
    return 0;
}
