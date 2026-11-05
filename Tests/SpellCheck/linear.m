// Masking in linear time: the indexed lookups of group, scope and environment
// ends must give exactly the masks of the direct scans, and unbalanced input
// must not make masking quadratic.
// usage: linear RULES-FILE OTHER-RULES-FILE FIXTURE.tex... [--reference]
//   --reference  time the direct scans instead (expected to fail the timing checks)
#import <Foundation/Foundation.h>
#import "TSSpellExclusions.h"

extern BOOL TSSpellTestReferenceScans;
extern NSInteger TSSpellTestIndexBudget;

// Everything a mask tells about a text.
static NSData *Describe(TSSpellMask *mask, NSUInteger n)
{
    NSMutableData *d = [NSMutableData data];
    NSString *masked = mask.masked;
    NSUInteger length = masked.length;
    unichar *chars = malloc((length + 1) * sizeof(unichar));
    [masked getCharacters:chars range:NSMakeRange(0, length)];
    [d appendBytes:&length length:sizeof(length)];
    [d appendBytes:chars length:length * sizeof(unichar)];
    free(chars);
    for (NSUInteger i = 0; i <= length; i++) {
        NSUInteger origin = [mask originalIndexForMaskedIndex:i];
        [d appendBytes:&origin length:sizeof(origin)];
    }
    NSMutableArray<NSString *> *codes = [NSMutableArray array];
    uint8_t *flags = malloc(n + 1);
    for (NSUInteger i = 0; i < n; i++) {
        NSRange r = NSMakeRange(i, 1);
        NSString *language = [mask languageForOriginalIndex:i];
        NSUInteger code = 0;
        if (language) {
            code = [codes indexOfObject:language];
            if (code == NSNotFound) { [codes addObject:language]; code = codes.count - 1; }
            code++;
        }
        flags[i] = (uint8_t)(([mask rangeTouchesExclusion:r] ? 1 : 0) | ([mask rangeIsNextToAccent:r] ? 2 : 0) | (code << 2));
    }
    [d appendBytes:flags length:n];
    free(flags);
    NSMutableString *rest = [NSMutableString stringWithString:[codes componentsJoinedByString:@","]];
    for (TSSpellLanguageSegment *s in [mask languageSegments])
        [rest appendFormat:@" %lu+%lu:%@", (unsigned long)s.range.location, (unsigned long)s.range.length, s.language ?: @"-"];
    [d appendData:[rest dataUsingEncoding:NSUTF8StringEncoding]];
    return d;
}

// The mask by the direct scans, by the indexes from the start, and as TeXShop
// makes it (direct scans, then the indexes once the scans have been long).
static NSString *Compare(TSSpellExclusions *ex, NSString *text)
{
    TSSpellTestReferenceScans = YES; TSSpellTestIndexBudget = -1;
    NSData *reference = Describe([ex maskForText:text], text.length);
    TSSpellTestReferenceScans = NO; TSSpellTestIndexBudget = 0;
    NSData *indexed = Describe([ex maskForText:text], text.length);
    TSSpellTestIndexBudget = 64;
    NSData *mixed = Describe([ex maskForText:text], text.length);
    TSSpellTestIndexBudget = -1;
    NSData *normal = Describe([ex maskForText:text], text.length);
    if (![reference isEqualToData:indexed]) return @"indexed";
    if (![reference isEqualToData:mixed]) return @"mixed";
    if (![reference isEqualToData:normal]) return @"default";
    return nil;
}

static uint64_t sSeed = 0x9e3779b97f4a7c15ULL;
static uint32_t Random(uint32_t limit)
{
    sSeed ^= sSeed << 13; sSeed ^= sSeed >> 7; sSeed ^= sSeed << 17;
    return (uint32_t)(sSeed % limit);
}

static NSString *RandomText(NSUInteger tokens)
{
    static NSArray<NSString *> *pieces;
    if (!pieces) pieces = @[
        @"word", @"zz", @"Haus", @" ", @" ", @"  ", @"\t", @"\n", @"\n\n", @"\r\n", @"\n  \n",
        @"{", @"{", @"}", @"}", @"[", @"]", @"(", @")", @"\\", @"\\\\", @"%", @"% note\n", @"$", @"$$", @"\\[", @"\\]",
        @"\\(", @"\\)", @"*", @"#1", @"#2", @"##", @"@", @"\\@", @"\\{", @"\\}", @"\\%",
        @"\\foreignlanguage", @"\\foreignlanguage{german}{", @"\\selectlanguage", @"\\selectlanguage{french}",
        @"{\\selectlanguage{german}", @"\\textgerman", @"\\textfrench{", @"\\begin", @"\\end", @"\\begin{", @"\\end{",
        @"\\begin{otherlanguage}", @"\\end{otherlanguage}", @"\\begin{otherlanguage}{german}",
        @"\\begin{german}", @"\\end{german}", @"\\end{german*}", @"\\end { german }", @"\\end{\u00a0german\u3000}",
        @"\\begin{spanish}", @"\\end{spanish}", @"\\begin{verbatim}", @"\\end{verbatim}", @"\\begin{equation}", @"\\end{equation}",
        @"\\begin{tabular}{ll}", @"\\begin{foo}", @"\\end{foo}", @"\\label", @"\\label{", @"\\ref{x}", @"\\cite[p]{k}",
        @"\\newcommand", @"\\newcommand{\\foo}[1]{\\label{#1}}", @"\\newcommand\\bar[2][d]{#1 \\ref{#2}}", @"\\foo", @"\\bar",
        @"\\def\\baz#1{\\ref{#1}}", @"\\baz", @"\\NewDocumentCommand{\\qux}{m o}{\\ref{#1}}", @"\\qux",
        @"\\newenvironment{foo}{\\begin{align}}{\\end{align}}", @"\\verb|x|", @"\\verb", @"\\emph", @"\\\\[2pt]",
        @"\\\"u", @"\\'{e}", @"\\ss", @"\\\"{a}", @"\\~n", @"\\cmidrule(lr){1-2}", @"\\usepackage[opt]{pkg}",
        @"{german}", @"{ngerman}", @"{french}", @"{klingon}", @"{ german }", @"{german*}", @"{otherlanguage}",
        @"\u00a0", @"\u3000", @"\u2003", @"\u200b", @"é", @"😀", @"\u0301",
    ];
    NSMutableString *s = [NSMutableString string];
    for (NSUInteger k = 0; k < tokens; k++) [s appendString:pieces[Random((uint32_t)pieces.count)]];
    return s;
}

