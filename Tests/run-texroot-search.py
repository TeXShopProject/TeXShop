#!/usr/bin/env python3
"""TSTeXRootSearch searches the TeX sources of a root and computes, for each match or hunk, the lines before and after
the replacement (Issue #45, spec §2.4–§2.6).

A real project is collected for each run. The replacements are compared with the Advanced Find engine itself
(TSRegexTextFind for Replace All, TSRegexMultipleReplace for a set) on random texts, open documents with and without
a line ending and files on the disk with LF, CRLF or CR. Files with mixed line endings put in the line ending of the
line where a match starts. Hunks are whole lines, separated by unchanged lines, and as few changed lines as a line
comparison gives. Also: line numbers with every kind of line break, highlights on whole characters, limits per file
and in all, the generation, cancellation, the encoding check of files on the disk, and query errors.
With --mutations, broken copies must be caught."""
from pathlib import Path
import shutil, subprocess, sys, tempfile

root = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(root / 'Tests'))
from source_tree import include_args

ENGINE = ['TSRegexFindOptions.m', 'TSRegexFindPattern.m', 'TSRegexReplacementTemplate.m', 'TSRegexTextFind.m', 'TSRegexFindReplacement.m',
          'TSRegexReplaceAllResult.m', 'TSRegexMultipleReplace.m', 'TSRegexReplacementRule.m', 'TSRegexPatternLexer.m',
          'TSRegexOnigmoIncompatibility.m']
SOURCES = {**{name: f'Sources/Find/{name}' for name in ENGINE},
           'TSTeXRootSearch.m': 'Sources/Find/TeXRoot/TSTeXRootSearch.m',
           'TSTeXRootProject.m': 'Sources/Document/TSTeXRootProject.m',
           'TSRootFileResolver.m': 'Sources/Document/TSRootFileResolver.m',
           'TSSourceMagicComments.m': 'Sources/Document/TSSourceMagicComments.m'}