static NSString *Repeat(NSString *unit, NSUInteger count)
{
    NSMutableString *s = [NSMutableString stringWithCapacity:unit.length * count];
    for (NSUInteger k = 0; k < count; k++) [s appendString:unit];
    return s;
}

// Inputs that make the direct scans quadratic: a unit to repeat, and what follows.
static NSArray<NSArray<NSString *> *> *Pathological(void)
{
    return @[@[@"\\foreignlanguage{german}{ ", @""], @[@"\\textgerman{ ", @""], @[@"{\\selectlanguage{german} ", @""],
             @[@"\\selectlanguage{german}{ ", @""], @[@"\\selectlanguage{german}{\\begin{x}} ", @""],
             @[@"\\begin{otherlanguage}{german} ", @""], @[@"\\begin{german} ", @""], @[@"\\begin{ ", @""], @[@"\\end{ ", @""],
             @[@"\\label{ ", @""], @[@"\\usepackage[ ", @""], @[@"\\cmidrule( ", @""], @[@"\\newcommand{\\a}[1]{ ", @""],
             @[@"\\begin{german}\\end{ ", @"}"], @[@"{\\selectlanguage{german} {", @""],
             @[@"\\begin{x}\\selectlanguage{german} ", @""]];
}

int main(int argc, char **argv)
{
    @autoreleasepool {
        if (argc < 4) { fprintf(stderr, "usage: linear RULES OTHER-RULES FIXTURE...\n"); return 2; }
        BOOL reference = !strcmp(argv[argc - 1], "--reference");
        int fixtures = reference ? argc - 1 : argc;
        TSSpellExclusions *ex = [[TSSpellExclusions alloc] initWithRulesFile:@(argv[1])];
        TSSpellExclusions *other = [[TSSpellExclusions alloc] initWithRulesFile:@(argv[2])];
        if (ex.problems || other.problems) { fprintf(stderr, "rules problems\n%s%s", ex.problems.UTF8String ?: "", other.problems.UTF8String ?: ""); return 2; }
        int failures = 0;

        if (!reference) {
            for (int k = 3; k < fixtures; k++) {
                NSString *text = [NSString stringWithContentsOfFile:@(argv[k]) encoding:NSUTF8StringEncoding error:NULL];
                if (!text) { fprintf(stderr, "cannot read %s\n", argv[k]); return 2; }
                for (TSSpellExclusions *e in @[ex, other]) {
                    NSString *bad = Compare(e, text);
                    if (bad) { printf("FAIL: %s differs (%s)\n", argv[k], bad.UTF8String); failures++; }
                }
            }
            NSUInteger compared = 0;
            for (NSUInteger round = 0; round < 15000; round++) {
                NSUInteger tokens = (round % 300 == 0) ? 4000 : 1 + Random(120);
                NSString *text = RandomText(tokens);
                for (TSSpellExclusions *e in @[ex, other]) {
                    NSString *bad = Compare(e, text);
                    compared++;
                    if (bad) {
                        if (failures < 5) printf("FAIL: random text differs (%s):\n%s\n", bad.UTF8String, text.UTF8String);
                        failures++;
                    }
                }
            }
            for (NSArray<NSString *> *case_ in Pathological()) {
                NSString *unit = case_[0];
                for (NSString *tail in @[case_[1], @"}", @"]", @")", @"\\end{german}", Repeat(@"}", 500)]) {
                    NSString *text = [Repeat(unit, 500) stringByAppendingString:tail];
                    for (TSSpellExclusions *e in @[ex, other]) {
                        NSString *bad = Compare(e, text);
                        compared++;
                        if (bad) { printf("FAIL: repeated '%s' differs (%s)\n", unit.UTF8String, bad.UTF8String); failures++; }
                    }
                }
            }
            printf("compared %lu texts with the direct scans: %s\n", (unsigned long)compared, failures ? "DIFFERENCES" : "identical");
        }

        TSSpellTestReferenceScans = reference;
        TSSpellTestIndexBudget = -1;
        double worst = 0;
        for (NSArray<NSString *> *case_ in Pathological()) {
            NSString *unit = case_[0];
            NSString *text = [Repeat(unit, 16000) stringByAppendingString:case_[1]];
            CFAbsoluteTime start = CFAbsoluteTimeGetCurrent();
            TSSpellMask *mask = [ex maskForText:text];
            double seconds = CFAbsoluteTimeGetCurrent() - start;
            worst = MAX(worst, seconds);
            printf("%7.1f ms  16000 x '%s' (%lu characters)\n", seconds * 1000, unit.UTF8String, (unsigned long)text.length);
            if (mask.originalLength != text.length) failures++;
            if (seconds > 0.25) { printf("FAIL: masking took %.2f s\n", seconds); failures++; }
        }
        if (failures) { printf("FAIL: %d problem(s)\n", failures); return 1; }
        printf("PASS: masks identical to the direct scans; unbalanced input masked in at most %.0f ms.\n", worst * 1000);
    }
    return 0;
}