PROGRAM = r'''
#import <Foundation/Foundation.h>
#import "TSTeXRootSearch.h"
#import "TSTeXRootProject.h"
#import "TSRegexTextFind.h"
#import "TSRegexMultipleReplace.h"
#import "TSRegexReplacementRule.h"

static int failures = 0;
static void Check(BOOL ok, NSString *what) { if (!ok) { if (failures < 30) printf("FAIL: %s\n", what.UTF8String); failures++; } }
static NSString *Q(NSString *s) {
    NSMutableString *r = [NSMutableString stringWithString:@"\""];
    for (NSUInteger i = 0; i < s.length; i++) {
        unichar c = [s characterAtIndex:i];
        if (c == '\n') [r appendString:@"\\n"]; else if (c == '\r') [r appendString:@"\\r"]; else if (c < 0x20 || c > 0x7E) [r appendFormat:@"\\u%04X", c]; else [r appendFormat:@"%C", c];
    }
    [r appendString:@"\""];
    return r;
}

#pragma mark Fixture

static NSString *Folder;
static NSMutableDictionary<NSString *, TSTeXRootProjectFile *> *Files;
static NSStringEncoding CF(CFStringEncoding e) { return CFStringConvertEncodingToNSStringEncoding(e); }

static TSTeXRootSourceCodec *Codec(void) {
    return [[TSTeXRootSourceCodec alloc] initWithEncodingForData:^NSStringEncoding(NSData *data, NSURL *url) {
        return [url.lastPathComponent hasPrefix:@"sjis"] ? CF(kCFStringEncodingShiftJIS) : NSUTF8StringEncoding;
    } textForEditing:^NSString *(NSString *text, NSStringEncoding encoding) {
        return [text stringByReplacingOccurrencesOfString:@"\t" withString:@"    "];   // lossy for files with tabs
    } textForSaving:^NSString *(NSString *text, NSStringEncoding encoding) {
        return text;
    }];
}

static void Write(NSString *name, NSString *text, NSStringEncoding encoding) {
    [[text dataUsingEncoding:encoding] writeToFile:[Folder stringByAppendingPathComponent:name] atomically:NO];
}

static void Collect(void) {
    TSTeXRootProjectCollector *collector = [[TSTeXRootProjectCollector alloc] initWithRootURL:[NSURL fileURLWithPath:[Folder stringByAppendingPathComponent:@"root.tex"]]
                                                                                       codec:Codec() allowsSourceDoc:NO jobNameToken:@"\\jobname"];
    TSTeXRootProject *project = [collector collect];
    Files = [NSMutableDictionary dictionary];
    for (TSTeXRootProjectFile *file in project.files)
        Files[file.relativePath] = file;
}

#pragma mark Helpers

static TSTeXRootSearchSource *Open(NSString *text, NSString *lineEnding) {
    return [[TSTeXRootSearchSource alloc] initWithFile:Files[@"root.tex"] openDocumentText:text lineEnding:lineEnding searchOnlyReason:TSTeXRootSearchOnlyReasonNone];
}
static TSTeXRootSearchSource *Disk(NSString *name) { return [[TSTeXRootSearchSource alloc] initWithFile:Files[name]]; }

static TSTeXRootSearchResult *Search(NSArray<TSTeXRootSearchSource *> *sources, TSTeXRootSearchQuery *query) {
    return [TSTeXRootSearch searchSources:sources query:query generation:7 codec:Codec() maximumItemsPerFile:TSTeXRootSearch.defaultMaximumItemsPerFile
                             maximumItems:TSTeXRootSearch.defaultMaximumItems cancellation:nil progress:nil];
}
static TSTeXRootSearchFileResult *One(TSTeXRootSearchSource *source, TSTeXRootSearchQuery *query) {
    return Search(@[source], query).files.firstObject;
}
static NSString *All(TSTeXRootSearchFileResult *file) {
    return file ? [file textReplacingItemsAtIndexes:[NSIndexSet indexSetWithIndexesInRange:NSMakeRange(0, file.items.count)]] : nil;
}
static NSString *Apply(NSString *text, TSRegexReplaceAllResult *result) {
    NSMutableString *s = [text mutableCopy];
    for (TSRegexFindReplacement *r in result.replacements.reverseObjectEnumerator)
        [s replaceCharactersInRange:r.range withString:r.string];
    return s;
}
/// Replace All of the panel: the find string and the replaced text put into `lineEnding`.
static NSString *EngineReplaceAll(NSString *text, NSString *find, NSString *replace, TSRegexFindOptions options, TSRegexReplacementSyntax syntax, NSString *lineEnding) {
    NSString *f = lineEnding ? TSRegexStringByReplacingLineEndings(find, lineEnding) : find;
    TSRegexFindPattern *pattern = [[TSRegexFindPattern alloc] initWithFindString:f options:options error:NULL];
    TSRegexTextFind *textFind = [[TSRegexTextFind alloc] initWithString:text pattern:pattern lineEnding:lineEnding selectedRanges:@[[NSValue valueWithRange:NSMakeRange(0, 0)]] inSelection:NO error:NULL];
    TSRegexReplacementTemplate *template = [[TSRegexReplacementTemplate alloc] initWithString:replace pattern:pattern syntax:syntax];
    return Apply(text, [textFind replaceAllWithTemplate:template cancellation:nil]);
}
static NSArray<NSValue *> *EngineMatches(NSString *text, NSString *find, TSRegexFindOptions options, NSString *lineEnding) {
    NSString *f = lineEnding ? TSRegexStringByReplacingLineEndings(find, lineEnding) : find;
    TSRegexFindPattern *pattern = [[TSRegexFindPattern alloc] initWithFindString:f options:options error:NULL];
    TSRegexTextFind *textFind = [[TSRegexTextFind alloc] initWithString:text pattern:pattern lineEnding:lineEnding selectedRanges:@[[NSValue valueWithRange:NSMakeRange(0, 0)]] inSelection:NO error:NULL];
    return [textFind matchRangesWithCancellation:nil];
}

/// Line starts of `text` as NSString counts lines.
static NSArray<NSNumber *> *LineStarts(NSString *text) {
    NSMutableArray *starts = [NSMutableArray arrayWithObject:@0];
    NSUInteger i = 0;
    while (i < text.length) {
        NSUInteger end = 0;
        [text getLineStart:NULL end:&end contentsEnd:NULL forRange:NSMakeRange(i, 0)];
        if (end > text.length || end == i) break;
        [starts addObject:@(end)];
        i = end;
    }
    if ([starts.lastObject unsignedIntegerValue] == text.length && starts.count > 1 && text.length > 0) { }   // an empty last line after a line break
    return starts;
}
static BOOL IsLineStart(NSString *text, NSUInteger p) { return p == 0 || p == text.length || [LineStarts(text) containsObject:@(p)]; }
static NSUInteger LineOf(NSString *text, NSUInteger p) {
    NSUInteger start = 0; [text getLineStart:&start end:NULL contentsEnd:NULL forRange:NSMakeRange(p, 0)];
    return [LineStarts(text) indexOfObject:@(start)] + 1;
}
static NSArray<NSString *> *Lines(NSString *text) {
    NSMutableArray *lines = [NSMutableArray array];
    NSArray *starts = LineStarts(text);
    for (NSUInteger k = 0; k < starts.count; k++) {
        NSUInteger s = [starts[k] unsignedIntegerValue], e = k + 1 < starts.count ? [starts[k + 1] unsignedIntegerValue] : text.length;
        if (e > s) [lines addObject:[text substringWithRange:NSMakeRange(s, e - s)]];
    }
    return lines;
}
static NSUInteger LCS(NSArray *a, NSArray *b) {
    NSUInteger n = a.count, m = b.count;
    NSUInteger *t = calloc((n + 1) * (m + 1), sizeof(NSUInteger));
    for (NSUInteger i = 1; i <= n; i++)
        for (NSUInteger j = 1; j <= m; j++)
            t[i * (m + 1) + j] = [a[i - 1] isEqual:b[j - 1]] ? t[(i - 1) * (m + 1) + j - 1] + 1 : MAX(t[(i - 1) * (m + 1) + j], t[i * (m + 1) + j - 1]);
    NSUInteger r = t[n * (m + 1) + m];
    free(t);
    return r;
}
static BOOL EndsWithBreak(NSString *s) {
    if (s.length == 0) return NO;
    unichar c = [s characterAtIndex:s.length - 1];
    return c == '\n' || c == '\r' || c == 0x85 || c == 0x2028 || c == 0x2029;
}

/// Every item of a match result: the highlight is the match, the after text is the lines of the text with only
/// this item replaced, the line number is the match's line, and no text ends with a line break it does not change.
static void CheckMatchItems(TSTeXRootSearchFileResult *file, NSString *label) {
    NSString *text = file.source.text;
    NSUInteger previousEnd = 0;
    for (NSUInteger k = 0; k < file.items.count; k++) {
        TSTeXRootSearchItem *item = file.items[k];
        NSString *w = [NSString stringWithFormat:@"%@ item %lu in %@", label, (unsigned long)k, Q(text)];
        Check(item.range.location >= previousEnd, [w stringByAppendingString:@": items overlap or are out of order"]);
        previousEnd = NSMaxRange(item.range);
        Check(item.lineNumber == LineOf(text, item.range.location), [w stringByAppendingFormat:@": line %lu, not %lu", (unsigned long)item.lineNumber, (unsigned long)LineOf(text, item.range.location)]);
        Check(NSMaxRange(item.beforeHighlight) <= item.beforeText.length && [[item.beforeText substringWithRange:item.beforeHighlight] isEqual:[text substringWithRange:item.range]], [w stringByAppendingString:@": before highlight is not the match"]);
        NSUInteger start = 0; [text getLineStart:&start end:NULL contentsEnd:NULL forRange:item.range];
        Check(start + item.beforeText.length <= text.length && [[text substringWithRange:NSMakeRange(start, item.beforeText.length)] isEqual:item.beforeText], [w stringByAppendingString:@": before text is not the lines"]);
        Check(!EndsWithBreak(item.beforeText) || NSMaxRange(item.beforeHighlight) == item.beforeText.length, [w stringByAppendingFormat:@": before text %@ keeps its last line break", Q(item.beforeText)]);
        if (!item.replacement) { Check(item.afterText == nil, [w stringByAppendingString:@": find mode has an after text"]); continue; }
        Check([[item.afterText substringWithRange:item.afterHighlight] isEqual:item.replacement], [w stringByAppendingString:@": after highlight is not the replacement"]);
        NSString *only = [file textReplacingItemsAtIndexes:[NSIndexSet indexSetWithIndex:k]];
        Check(start + item.afterText.length <= only.length && [[only substringWithRange:NSMakeRange(start, item.afterText.length)] isEqual:item.afterText],
              [w stringByAppendingFormat:@": after text %@ is not the lines of %@", Q(item.afterText), Q(only)]);
        Check(!EndsWithBreak(item.afterText) || NSMaxRange(item.afterHighlight) == item.afterText.length, [w stringByAppendingFormat:@": after text %@ keeps its last line break", Q(item.afterText)]);
    }
}

/// Every hunk: whole lines in both texts, at least one unchanged line between hunks, every hunk on gives `final`,
/// and as few changed lines as the longest common subsequence of lines allows.
static void CheckHunks(TSTeXRootSearchFileResult *file, NSString *final, NSString *label, BOOL minimal) {
    NSString *text = file ? file.source.text : nil;
    if (!file) return;
    NSString *w = [NSString stringWithFormat:@"%@ in %@ → %@", label, Q(text), Q(final)];
    Check([All(file) isEqual:final], [w stringByAppendingFormat:@": every hunk on gives %@", Q(All(file))]);
    NSInteger shift = 0;
    NSUInteger previousEnd = 0, changed = 0;
    BOOL firstHunk = YES;
    for (TSTeXRootSearchItem *item in file.items) {
        NSString *v = [w stringByAppendingFormat:@" hunk %@", NSStringFromRange(item.range)];
        Check(firstHunk || item.range.location > previousEnd, [v stringByAppendingString:@": no unchanged line before it"]);
        Check(IsLineStart(text, item.range.location) && IsLineStart(text, NSMaxRange(item.range)), [v stringByAppendingString:@": not whole lines of the original"]);
        NSUInteger at = (NSUInteger)((NSInteger)item.range.location + shift);
        Check(IsLineStart(final, at) && IsLineStart(final, at + item.replacement.length), [v stringByAppendingString:@": not whole lines of the result"]);
        Check(item.lineNumber == LineOf(text, item.range.location),
              [v stringByAppendingFormat:@": line %lu", (unsigned long)item.lineNumber]);
        Check([[item.beforeText substringWithRange:item.beforeHighlight] length] + [[item.afterText substringWithRange:item.afterHighlight] length] > 0, [v stringByAppendingString:@": nothing highlighted"]);
        Check(item.beforeText.length <= item.range.length && [[text substringWithRange:NSMakeRange(item.range.location, item.beforeText.length)] isEqual:item.beforeText]
              && item.afterText.length <= item.replacement.length && [[item.replacement substringToIndex:item.afterText.length] isEqual:item.afterText], [v stringByAppendingString:@": texts are not the hunk's lines"]);
        Check(!EndsWithBreak(item.beforeText) || NSMaxRange(item.beforeHighlight) == item.beforeText.length, [v stringByAppendingString:@": before keeps its last line break"]);
        changed += Lines([text substringWithRange:item.range]).count + Lines(item.replacement).count;
        shift += (NSInteger)item.replacement.length - (NSInteger)item.range.length;
        previousEnd = NSMaxRange(item.range);
        firstHunk = NO;
    }
    if (minimal) {
        NSArray *a = Lines(text), *b = Lines(final);
        NSUInteger best = a.count + b.count - 2 * LCS(a, b);
        Check(changed == best, [w stringByAppendingFormat:@": %lu changed lines, the fewest is %lu", (unsigned long)changed, (unsigned long)best]);
    }
}

static unsigned Seed = 12345;
static unsigned Rand(unsigned n) { Seed = Seed * 1103515245 + 12345; return (Seed >> 16) % n; }
static NSString *RandomText(NSString *lineEnding, NSUInteger pieces) {
    NSArray *alphabet = @[@"a", @"b", @"c", @"ab", @" ", @"\u00E9", @"e\u0301", @"\n", @"\n", @"aa"];
    NSMutableString *s = [NSMutableString string];
    for (NSUInteger i = 0; i < pieces; i++) [s appendString:alphabet[Rand((unsigned)alphabet.count)]];
    return lineEnding ? TSRegexStringByReplacingLineEndings(s, lineEnding) : s;
}

typedef struct { const char *find, *replace; TSRegexFindOptions options; TSRegexReplacementSyntax syntax; } Case;
static const TSRegexFindOptions RE = TSRegexFindRegularExpression | TSRegexFindAnchorsMatchLines | TSRegexFindUnescapesReplacement;
static const Case Cases[] = {
    {"a", "X", 0, TSRegexReplacementSyntaxICU},
    {"ab", "", 0, TSRegexReplacementSyntaxICU},
    {"a\nb", "Y\nZ", 0, TSRegexReplacementSyntaxICU},
    {"a+", "<$0>", TSRegexFindRegularExpression, TSRegexReplacementSyntaxICU},
    {"(a)(b)?", "$2$1\\n", RE, TSRegexReplacementSyntaxICU},
    {"^", "> ", RE, TSRegexReplacementSyntaxICU},
    {"$", ";", RE, TSRegexReplacementSyntaxICU},
    {"b|$", "|", RE, TSRegexReplacementSyntaxICU},
    {"\\n", " ", RE, TSRegexReplacementSyntaxICU},
    {"c\\n?", "\\-[\\&]", RE, TSRegexReplacementSyntaxOgreKit},
    {"a", "\\`", RE, TSRegexReplacementSyntaxOgreKit},
    {"(?s)a.*?c", "Q\\nQ", RE, TSRegexReplacementSyntaxICU},
    {"\u00E9", "e", TSRegexFindIgnoreDiacritics, TSRegexReplacementSyntaxICU},
    {"x*", "-", RE | TSRegexFindIgnoreEmptyMatches, TSRegexReplacementSyntaxICU},
};

int main(int argc, const char **argv) { @autoreleasepool {
    Folder = [[NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString] stringByResolvingSymlinksInPath];
    [NSFileManager.defaultManager createDirectoryAtPath:Folder withIntermediateDirectories:YES attributes:nil error:NULL];
    NSString *head = @"% !TEX root = root.tex";
    Write(@"root.tex", @"\\documentclass{article}\n\\begin{document}\nabc\n\\end{document}\n", NSUTF8StringEncoding);
    NSArray *endings = @[@"\n", @"\r\n", @"\r"];
    NSMutableArray<NSString *> *randomNames = [NSMutableArray array];
    for (NSUInteger k = 0; k < 90; k++) {
        NSString *name = [NSString stringWithFormat:@"r%03lu.tex", (unsigned long)k];
        NSString *ending = endings[k % 3];
        Write(name, [NSString stringWithFormat:@"%@%@%@", head, ending, RandomText(ending, 3 + Rand(40))], NSUTF8StringEncoding);
        [randomNames addObject:name];
    }
    Write(@"mixed.tex", [head stringByAppendingString:@"\r\nA1\nA2\r\nA3\rA4"], NSUTF8StringEncoding);
    Write(@"crlf.tex", [head stringByAppendingString:@"\r\nfoo\r\nbar\r\n"], NSUTF8StringEncoding);
    Write(@"sjis.tex", [head stringByAppendingString:@"\n\u3042\u3044 abc\n"], CF(kCFStringEncodingShiftJIS));
    Write(@"lossy.tex", [head stringByAppendingString:@"\n\tabc\n"], NSUTF8StringEncoding);
    Write(@"breaks.tex", [head stringByAppendingString:[NSString stringWithFormat:@"\nL2\rL3\r\nL4%CL5%CL6%CL7 x\nL8 x", (unichar)0x85, (unichar)0x2028, (unichar)0x2029]], NSUTF8StringEncoding);
    Collect();
    Check(Files.count == 96, [NSString stringWithFormat:@"collected %lu files", (unsigned long)Files.count]);

    // 1. Find and replace in open documents are Replace All of the panel, with and without the line ending.
    NSUInteger compared = 0;
    for (NSUInteger round = 0; round < 60; round++) {
        NSString *text = RandomText(nil, 1 + Rand(60));
        for (NSString *lineEnding in @[@"\n", [NSNull null]]) {
            NSString *le = [lineEnding isKindOfClass:NSString.class] ? lineEnding : nil;
            for (NSUInteger c = 0; c < sizeof Cases / sizeof Cases[0]; c++) {
                NSString *find = @(Cases[c].find), *replace = @(Cases[c].replace);
                NSString *w = [NSString stringWithFormat:@"open %@ /%@/ → %@ in %@", Q(le ?: @"nil"), Q(find), Q(replace), Q(text)];
                TSTeXRootSearchQuery *fq = [TSTeXRootSearchQuery findQueryWithString:find options:Cases[c].options error:NULL];
                TSTeXRootSearchFileResult *found = One(Open(text, le), fq);
                NSArray *expected = EngineMatches(text, find, Cases[c].options, le);
                NSMutableArray *got = [NSMutableArray array];
                for (TSTeXRootSearchItem *item in found.items) [got addObject:[NSValue valueWithRange:item.range]];
                Check([got isEqual:expected], [w stringByAppendingFormat:@": matches %@, panel %@", got, expected]);
                if (found) CheckMatchItems(found, w);
                TSTeXRootSearchQuery *rq = [TSTeXRootSearchQuery replaceQueryWithString:find replacement:replace options:Cases[c].options syntax:Cases[c].syntax error:NULL];
                TSTeXRootSearchFileResult *replaced = One(Open(text, le), rq);
                NSString *panel = EngineReplaceAll(text, find, replace, Cases[c].options, Cases[c].syntax, le);
                Check([(All(replaced) ?: text) isEqual:panel], [w stringByAppendingFormat:@": gives %@, panel %@", Q(All(replaced) ?: text), Q(panel)]);
                if (replaced) CheckMatchItems(replaced, w);
                compared++;
            }
        }
    }

    // 2. Files on the disk with one kind of line ending are the panel with that line ending.
    TSTeXRootSearchSource *(^disk)(NSString *) = ^(NSString *name) { return Disk(name); };
    for (NSString *name in randomNames) {
        TSTeXRootSearchSource *source = disk(name);
        NSString *text = source.text;
        NSString *le = [TSTeXRootSearch firstLineEndingInText:text];
        for (NSUInteger c = 0; c < sizeof Cases / sizeof Cases[0]; c++) {
            NSString *find = @(Cases[c].find), *replace = @(Cases[c].replace);
            NSString *w = [NSString stringWithFormat:@"%@ /%@/ → %@", name, Q(find), Q(replace)];
            TSTeXRootSearchQuery *rq = [TSTeXRootSearchQuery replaceQueryWithString:find replacement:replace options:Cases[c].options syntax:Cases[c].syntax error:NULL];
            TSTeXRootSearchFileResult *replaced = One(source, rq);
            NSString *panel = EngineReplaceAll(text, find, replace, Cases[c].options, Cases[c].syntax, le);
            Check([(All(replaced) ?: text) isEqual:panel], [w stringByAppendingFormat:@": gives %@, panel %@", Q(All(replaced) ?: text), Q(panel)]);
            if (replaced) CheckMatchItems(replaced, w);
            compared++;
        }
    }

    // 3. Mixed line endings: a line break put in takes the line ending of the match's line, the first one on a last
    //    line without one; the find string takes the file's first line ending.
    TSTeXRootSearchQuery *mixedQuery = [TSTeXRootSearchQuery replaceQueryWithString:@"A(\\d)" replacement:@"B$1\\nC" options:RE syntax:TSRegexReplacementSyntaxICU error:NULL];
    NSString *mixedResult = All(One(disk(@"mixed.tex"), mixedQuery));
    Check([mixedResult hasSuffix:@"\r\nB1\nC\nB2\r\nC\r\nB3\rC\rB4\r\nC"], [@"mixed line endings give " stringByAppendingString:Q(mixedResult)]);
    TSTeXRootSearchQuery *acrossLines = [TSTeXRootSearchQuery findQueryWithString:@"foo\nbar" options:0 error:NULL];
    Check(One(disk(@"crlf.tex"), acrossLines).items.count == 1, @"a line break in the find string does not match a CRLF file");
    TSRegexReplacementRule *mixedRule = [[TSRegexReplacementRule alloc] initWithFindString:@"A(\\d)" replaceString:@"B$1\\nC" usesRegularExpression:YES ignoresCase:NO enabled:YES note:nil];
    TSRegexMultipleReplace *mixedSet = [[TSRegexMultipleReplace alloc] initWithRules:@[mixedRule] textualOptions:0 regularExpressionOptions:TSRegexFindAnchorsMatchLines | TSRegexFindUnescapesReplacement replacementSyntax:TSRegexReplacementSyntaxICU];
    TSTeXRootSearchFileResult *mixedHunks = One(disk(@"mixed.tex"), [TSTeXRootSearchQuery multipleReplaceQueryWithSet:mixedSet]);
    Check([All(mixedHunks) isEqual:mixedResult], [@"a set on mixed line endings gives " stringByAppendingString:Q(All(mixedHunks))]);
    CheckHunks(mixedHunks, mixedResult, @"mixed set", YES);
    Check([[TSTeXRootSearch lineEndingAtIndex:0 inText:@"abc"] isEqual:@"\n"] && [[TSTeXRootSearch firstLineEndingInText:@"a\u2028b\r\n"] isEqual:@"\u2028"]
          && [[TSTeXRootSearch lineEndingAtIndex:5 inText:@"a\r\nb\rc"] isEqual:@"\r\n"] && [[TSTeXRootSearch lineEndingAtIndex:3 inText:@"a\r\nb\rc"] isEqual:@"\r"]
          && [[TSTeXRootSearch firstLineEndingInText:@"a\r"] isEqual:@"\r"], @"line endings at an index");

    // 4. Line numbers with every kind of line break.
    TSTeXRootSearchFileResult *breaks = One(disk(@"breaks.tex"), [TSTeXRootSearchQuery findQueryWithString:@"L\\d" options:RE error:NULL]);
    NSMutableArray *numbers = [NSMutableArray array];
    for (TSTeXRootSearchItem *item in breaks.items) [numbers addObject:@(item.lineNumber)];
    Check([numbers isEqual:@[@2, @3, @4, @5, @6, @7, @8]], [NSString stringWithFormat:@"line numbers %@", numbers]);
    CheckMatchItems(breaks, @"breaks");

    // 5. Multiple replacement: the set applied as the panel applies it, cut into minimal hunks of whole lines.
    NSArray *ruleSets = @[
        @[@[@"a", @"b", @NO], @[@"b", @"c", @NO]],
        @[@[@"a", @"b", @NO], @[@"b", @"a", @NO]],
        @[@[@"\\n", @"", @YES]],
        @[@[@"c", @"c\\nc", @YES], @[@"^b", @"", @YES]],
        @[@[@"(?s)a.*?c", @"a\\nc", @YES]],
        @[@[@"$", @"%", @YES], @[@"%\\n%", @"\\n", @YES]],
        @[@[@"aa", @"", @NO], @[@"\u00E9", @"\u00E8", @NO]],
        @[@[@"", @"z", @NO], @[@"(", @"z", @YES], @[@"b", @"B", @NO]],
    ];
    for (NSUInteger s = 0; s < ruleSets.count; s++) {
        NSMutableArray *rules = [NSMutableArray array];
        for (NSArray *r in ruleSets[s])
            [rules addObject:[[TSRegexReplacementRule alloc] initWithFindString:r[0] replaceString:r[1] usesRegularExpression:[r[2] boolValue] ignoresCase:NO enabled:YES note:nil]];
        TSRegexMultipleReplace *set = [[TSRegexMultipleReplace alloc] initWithRules:rules textualOptions:0 regularExpressionOptions:TSRegexFindAnchorsMatchLines | TSRegexFindUnescapesReplacement replacementSyntax:TSRegexReplacementSyntaxICU];
        TSTeXRootSearchQuery *query = [TSTeXRootSearchQuery multipleReplaceQueryWithSet:set];
        for (NSUInteger round = 0; round < 40; round++) {
            NSString *text = RandomText(nil, 1 + Rand(50));
            for (NSString *le in @[@"\n", @""]) {
                NSString *lineEnding = le.length ? le : nil;
                NSString *panel = [set applyToString:text selectedRanges:@[[NSValue valueWithRange:NSMakeRange(0, 0)]] inSelection:NO lineEnding:lineEnding cancellation:nil].string;
                TSTeXRootSearchFileResult *file = One(Open(text, lineEnding), query);
                if (!file) Check([panel isEqual:text], [NSString stringWithFormat:@"set %lu gives no hunk for %@ → %@", (unsigned long)s, Q(text), Q(panel)]);
                CheckHunks(file, panel, [NSString stringWithFormat:@"set %lu open %@", (unsigned long)s, Q(le)], YES);
                compared++;
            }
        }
        for (NSString *name in randomNames) {
            TSTeXRootSearchSource *source = disk(name);
            NSString *le = [TSTeXRootSearch firstLineEndingInText:source.text];
            NSString *panel = [set applyToString:source.text selectedRanges:@[[NSValue valueWithRange:NSMakeRange(0, 0)]] inSelection:NO lineEnding:le cancellation:nil].string;
            TSTeXRootSearchFileResult *file = One(source, query);
            if (!file) Check([panel isEqual:source.text], [NSString stringWithFormat:@"set %lu gives no hunk in %@", (unsigned long)s, name]);
            CheckHunks(file, panel, [NSString stringWithFormat:@"set %lu %@", (unsigned long)s, name], [le isEqual:@"\n"]);
            compared++;
        }
        if (s == 7) {
            TSTeXRootSearchQuery *q = [TSTeXRootSearchQuery multipleReplaceQueryWithSet:set];
            Check(q.ruleErrors.count == 2 && q.ruleErrors[@0].code == TSRegexFindErrorEmptyFindString && q.ruleErrors[@1].code == TSRegexFindErrorInvalidPattern,
                  [NSString stringWithFormat:@"rule errors %@", q.ruleErrors]);
        }
    }
    // A CR left alone by removing the LF of a CRLF: the hunk is the whole line.
    {
        TSRegexReplacementRule *rule = [[TSRegexReplacementRule alloc] initWithFindString:@"\\n" replaceString:@"" usesRegularExpression:YES ignoresCase:NO enabled:YES note:nil];
        TSRegexMultipleReplace *set = [[TSRegexMultipleReplace alloc] initWithRules:@[rule] textualOptions:0 regularExpressionOptions:0 replacementSyntax:TSRegexReplacementSyntaxICU];
        for (NSString *text in @[@"x\r\ny", @"p\nx\r\ny\nq", @"x\r\n", @"\r\n\r\n"]) {
            NSString *panel = [set applyToString:text selectedRanges:@[[NSValue valueWithRange:NSMakeRange(0, 0)]] inSelection:NO lineEnding:nil cancellation:nil].string;
            CheckHunks(One(Open(text, nil), [TSTeXRootSearchQuery multipleReplaceQueryWithSet:set]), panel, @"half a CRLF", NO);
        }
        TSRegexReplacementRule *insert = [[TSRegexReplacementRule alloc] initWithFindString:@"x" replaceString:@"\\r" usesRegularExpression:YES ignoresCase:NO enabled:YES note:nil];
        TSRegexMultipleReplace *insertSet = [[TSRegexMultipleReplace alloc] initWithRules:@[insert] textualOptions:0 regularExpressionOptions:0 replacementSyntax:TSRegexReplacementSyntaxICU];
        for (NSString *text in @[@"ax\nb", @"a\nx\nb", @"q\nax\nb\nx"]) {
            NSString *panel = [insertSet applyToString:text selectedRanges:@[[NSValue valueWithRange:NSMakeRange(0, 0)]] inSelection:NO lineEnding:nil cancellation:nil].string;
            CheckHunks(One(Open(text, nil), [TSTeXRootSearchQuery multipleReplaceQueryWithSet:insertSet]), panel, @"a CR before a LF", NO);
        }
    }
    // Unchanged lines inside one replacement split it; a long run of changed lines stays one hunk.
    {
        TSRegexReplacementRule *rule = [[TSRegexReplacementRule alloc] initWithFindString:@"(?s)\\\\begin\\{x\\}(.*?)\\\\end\\{x\\}" replaceString:@"\\\\begin{y}$1\\\\end{y}" usesRegularExpression:YES ignoresCase:NO enabled:YES note:nil];
        TSRegexMultipleReplace *set = [[TSRegexMultipleReplace alloc] initWithRules:@[rule] textualOptions:0 regularExpressionOptions:0 replacementSyntax:TSRegexReplacementSyntaxICU];
        NSMutableString *text = [NSMutableString stringWithString:@"top\n\\begin{x}\n"];
        for (NSUInteger k = 0; k < 3000; k++) [text appendFormat:@"line %lu\n", (unsigned long)k];
        [text appendString:@"\\end{x}\nbottom\n"];
        TSTeXRootSearchFileResult *file = One(Open(text, @"\n"), [TSTeXRootSearchQuery multipleReplaceQueryWithSet:set]);
        Check(file.items.count == 2 && file.items[0].lineNumber == 2 && file.items[1].lineNumber == 3003, [NSString stringWithFormat:@"a long replacement gives hunks %@", file.items]);
        NSMutableString *many = [NSMutableString string];
        for (NSUInteger k = 0; k < 3000; k++) [many appendFormat:@"a%lu\n", (unsigned long)k];
        TSRegexReplacementRule *every = [[TSRegexReplacementRule alloc] initWithFindString:@"a" replaceString:@"b" usesRegularExpression:NO ignoresCase:NO enabled:YES note:nil];
        TSRegexMultipleReplace *everySet = [[TSRegexMultipleReplace alloc] initWithRules:@[every] textualOptions:0 regularExpressionOptions:0 replacementSyntax:TSRegexReplacementSyntaxICU];
        TSTeXRootSearchFileResult *all = One(Open(many, @"\n"), [TSTeXRootSearchQuery multipleReplaceQueryWithSet:everySet]);
        Check(all.items.count == 1 && [All(all) isEqual:[many stringByReplacingOccurrencesOfString:@"a" withString:@"b"]], [NSString stringWithFormat:@"3000 changed lines give %lu hunks", (unsigned long)all.items.count]);
        NSMutableString *spaced = [NSMutableString string];
        for (NSUInteger k = 0; k < 3000; k++) [spaced appendFormat:@"a%lu\nkeep\n", (unsigned long)k];
        TSTeXRootSearchFileResult *apart = One(Open(spaced, @"\n"), [TSTeXRootSearchQuery multipleReplaceQueryWithSet:everySet]);
        Check(apart.items.count == 3000 && apart.items[2999].lineNumber == 5999, [NSString stringWithFormat:@"3000 changed lines apart give %lu hunks", (unsigned long)apart.items.count]);
    }
    // Highlights of a hunk are on whole characters: a decomposed é changed to è.
    {
        TSRegexReplacementRule *rule = [[TSRegexReplacementRule alloc] initWithFindString:@"\u0301" replaceString:@"\u0300" usesRegularExpression:NO ignoresCase:NO enabled:YES note:nil];
        TSRegexMultipleReplace *set = [[TSRegexMultipleReplace alloc] initWithRules:@[rule] textualOptions:TSRegexFindLiteral regularExpressionOptions:0 replacementSyntax:TSRegexReplacementSyntaxICU];
        TSTeXRootSearchItem *item = One(Open(@"caf e\u0301!\n", @"\n"), [TSTeXRootSearchQuery multipleReplaceQueryWithSet:set]).items.firstObject;
        Check(NSEqualRanges(item.beforeHighlight, NSMakeRange(4, 2)) && NSEqualRanges(item.afterHighlight, NSMakeRange(4, 2)) && [item.beforeText isEqual:@"caf e\u0301!"],
              [NSString stringWithFormat:@"decomposed highlight %@ %@ %@", NSStringFromRange(item.beforeHighlight), NSStringFromRange(item.afterHighlight), Q(item.beforeText)]);
    }

    // 6. Limits per file and in all; a result at the limit with nothing more has not reached it.
    {
        TSTeXRootSearchQuery *q = [TSTeXRootSearchQuery findQueryWithString:@"a" options:0 error:NULL];
        NSArray *sources = @[Open(@"aaaa", nil), Open(@"aaaa", nil), Open(@"aaa", nil)];
        TSTeXRootSearchResult *r = [TSTeXRootSearch searchSources:sources query:q generation:3 codec:nil maximumItemsPerFile:3 maximumItems:5 cancellation:nil progress:nil];
        Check(r.reachedLimit && r.files.count == 2 && r.files[0].items.count == 3 && r.files[0].truncated && r.files[1].items.count == 2 && r.files[1].truncated && r.numberOfItems == 5,
              [NSString stringWithFormat:@"limits: %lu files, reached %d", (unsigned long)r.files.count, r.reachedLimit]);
        TSTeXRootSearchResult *exact = [TSTeXRootSearch searchSources:@[Open(@"aaa", nil), Open(@"aa", nil)] query:q generation:3 codec:nil maximumItemsPerFile:3 maximumItems:5 cancellation:nil progress:nil];
        Check(!exact.reachedLimit && exact.numberOfItems == 5 && !exact.files[0].truncated, @"exactly the limits count as reached");
        TSTeXRootSearchResult *over = [TSTeXRootSearch searchSources:@[Open(@"aaa", nil), Open(@"aa", nil), Open(@"a", nil)] query:q generation:3 codec:nil maximumItemsPerFile:3 maximumItems:5 cancellation:nil progress:nil];
        Check(over.reachedLimit && over.numberOfItems == 5, @"a match past the limit in all is not noticed");
        TSRegexReplacementRule *every = [[TSRegexReplacementRule alloc] initWithFindString:@"a" replaceString:@"b" usesRegularExpression:NO ignoresCase:NO enabled:YES note:nil];
        TSRegexMultipleReplace *set = [[TSRegexMultipleReplace alloc] initWithRules:@[every] textualOptions:0 regularExpressionOptions:0 replacementSyntax:TSRegexReplacementSyntaxICU];
        TSTeXRootSearchResult *hunks = [TSTeXRootSearch searchSources:@[Open(@"a\n-\na\n-\na\n-\na\n", nil)] query:[TSTeXRootSearchQuery multipleReplaceQueryWithSet:set] generation:3 codec:nil maximumItemsPerFile:3 maximumItems:5 cancellation:nil progress:nil];
        Check(hunks.reachedLimit && hunks.numberOfItems == 3 && hunks.files[0].truncated, @"the limit per file does not hold for hunks");
        Check(r.generation == 3 && r.mode == TSTeXRootSearchModeFind && hunks.mode == TSTeXRootSearchModeMultipleReplace, @"generation and mode");
    }

    // 7. The encoding check: only files on the disk, only replacing, and a reason found when collecting stays.
    {
        TSTeXRootSearchQuery *accent = [TSTeXRootSearchQuery replaceQueryWithString:@"abc" replacement:@"\u00E9" options:0 syntax:TSRegexReplacementSyntaxICU error:NULL];
        TSTeXRootSearchQuery *kana = [TSTeXRootSearchQuery replaceQueryWithString:@"abc" replacement:@"\u304B" options:0 syntax:TSRegexReplacementSyntaxICU error:NULL];
        TSTeXRootSearchQuery *find = [TSTeXRootSearchQuery findQueryWithString:@"abc" options:0 error:NULL];
        Check(One(disk(@"sjis.tex"), accent).searchOnlyReason == TSTeXRootSearchOnlyReasonUnencodable, @"é in a Shift JIS file is not refused");
        Check(One(disk(@"sjis.tex"), kana).searchOnlyReason == TSTeXRootSearchOnlyReasonNone, @"か in a Shift JIS file is refused");
        Check(One(disk(@"sjis.tex"), find).searchOnlyReason == TSTeXRootSearchOnlyReasonNone, @"searching is refused");
        TSTeXRootSearchSource *openSJIS = [[TSTeXRootSearchSource alloc] initWithFile:Files[@"sjis.tex"] openDocumentText:Files[@"sjis.tex"].text lineEnding:@"\n" searchOnlyReason:TSTeXRootSearchOnlyReasonNone];
        Check(One(openSJIS, accent).searchOnlyReason == TSTeXRootSearchOnlyReasonNone, @"an open document is checked against its file's encoding");
        Check(Files[@"lossy.tex"].searchOnlyReason == TSTeXRootSearchOnlyReasonRoundTrip && One(disk(@"lossy.tex"), [TSTeXRootSearchQuery replaceQueryWithString:@"abc" replacement:@"\u00E9" options:0 syntax:TSRegexReplacementSyntaxICU error:NULL]).searchOnlyReason == TSTeXRootSearchOnlyReasonRoundTrip,
              @"the collector's reason is lost");
        TSRegexReplacementRule *rule = [[TSRegexReplacementRule alloc] initWithFindString:@"abc" replaceString:@"\u00E9" usesRegularExpression:NO ignoresCase:NO enabled:YES note:nil];
        TSRegexMultipleReplace *set = [[TSRegexMultipleReplace alloc] initWithRules:@[rule] textualOptions:0 regularExpressionOptions:0 replacementSyntax:TSRegexReplacementSyntaxICU];
        Check(One(disk(@"sjis.tex"), [TSTeXRootSearchQuery multipleReplaceQueryWithSet:set]).searchOnlyReason == TSTeXRootSearchOnlyReasonUnencodable, @"a set's é in a Shift JIS file is not refused");
    }

    // 8. Cancelling, progress, and query errors.
    {
        TSTeXRootSearchQuery *q = [TSTeXRootSearchQuery findQueryWithString:@"a" options:0 error:NULL];
        NSMutableArray *sources = [NSMutableArray array];
        for (NSString *name in randomNames) [sources addObject:disk(name)];
        __block NSUInteger asked = 0, reported = 0, last = 0;
        TSTeXRootSearchResult *cancelled = [TSTeXRootSearch searchSources:sources query:q generation:1 codec:nil maximumItemsPerFile:5000 maximumItems:500000
                                                             cancellation:^BOOL { return ++asked > 20; } progress:^(NSUInteger done, NSUInteger total) { reported++; }];
        Check(cancelled == nil && reported < sources.count, [NSString stringWithFormat:@"cancelled search gave a result after %lu reports", (unsigned long)reported]);
        __block NSUInteger flips = 0;
        TSTeXRootSearchResult *once = [TSTeXRootSearch searchSources:sources query:q generation:1 codec:nil maximumItemsPerFile:5000 maximumItems:500000
                                                        cancellation:^BOOL { return ++flips == 5; } progress:nil];
        Check(once == nil, @"a cancellation that later says NO is forgotten");
        __block NSUInteger calls = 0;
        TSTeXRootSearchResult *inside = [TSTeXRootSearch searchSources:@[Open(@"aaaa", nil)] query:[TSTeXRootSearchQuery findQueryWithString:@"a" options:TSRegexFindRegularExpression error:NULL]
                                                            generation:1 codec:nil maximumItemsPerFile:5000 maximumItems:500000 cancellation:^BOOL { return ++calls == 2; } progress:nil];
        Check(inside == nil && calls >= 2, @"a search cancelled while matching gives a partial result");
        reported = 0;
        TSTeXRootSearchResult *full = [TSTeXRootSearch searchSources:sources query:q generation:1 codec:nil maximumItemsPerFile:5000 maximumItems:500000
                                                        cancellation:^BOOL { return NO; } progress:^(NSUInteger done, NSUInteger total) { reported++; last = done; Check(total == sources.count, @"progress total"); }];
        Check(full != nil && reported == sources.count && last == sources.count, @"progress is not told every source");
        NSError *error = nil;
        Check(![TSTeXRootSearchQuery findQueryWithString:@"" options:0 error:&error] && error.code == TSRegexFindErrorEmptyFindString, @"an empty find string is taken");
        error = nil;
        Check(![TSTeXRootSearchQuery replaceQueryWithString:@"(" replacement:@"" options:TSRegexFindRegularExpression syntax:TSRegexReplacementSyntaxICU error:&error] && error.code == TSRegexFindErrorInvalidPattern, @"an invalid pattern is taken");
    }

    [NSFileManager.defaultManager removeItemAtPath:Folder error:NULL];
    if (failures) { printf("%d failures\n", failures); return 1; }
    printf("PASS: %lu comparisons with the panel's Replace All and Multiple Replace, mixed line endings, minimal hunks of whole lines, limits, encodings, cancelling\n", (unsigned long)compared);
    return 0;
} }
'''

MUTATIONS = {
    'a file on the disk puts in its first line ending': ('TSTeXRootSearch.m', 'return TSRegexStringByReplacingLineEndings(replacement, [self lineEndingAtIndex:index inText:text]);',
                                                         'return TSRegexStringByReplacingLineEndings(replacement, [self firstLineEndingInText:text]);'),
    'find strings keep LF in files on the disk': ('TSTeXRootSearch.m', 'return source.openDocument ? source.lineEnding : [self firstLineEndingInText:source.text];', 'return source.lineEnding;'),
    'the previous match is forgotten': ('TSTeXRootSearch.m', '[template replacementForMatchRange:matchRange result:result inString:text previousMatchEnd:location]',
                                        '[template replacementForMatchRange:matchRange result:result inString:text previousMatchEnd:0]'),
    'the encoding is not checked': ('TSTeXRootSearch.m', '&& ![codec dataForText:', '&& NO && ![codec dataForText:'),
    'open documents are checked against the encoding': ('TSTeXRootSearch.m', 'replacedText && !source.openDocument && codec', 'replacedText && codec'),
    'no limit per file': ('TSTeXRootSearch.m', 'if (ranges.count == perFile || ranges.count == room) {', 'if (ranges.count == room) {'),
    'parts lose their place in the original': ('TSTeXRootSearch.m', '                delta = (NSInteger)(regions[i].oLoc + regions[i].oLen) - (NSInteger)(regions[i].cLoc + regions[i].cLen);\n', ''),
    'a CR before a part ends a line': ('TSTeXRootSearch.m', 'if (!TSIsLineBreak(c) || (c == \'\\r\' && p == r.cLoc))', 'if (!TSIsLineBreak(c))'),
    'parts are never split': ('TSTeXRootSearch.m', '+ (NSUInteger)maximumLineEdits { return 1024; }', '+ (NSUInteger)maximumLineEdits { return 0; }'),
    'a CRLF counts as two lines': ('TSTeXRootSearch.m', "        if (c == '\\n' && i > 0 && CFStringGetCharacterFromInlineBuffer(&counter->buffer, (CFIndex)i - 1) == '\\r')\n            continue;\n", ''),
    'matches keep their last line break': ('TSTeXRootSearch.m', 'NSUInteger textEnd = matchEnd > contentsEnd ? end : contentsEnd;', 'NSUInteger textEnd = end;'),
    'highlights split characters': ('TSTeXRootSearch.m', '        if (start == prefix)\n            break;\n        prefix = start;\n', '        break;\n'),
    'hunks touching are not joined': ('TSTeXRootSearch.m', 'if (last && last->fEnd >= window.fStart) {', 'if (last && last->fEnd > window.fStart) {'),
    'a cancellation is forgotten': ('TSTeXRootSearch.m', 'return cancelled || (isCancelled && (cancelled = isCancelled()));', 'return isCancelled && isCancelled();'),
}


def build(tmp, sources):
    program = tmp / 'probe.m'
    program.write_text(PROGRAM, encoding='utf-8')
    probe = tmp / 'probe'
    compiled = subprocess.run(['xcrun', 'clang', '-fobjc-arc', '-fmodules', '-mmacosx-version-min=14.6', '-Wall', '-Wno-unused-parameter',
                               '-I', str(sources), *include_args(root), str(program), *(str(sources / name) for name in SOURCES),
                               '-framework', 'Foundation', '-o', str(probe)], capture_output=True, text=True)
    if compiled.returncode != 0:
        return None, compiled.stderr
    return probe, ''


def copy_sources(tmp):
    sources = tmp / 'sources'
    sources.mkdir()
    for name, path in SOURCES.items():
        shutil.copy(root / path, sources / name)
    shutil.copy(root / 'Sources/Find/TeXRoot/TSTeXRootSearch.h', sources / 'TSTeXRootSearch.h')
    return sources


def main():
    with tempfile.TemporaryDirectory() as directory:
        tmp = Path(directory)
        sources = copy_sources(tmp)
        probe, errors = build(tmp, sources)
        if not probe:
            print(errors)
            return 1
        result = subprocess.run([str(probe)], capture_output=True, text=True, timeout=600)
        print(result.stdout.strip() or result.stderr.strip())
        if result.returncode != 0:
            return 1
        if '--mutations' not in sys.argv:
            return 0
        survived = []
        for label, (name, old, new) in MUTATIONS.items():
            mutated_dir = tmp / ('m-' + str(abs(hash(label))))
            mutated_dir.mkdir()
            mutated = copy_sources(mutated_dir)
            text = (mutated / name).read_text(encoding='utf-8')
            if text.count(old) != 1:
                print(f'mutation {label!r}: the text to break is found {text.count(old)} times')
                return 1
            (mutated / name).write_text(text.replace(old, new), encoding='utf-8')
            mprobe, errors = build(mutated_dir, mutated)
            if not mprobe:
                print(f'mutation {label!r} does not compile:\n{errors}')
                return 1
            run = subprocess.run([str(mprobe)], capture_output=True, text=True, timeout=600)
            print(f"{'caught' if run.returncode != 0 else 'SURVIVED'}: {label}")
            if run.returncode == 0:
                survived.append(label)
        if survived:
            print(f'{len(survived)} mutations survived')
            return 1
        print(f'PASS: all {len(MUTATIONS)} mutations caught')
    return 0


if __name__ == '__main__':
    sys.exit(main())
