#!/usr/bin/env python3
"""TSTeXRootProjectCollector collects the root and every .tex file below the root's folder whose "% !TEX root"
names the same file, and reads each as TeXShop opens it, strictly, with the round-trip check.

A real folder is built for each run (hidden folders, symbolic and hard links, a backup folder, Shift JIS with a
character that does not round-trip, a byte order mark, CRLF, read-only and unreadable items, the old %SourceDoc
past line 20, an open document whose unsaved text names the root). TSSourceMagicComments, which -dataEncoding: now
uses, is compared with the old code kept below word for word. With --mutations, five broken copies must be caught."""
from pathlib import Path
import os, subprocess, sys, tempfile

root = Path(__file__).resolve().parents[1]
sources = {name: (root / path).read_text(encoding='utf-8') for name, path in {
    'TSTeXRootProject.m': 'Sources/Document/TSTeXRootProject.m',
    'TSRootFileResolver.m': 'Sources/Document/TSRootFileResolver.m',
    'TSSourceMagicComments.m': 'Sources/Document/TSSourceMagicComments.m'}.items()}
headers = [root / 'Sources/Document']

# The encoding part of -[TSDocument dataEncoding:] as it was in TeXShop 6.00 beta 1 (master e4e1dee8): the header text
# and the loop; `encodingString` is what it passed to -stringEncodingForKey:, nil when it set no encoding.
REFERENCE = r'''
#define NSISOLatin9StringEncoding CFStringConvertEncodingToNSStringEncoding(kCFStringEncodingISOLatin9)
static NSString *RefHeader(NSData *theData) {
    NSString *firstBytes; const unsigned char *b = theData.bytes;
    BOOL utf16 = theData.length >= 2 && ((b[0] == 0xFE && b[1] == 0xFF) || (b[0] == 0xFF && b[1] == 0xFE));
    if (utf16) firstBytes = [[NSString alloc] initWithData:theData encoding:NSUnicodeStringEncoding]; else firstBytes = nil;
    if (! firstBytes) firstBytes = [[NSString alloc] initWithData:theData encoding:NSISOLatin9StringEncoding];
    return firstBytes;
}
static NSString *RefEncodingName(NSString *firstBytes, BOOL useOld) {
    NSUInteger length, start, end; BOOL done; NSInteger linesTested, offset; NSString *testString, *encodingString = nil;
    NSRange myRange, theRange, encodingRange, newEncodingRange;
    length = [firstBytes length]; done = NO; linesTested = 0; myRange.location = 0; myRange.length = 1;
    while ((myRange.location < length) && (!done) && (linesTested < 20)) {
        [firstBytes getLineStart: &start end: &end contentsEnd: nil forRange: myRange];
        myRange.location = end; myRange.length = 1; linesTested++;
        theRange.location = start; theRange.length = (end - start);
        testString = [firstBytes substringWithRange: theRange];
        encodingRange = [testString rangeOfString:@"%!TEX encoding ="]; offset = 16;
        if (encodingRange.location == NSNotFound) { encodingRange = [testString rangeOfString:@"% !TEX encoding ="]; offset = 17; }
        if (encodingRange.location != NSNotFound) {
            done = YES;
            newEncodingRange.location = encodingRange.location + offset;
            newEncodingRange.length = [testString length] - newEncodingRange.location;
            if (newEncodingRange.length > 0)
                encodingString = [[testString substringWithRange: newEncodingRange] stringByTrimmingCharactersInSet: [NSCharacterSet whitespaceAndNewlineCharacterSet]];
        } else if (useOld) {
            encodingRange = [testString rangeOfString:@"%&encoding="];
            if (encodingRange.location != NSNotFound) {
                done = YES;
                newEncodingRange.location = encodingRange.location + 11;
                newEncodingRange.length = [testString length] - newEncodingRange.location;
                if (newEncodingRange.length > 0)
                    encodingString = [[testString substringWithRange: newEncodingRange] stringByTrimmingCharactersInSet: [NSCharacterSet whitespaceAndNewlineCharacterSet]];
            }
        }
    }
    return encodingString;
}
'''

PROGRAM = r'''
#import <Foundation/Foundation.h>
#import "TSTeXRootProject.h"
#import "TSSourceMagicComments.h"
#include <sys/stat.h>
#import <CommonCrypto/CommonDigest.h>
REFERENCE
static int failures = 0;
static void Check(BOOL ok, NSString *what) { if (!ok) { if (failures < 30) printf("FAIL: %s\n", what.UTF8String); failures++; } }
static NSStringEncoding CF(CFStringEncoding e) { return CFStringConvertEncodingToNSStringEncoding(e); }
static BOOL ReadsBackslashAsYen(NSStringEncoding e) { CFStringEncoding cf = CFStringConvertNSStringEncodingToEncoding(e); return cf == kCFStringEncodingMacJapanese || cf == kCFStringEncodingShiftJIS_X0213_00; }
static NSMutableSet<NSString *> *DecodedNames;   // files the codec was asked to choose an encoding for
static NSUInteger SavingCalls;                    // round trips made (one saving conversion each)
static TSTeXRootSourceCodec *Codec(void) {
    return [[TSTeXRootSourceCodec alloc] initWithEncodingForData:^NSStringEncoding(NSData *data, NSURL *url) {
        [DecodedNames addObject:url.lastPathComponent];
        if ([url.lastPathComponent isEqual:@"ascii-as-utf16.tex"]) return NSUTF16BigEndianStringEncoding;   // a chosen encoding that does not read ASCII as ASCII
        NSString *name = [TSSourceMagicComments encodingNameInHeaderText:[TSSourceMagicComments headerTextOfData:data] allowingOldHeading:NO];
        if ([name isEqual:@"UTF-8"]) return NSUTF8StringEncoding;
        if ([name isEqual:@"DOSJapanese"]) return CF(kCFStringEncodingDOSJapanese);
        if ([name isEqual:@"MacJapanese"]) return CF(kCFStringEncodingMacJapanese);
        if ([name isEqual:@"UTF-16"]) return NSUnicodeStringEncoding;
        if (data.length >= 2 && ((const unsigned char *)data.bytes)[0] == 0) return NSUTF16BigEndianStringEncoding;   // as a default of UTF-16 would
        return [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] ? NSUTF8StringEncoding : CF(kCFStringEncodingDOSJapanese);
    } textForEditing:^NSString *(NSString *text, NSStringEncoding e) {
        return ReadsBackslashAsYen(e) ? [text stringByReplacingOccurrencesOfString:@"\u00A5" withString:@"\\"] : text;
    } textForSaving:^NSString *(NSString *text, NSStringEncoding e) {
        SavingCalls++;
        return ReadsBackslashAsYen(e) ? [text stringByReplacingOccurrencesOfString:@"\\" withString:@"\u00A5"] : text;
    }];
}
static NSFileManager *FM;
static void Write(NSString *dir, NSString *rel, NSData *data) {
    NSString *p = [dir stringByAppendingPathComponent:rel];
    [FM createDirectoryAtPath:p.stringByDeletingLastPathComponent withIntermediateDirectories:YES attributes:nil error:nil];
    [data writeToFile:p atomically:NO];
}
static NSData *U(NSString *s) { return [s dataUsingEncoding:NSUTF8StringEncoding]; }
#define Bytes(literal) [NSData dataWithBytes:literal length:sizeof(literal) - 1]
static NSArray<NSString *> *Paths(TSTeXRootProject *p) { NSMutableArray *a = [NSMutableArray array]; for (TSTeXRootProjectFile *f in p.files) [a addObject:f.relativePath]; return a; }
static TSTeXRootProjectFile *File(TSTeXRootProject *p, NSString *rel) { for (TSTeXRootProjectFile *f in p.files) if ([f.relativePath isEqual:rel]) return f; return nil; }
static id Identifier(NSString *path) { id i = nil; [[NSURL fileURLWithPath:path] getResourceValue:&i forKey:NSURLFileResourceIdentifierKey error:NULL]; return i; }

static NSData *OneShotSHA(NSData *d) { unsigned char out[32]; CC_SHA256(d.bytes, (CC_LONG)d.length, out); return [NSData dataWithBytes:out length:32]; }
int main(int argc, char **argv) { @autoreleasepool {
    FM = NSFileManager.defaultManager; DecodedNames = [NSMutableSet set];
    // Magic comments: the same name as the old -dataEncoding: loop, including its quirks.
    NSArray *heads = @[@"% !TEX encoding = UTF-8\n", @"%!TEX encoding =UTF-8\n", @"% !TEX encoding =   \n% !TEX encoding = X\n",
        @"% !TEX encoding =", @"x % !TEX encoding = A % !TEX encoding = B\n", @"% !TeX encoding = UTF-8\n", @"%&encoding=MacJapanese\n",
        @"%&encoding=\n% !TEX encoding = Y\n", @"%&encoding=Z\n% !TEX encoding = Y\n", @"% !TEX encoding = A %!TEX encoding = B\n"];
    NSMutableArray *generated = [heads mutableCopy];
    srandom(45);
    NSArray *pieces = @[@"% !TEX encoding = UTF-8", @"%!TEX encoding = DOSJapanese", @"% !TEX encoding =", @"%&encoding=MacJapanese", @"%&encoding=", @"text", @"", @"% !TEX root = a.tex"];
    NSArray *breaks = @[@"\n", @"\r", @"\r\n", @"\u2028"];
    for (int n = 0; n < 3000; n++) { NSMutableString *s = [NSMutableString string]; long lines = random() % 24;
        for (long i = 0; i < lines; i++) { [s appendString:pieces[random() % pieces.count]]; [s appendString:breaks[random() % breaks.count]]; } [generated addObject:s]; }
    for (NSString *h in generated) for (NSNumber *old in @[@NO, @YES]) {
        NSData *d = [h dataUsingEncoding:NSUTF8StringEncoding];
        NSString *a = RefEncodingName(RefHeader(d), old.boolValue), *b = [TSSourceMagicComments encodingNameInHeaderText:[TSSourceMagicComments headerTextOfData:d] allowingOldHeading:old.boolValue];
        Check((a == nil && b == nil) || [a isEqual:b], [NSString stringWithFormat:@"magic %@ old=%@ new=%@", h, a, b]);
    }
    Check([[TSSourceMagicComments encodingNameInHeaderText:@"% !TEX encoding = A %!TEX encoding = B\n" allowingOldHeading:NO] isEqual:@"B"], @"%!TEX encoding is looked for first on a line");
    NSData *u16 = [@"% !TEX encoding = UTF-16\n" dataUsingEncoding:NSUnicodeStringEncoding];
    Check([[TSSourceMagicComments headerTextOfData:u16] isEqual:RefHeader(u16)], @"UTF-16 header text");

    // The project folder.
    NSString *tmp = [[NSString stringWithUTF8String:argv[1]] stringByResolvingSymlinksInPath];
    NSString *D = [tmp stringByAppendingPathComponent:@"Thesis"], *elsewhere = [tmp stringByAppendingPathComponent:@"elsewhere"];
    Write(D, @"main.tex", U(@"\\documentclass{book}\n\\begin{document}\n\\input{chapters/c1}\n\\end{document}\n"));
    Write(D, @"chapters/c1.tex", U(@"% !TEX root = ../main.tex\n\\chapter{One}\\label{eq:main}\n"));
    Write(D, @"chapters/c2.tex", U(@"%!TEX root =../main.tex\r\n\\chapter{Two}\r\n"));
    Write(D, @"chapters/c3.tex", U(@"\\chapter{No root}\n"));
    Write(D, @"chapters/c4.tex", U(@"% !TeX root = ../main.tex\n"));
    Write(D, @"chapters/C5.TEX", U(@"% !TEX root = ../main.tex\n"));
    Write(D, @"chapters/case.tex", U(@"% !TEX root = ../MAIN.tex\n"));
    Write(D, @"chapters/bom.tex", Bytes("\xEF\xBB\xBF% !TEX root = ../main.tex\n\xE7\xAB\xA0\n"));
    Write(D, @"chapters/sjis-ok.tex", Bytes("% !TEX encoding = DOSJapanese\n% !TEX root = ../main.tex\n\x8F\xCD \\section\n"));
    Write(D, @"chapters/sjis-nec.tex", Bytes("% !TEX encoding = DOSJapanese\n% !TEX root = ../main.tex\n\x85\x40\n"));
    Write(D, @"chapters/macjp.tex", Bytes("% !TEX encoding = MacJapanese\n% !TEX root = ../main.tex\n\x5C" "section{\x82\xA0}\n"));
    Write(D, @"chapters/bad.tex", Bytes("% !TEX encoding = UTF-8\n% !TEX root = ../main.tex\n\xFF\xFE\xFD\n"));
    Write(D, @"chapters/ro.tex", U(@"% !TEX root = ../main.tex\n"));
    chmod([D stringByAppendingPathComponent:@"chapters/ro.tex"].fileSystemRepresentation, 0444);
    Write(D, @"chapters/hard-a.tex", U(@"% !TEX root = ../main.tex\nhard\n"));
    link([D stringByAppendingPathComponent:@"chapters/hard-a.tex"].fileSystemRepresentation, [D stringByAppendingPathComponent:@"chapters/hard-b.tex"].fileSystemRepresentation);
    [FM createSymbolicLinkAtPath:[D stringByAppendingPathComponent:@"chapters/sym.tex"] withDestinationPath:@"c1.tex" error:nil];
    Write(elsewhere, @"far.tex", U(@"% !TEX root = ../Thesis/main.tex\n"));
    [FM createSymbolicLinkAtPath:[D stringByAppendingPathComponent:@"linked"] withDestinationPath:elsewhere error:nil];
    [FM createSymbolicLinkAtPath:[tmp stringByAppendingPathComponent:@"alias"] withDestinationPath:D error:nil];
    Write(D, @"chapters/via-alias.tex", U([NSString stringWithFormat:@"%% !TEX root = %@/alias/main.tex\n", tmp]));
    Write(D, @".hidden/h.tex", U(@"% !TEX root = ../main.tex\n"));
    Write(D, @"TeXShop Backups/2026-11-16 22.11.33/chapters/c1.tex", U(@"% !TEX root = ../../../main.tex\n"));
    Write(D, @"sub/TeXShop Backups/x.tex", U(@"% !TEX root = ../../main.tex\n"));
    Write(D, @"other/o.tex", U(@"% !TEX root = ../other-root.tex\n"));
    Write(D, @"other-root.tex", U(@"\\documentclass{article}\n"));
    NSMutableString *deep = [NSMutableString string]; for (int i = 0; i < 22; i++) [deep appendString:@"x\n"];
    Write(D, @"chapters/srcdoc.tex", U([deep stringByAppendingString:@"%SourceDoc ../main.tex\n"]));
    NSMutableString *level = [NSMutableString stringWithString:@"deep"]; NSMutableString *up = [NSMutableString string];
    for (int i = 0; i < 20; i++) { [level appendFormat:@"/d%d", i]; }
    for (int i = 0; i < 21; i++) [up appendString:@"../"];
    Write(D, [level stringByAppendingPathComponent:@"leaf.tex"], U([NSString stringWithFormat:@"%% !TEX root = %@main.tex\n", up]));
    Write(D, @"chapters/open.tex", U(@"\\chapter{Saved without a root line}\n"));
    Write(D, @"locked/inside.tex", U(@"% !TEX root = ../main.tex\n"));
    chmod([D stringByAppendingPathComponent:@"locked"].fileSystemRepresentation, 0000);
    Write(D, @"chapters/noread.tex", U(@"% !TEX root = ../main.tex\n"));
    chmod([D stringByAppendingPathComponent:@"chapters/noread.tex"].fileSystemRepresentation, 0000);

    NSMutableData *big = [NSMutableData dataWithLength:2 * 1024 * 1024]; memset(big.mutableBytes, 'x', big.length);
    NSMutableData *bigOther = [[@"% !TEX root = ../other-root.tex\n" dataUsingEncoding:NSUTF8StringEncoding] mutableCopy]; [bigOther appendData:big];
    Write(D, @"chapters/big-plain.tex", big);
    NSMutableString *late = [NSMutableString stringWithString:@"% !TEX root = ../other-root.tex\n"];
    for (int i = 0; i < 20; i++) [late appendString:@"ascii\n"];
    [late appendString:@"\u65E5\u672C\u8A9E\u306E\u30B3\u30E1\u30F3\u30C8\n"];
    NSMutableData *lateData = [U(late) mutableCopy]; [lateData appendData:big];
    Write(D, @"chapters/late-japanese.tex", lateData);
    Write(D, @"chapters/ascii-as-utf16.tex", U(@"% !TEX root = ../main.tex\n"));
    Write(D, @"chapters/utf16.tex", [@"% !TEX root = ../main.tex\n\\chapter{UTF-16}\n" dataUsingEncoding:NSUTF16BigEndianStringEncoding]);
    NSMutableString *longLines = [NSMutableString string]; NSString *longLine = [@"" stringByPaddingToLength:8192 withString:@"y" startingAtIndex:0];
    for (int i = 0; i < 14; i++) [longLines appendFormat:@"%@\n", longLine];
    Write(D, @"chapters/line15.tex", U([longLines stringByAppendingString:@"% !TEX root = ../main.tex\n"]));
    NSMutableData *far = [NSMutableData data];
    while (far.length < 65536 - 5) [far appendData:U(@"z\n")];
    far.length = 65536 - 5; ((char *)far.mutableBytes)[far.length - 1] = '\n';
    [far appendData:U(@"%SourceDoc ../main.tex\n")];
    Write(D, @"chapters/srcdoc-far.tex", far);
    Write(D, @"chapters/srcdoc-mid.tex", U(@"see %SourceDoc ../main.tex\n%SourceDoc ../main.tex\n"));
    Write(D, @"chapters/big-other.tex", bigOther);
    NSURL *rootURL = [NSURL fileURLWithPath:[D stringByAppendingPathComponent:@"main.tex"]];
    TSTeXRootProjectCollector *collector = [[TSTeXRootProjectCollector alloc] initWithRootURL:rootURL codec:Codec() allowsSourceDoc:NO jobNameToken:@"\\jobname"];
    id openID = Identifier([D stringByAppendingPathComponent:@"chapters/open.tex"]);
    collector.openDocumentTexts = @{openID: @"% !TEX root = ../main.tex\n\\chapter{Edited}\n"};
    __block NSUInteger progressCalls = 0, lastFiles = 0;
    collector.progressHandler = ^(NSUInteger folders, NSUInteger files, NSString *current) { progressCalls++; lastFiles = files; };
    SavingCalls = 0;
    TSTeXRootProject *p = [collector collect];
    Check(p != nil && collector.failure == TSTeXRootCollectionFailureNone, @"collected");
    NSUInteger closedFiles = 0; for (TSTeXRootProjectFile *f in p.files) if (!f.isOpen) closedFiles++;
    Check(SavingCalls == closedFiles, [NSString stringWithFormat:@"round trips only for the files that belong: %lu for %lu", (unsigned long)SavingCalls, (unsigned long)closedFiles]);
    Check(![DecodedNames containsObject:@"big-plain.tex"] && ![DecodedNames containsObject:@"c3.tex"], @"a file without a root marker is not decoded");
    Check(![DecodedNames containsObject:@"big-other.tex"], @"a file naming another root in its head is decided from the head, not decoded");
    Check(![DecodedNames containsObject:@"late-japanese.tex"], @"Japanese after the first 20 lines does not make the file be read whole");
    Check(![Paths(p) containsObject:@"chapters/ascii-as-utf16.tex"], @"the text in the chosen encoding must name the root too");
    Check([Paths(p) containsObject:@"chapters/utf16.tex"], @"UTF-16 without a byte order mark is read properly and belongs");
    Check([Paths(p) containsObject:@"chapters/line15.tex"], @"a root line after long lines, beyond the first piece read, is found");
    NSArray *expected = @[@"main.tex", @".hidden/h.tex", @"chapters/bad.tex", @"chapters/bom.tex", @"chapters/c1.tex", @"chapters/c2.tex",
        @"chapters/case.tex", @"chapters/hard-a.tex", @"chapters/line15.tex", @"chapters/macjp.tex", @"chapters/open.tex", @"chapters/ro.tex", @"chapters/sjis-nec.tex",
        @"chapters/sjis-ok.tex", @"chapters/utf16.tex", @"chapters/via-alias.tex", [level stringByAppendingPathComponent:@"leaf.tex"], @"sub/TeXShop Backups/x.tex"];
    NSArray *actual = Paths(p);
    BOOL caseInsensitive = [FM fileExistsAtPath:[D stringByAppendingPathComponent:@"MAIN.tex"]];
    NSMutableArray *want = [expected mutableCopy]; if (!caseInsensitive) [want removeObject:@"chapters/case.tex"];
    Check([actual isEqual:want], [NSString stringWithFormat:@"files %@", actual]);
    Check(File(p, @"main.tex").isRoot && !File(p, @"chapters/c1.tex").isRoot, @"the root is marked and first");
    Check(File(p, @"chapters/c1.tex").searchOnlyReason == TSTeXRootSearchOnlyReasonNone, @"plain UTF-8 can be replaced");
    Check(File(p, @"chapters/c2.tex").searchOnlyReason == TSTeXRootSearchOnlyReasonNone && [File(p, @"chapters/c2.tex").text containsString:@"\r\n"], @"CRLF kept and round-trips");
    Check(File(p, @"chapters/bom.tex").reading.byteOrderMark == TSTeXRootByteOrderMarkUTF8 && File(p, @"chapters/bom.tex").searchOnlyReason == TSTeXRootSearchOnlyReasonNone, @"UTF-8 byte order mark round-trips");
    Check(File(p, @"chapters/sjis-ok.tex").searchOnlyReason == TSTeXRootSearchOnlyReasonNone && [File(p, @"chapters/sjis-ok.tex").text containsString:@"\u7AE0 \\section"], @"Shift JIS read and round-trips");
    Check(File(p, @"chapters/sjis-nec.tex").searchOnlyReason == TSTeXRootSearchOnlyReasonRoundTrip, @"85 40 does not round-trip: search only");
    Check(File(p, @"chapters/macjp.tex").searchOnlyReason == TSTeXRootSearchOnlyReasonNone && [File(p, @"chapters/macjp.tex").text containsString:@"\\section{\u3042}"], @"Mac Japanese yen read as backslash, written back as 5C");
    Check(File(p, @"chapters/bad.tex").searchOnlyReason == TSTeXRootSearchOnlyReasonUndecodable && !File(p, @"chapters/bad.tex").reading.decodedStrictly, @"invalid UTF-8: search only, read leniently");
    Check(File(p, @"chapters/ro.tex").searchOnlyReason == TSTeXRootSearchOnlyReasonNotWritable, @"read-only file: search only");
    Check(File(p, @"chapters/hard-a.tex").searchOnlyReason == TSTeXRootSearchOnlyReasonHardLink && File(p, @"chapters/hard-b.tex") == nil, @"hard link: one name, search only");
    Check(File(p, @"chapters/open.tex").isOpen && [File(p, @"chapters/open.tex").text containsString:@"Edited"] && File(p, @"chapters/open.tex").reading == nil, @"open document judged by its unsaved text");
    NSData *c1 = [NSData dataWithContentsOfFile:[D stringByAppendingPathComponent:@"chapters/c1.tex"]];
    Check([File(p, @"chapters/c1.tex").sha256 isEqual:OneShotSHA(c1)] && File(p, @"chapters/c1.tex").size == c1.length && File(p, @"chapters/c1.tex").modificationDate, @"hash, size and date");
    Check([[TSTeXRootProjectCollector sha256OfData:bigOther pieceLength:7] isEqual:OneShotSHA(bigOther)] && [[TSTeXRootProjectCollector sha256OfData:bigOther] isEqual:OneShotSHA(bigOther)], @"the hash in pieces is the hash of the whole");
    BOOL lockedFolder = NO, unreadableFile = NO;
    for (TSTeXRootUnreadableItem *u in p.unreadableItems) {
        if ([u.relativePath isEqual:@"locked"] && u.reason == TSTeXRootUnreadableReasonFolder) lockedFolder = YES;
        if ([u.relativePath isEqual:@"chapters/noread.tex"] && u.reason == TSTeXRootUnreadableReasonFile) unreadableFile = YES;
    }
    Check(lockedFolder && unreadableFile, [NSString stringWithFormat:@"unreadable items %@", [p.unreadableItems valueForKey:@"relativePath"]]);
    Check(progressCalls >= 2 && lastFiles >= 20, @"progress");

    // %SourceDoc past line 20 counts only with the old setting.
    TSTeXRootProjectCollector *old = [[TSTeXRootProjectCollector alloc] initWithRootURL:rootURL codec:Codec() allowsSourceDoc:YES jobNameToken:@"\\jobname"];
    NSArray *oldPaths = Paths([old collect]);
    Check([oldPaths containsObject:@"chapters/srcdoc.tex"] && ![actual containsObject:@"chapters/srcdoc.tex"], @"SourceDoc past line 20 only with the old setting");
    Check([oldPaths containsObject:@"chapters/srcdoc-far.tex"], @"SourceDoc split across two pieces of the stream is found");
    Check(![oldPaths containsObject:@"chapters/srcdoc-mid.tex"], @"only the first SourceDoc counts, and it must start its line");

    // Stopping while the line of a %SourceDoc is being read to its end stops reading.
    NSString *S = [tmp stringByAppendingPathComponent:@"stream"];
    Write(S, @"main.tex", U(@"x\n"));
    NSMutableData *sourceDocLine = [NSMutableData data];
    for (int i = 0; i < 25; i++) [sourceDocLine appendData:U(@"line\n")];
    [sourceDocLine appendData:U(@"%SourceDoc ../main.tex ")];
    [sourceDocLine appendData:big]; [sourceDocLine appendData:big];
    Write(S, @"ch/long.tex", sourceDocLine);
    TSTeXRootProjectCollector *streaming = [[TSTeXRootProjectCollector alloc] initWithRootURL:[NSURL fileURLWithPath:[S stringByAppendingPathComponent:@"main.tex"]] codec:Codec() allowsSourceDoc:YES jobNameToken:@"\\jobname"];
    __block NSUInteger reads = 0;
    __weak TSTeXRootProjectCollector *weakStreaming = streaming;
    streaming.pieceReadHandler = ^{ if (++reads == 2) [weakStreaming cancel]; };
    Check([streaming collect] == nil && reads <= 3, [NSString stringWithFormat:@"stopping while reading a long SourceDoc line: %lu reads", (unsigned long)reads]);

    // A child opened as the root: the same project.
    TSTeXRootProjectCollector *other = [[TSTeXRootProjectCollector alloc] initWithRootURL:[NSURL fileURLWithPath:[D stringByAppendingPathComponent:@"other-root.tex"]] codec:Codec() allowsSourceDoc:NO jobNameToken:@"\\jobname"];
    Check([Paths([other collect]) isEqual:(@[@"other-root.tex", @"chapters/big-other.tex", @"chapters/late-japanese.tex", @"other/o.tex"])], @"another root in the same folder has its own files");

    // Cancelling drops the result.
    TSTeXRootProjectCollector *cancelled = [[TSTeXRootProjectCollector alloc] initWithRootURL:rootURL codec:Codec() allowsSourceDoc:NO jobNameToken:@"\\jobname"];
    __weak TSTeXRootProjectCollector *weakCancelled = cancelled;
    cancelled.progressHandler = ^(NSUInteger folders, NSUInteger files, NSString *current) { if (folders >= 2) [weakCancelled cancel]; };
    Check([cancelled collect] == nil && cancelled.cancelled, @"cancelled collection gives nothing");

    // Root problems.
    Check([TSTeXRootProjectCollector problemWithRootURL:[NSURL fileURLWithPath:[D stringByAppendingPathComponent:@"none.tex"]]] == TSTeXRootProblemMissing, @"missing root");
    Check([TSTeXRootProjectCollector problemWithRootURL:[NSURL fileURLWithPath:[D stringByAppendingPathComponent:@"chapters"]]] == TSTeXRootProblemNotRegularFile, @"folder root");
    Write(D, @"refs.bib", U(@"@book{}\n")); Write(D, @"UPPER.TEX", U(@"x\n"));
    Check([TSTeXRootProjectCollector problemWithRootURL:[NSURL fileURLWithPath:[D stringByAppendingPathComponent:@"refs.bib"]]] == TSTeXRootProblemNotTeXFile, @".bib root");
    Check([TSTeXRootProjectCollector problemWithRootURL:[NSURL fileURLWithPath:[D stringByAppendingPathComponent:@"UPPER.TEX"]]] == TSTeXRootProblemNotTeXFile, @"uppercase .TEX root");
    Check([TSTeXRootProjectCollector problemWithRootURL:[NSURL fileURLWithPath:[D stringByAppendingPathComponent:@"chapters/sym.tex"]]] == TSTeXRootProblemNotRegularFile, @"symbolic link root");
    Check([TSTeXRootProjectCollector problemWithRootURL:rootURL] == TSTeXRootProblemNone, @"good root");

    // A root that cannot be read: recorded, and the files that name it are still collected.
    NSString *U3 = [tmp stringByAppendingPathComponent:@"noroot"];
    Write(U3, @"main.tex", U(@"\\documentclass{book}\n")); Write(U3, @"ch/a.tex", U(@"% !TEX root = ../main.tex\n"));
    chmod([U3 stringByAppendingPathComponent:@"main.tex"].fileSystemRepresentation, 0000);
    TSTeXRootProjectCollector *unreadableRoot = [[TSTeXRootProjectCollector alloc] initWithRootURL:[NSURL fileURLWithPath:[U3 stringByAppendingPathComponent:@"main.tex"]] codec:Codec() allowsSourceDoc:NO jobNameToken:@"\\jobname"];
    TSTeXRootProject *q = [unreadableRoot collect];
    chmod([U3 stringByAppendingPathComponent:@"main.tex"].fileSystemRepresentation, 0644);
    Check(q != nil && q.rootFile == nil && [Paths(q) isEqual:@[@"ch/a.tex"]] && [[q.unreadableItems valueForKey:@"relativePath"] containsObject:@"main.tex"], @"unreadable root recorded, its files still collected");

    // Folders whose names are stored composed or decomposed: the relative paths keep their first letters.
    for (NSString *parentName in @[@"caf\u00E9", @"cafe\u0301", @"\u30AC", @"\u30AB\u3099"]) {
        // mkdir with the UTF-8 bytes as they are, so that a composed name stays composed on the disk (the
        // Foundation path functions would store it decomposed).
        mkdir([[tmp stringByAppendingPathComponent:parentName] UTF8String], 0755);
        NSString *P = [[tmp stringByAppendingPathComponent:parentName] stringByAppendingPathComponent:@"Thesis"];
        Write(P, @"main.tex", U(@"x\n")); Write(P, @"chapters/c1.tex", U(@"% !TEX root = ../main.tex\n")); Write(P, @"auxiliary/m.tex", U(@"% !TEX root = ../main.tex\n"));
        TSTeXRootProjectCollector *u = [[TSTeXRootProjectCollector alloc] initWithRootURL:[NSURL fileURLWithPath:[P stringByAppendingPathComponent:@"main.tex"]] codec:Codec() allowsSourceDoc:NO jobNameToken:@"\\jobname"];
        TSTeXRootProject *r = [u collect];
        Check([Paths(r) isEqual:(@[@"main.tex", @"auxiliary/m.tex", @"chapters/c1.tex"])], [NSString stringWithFormat:@"relative paths under %@: %@", parentName, Paths(r)]);
    }

    chmod([D stringByAppendingPathComponent:@"locked"].fileSystemRepresentation, 0755);
    chmod([D stringByAppendingPathComponent:@"chapters/noread.tex"].fileSystemRepresentation, 0644);
    printf("checked %lu magic headers and %lu files\n", (unsigned long)generated.count * 2, (unsigned long)p.files.count);
    return failures ? 1 : 0;
} }
'''

MUTATIONS = {
    # Symbolic links are refused twice (no link, and a regular file); both must go for one to be listed.
    'follow-symlinks': [('if ([values[NSURLIsSymbolicLinkKey] boolValue])\n            continue;', 'if (0)\n            continue;'),
                        ('if (![values[NSURLIsRegularFileKey] boolValue] || ![TSTeXRootProjectCollector isCandidateName:url.lastPathComponent ?: @""])',
                         'if (![TSTeXRootProjectCollector isCandidateName:url.lastPathComponent ?: @""])')],
    'enter-backups': ('if (enumerator.level == 1 && [url.lastPathComponent isEqualToString:TSTeXRootBackupFolderName]) {', 'if (0) {'),
    'any-case-extension': ('[name.pathExtension isEqualToString:@"tex"]', '[name.pathExtension.lowercaseString isEqualToString:@"tex"]'),
    'no-round-trip': ('decodedStrictly:YES roundTrips:[written isEqualToData:data]]', 'decodedStrictly:YES roundTrips:YES]'),
    'hash-copy': ('CC_SHA256_Update(running, (const unsigned char *)bytes + offset, (CC_LONG)length);', 'CC_SHA256_CTX local = *running; CC_SHA256_Update(&local, (const unsigned char *)bytes + offset, (CC_LONG)length);'),
    'judge-with-round-trip': ('[self->_codec readData:data url:url verifyingRoundTrip:NO]', '[self->_codec readData:data url:url verifyingRoundTrip:YES]'),
    'unreadable-root-ends': ('        else if (!self.cancelled)\n            [self addUnreadable:_rootURL', '        else { self.failure = TSTeXRootCollectionFailureCancelled; return nil; }\n        if (0)\n            [self addUnreadable:_rootURL'),
    'relative-by-length': ('    for (NSUInteger i = 0; i < folder.count; i++)\n        if ([parent[i] compare:folder[i]] != NSOrderedSame)\n            return name;\n    NSArray *rest',
                           '    NSString *joined = [[NSString pathWithComponents:parent] stringByAppendingPathComponent:name], *prefix = [_folderURL.path stringByAppendingString:@"/"];\n    if ([joined hasPrefix:prefix]) return [joined substringFromIndex:prefix.length];\n    NSArray *rest'),
    'head-two-lines': ('linesLength = TSTeXRootLengthOfLines(head.bytes, head.length, 20);', 'linesLength = TSTeXRootLengthOfLines(head.bytes, head.length, 2);'),
    'stream-keeps-nothing': ('NSUInteger keep = MIN(buffer.length, markerLength);', 'NSUInteger keep = 0;'),
    'ascii-gate': ('        if (bytes[i] >= 0x80 || bytes[i] == 0x00 || bytes[i] == 0x1B)\n            return NO;\n    return YES;', '        if (0)\n            return NO;\n    return YES;'),
    'whole-head-gate': ('if (!TSTeXRootPlainASCII(lines.bytes, lines.length))', 'if (!TSTeXRootPlainASCII(head.bytes, head.length))'),
    'inner-no-cancel': ('                if (self.cancelled)\n                    return TSTeXRootJudgementNo;\n                NSData *piece = [handle readDataUpToLength:TSTeXRootReadPiece error:outError];', '                NSData *piece = [handle readDataUpToLength:TSTeXRootReadPiece error:outError];'),
    'trust-ascii': ('                    belongs = [self text:judging.text ofURL:url namesRoot:rootIdentifier];', '                    belongs = YES;'),
    'magic-order': ('[line rangeOfString:@"%!TEX encoding ="];\n        NSUInteger offset = 16;', '[line rangeOfString:@"% !TEX encoding ="];\n        NSUInteger offset = 17;'),
}

def run(texts):
    with tempfile.TemporaryDirectory(prefix='texshop-texroot-') as tmp:
        tmp = Path(tmp)
        for name, text in texts.items():
            (tmp / name).write_text(text, encoding='utf-8')
        (tmp / 'test.m').write_text(PROGRAM.replace('REFERENCE', REFERENCE), encoding='utf-8')
        exe = tmp / 'test'
        includes = [a for h in headers for a in ('-I', str(h))]
        subprocess.run(['xcrun', 'clang', '-fobjc-arc', '-Wall', '-Wno-unused-variable', *includes, '-framework', 'Foundation',
                        str(tmp / 'test.m'), *[str(tmp / n) for n in texts], '-o', str(exe)], check=True)
        work = tmp / 'work'; work.mkdir()
        try:
            return subprocess.run([str(exe), str(work)], capture_output=True, text=True, timeout=300)
        finally:
            subprocess.run(['chmod', '-R', 'u+rwx', str(work)], check=False)

if '--mutations' in sys.argv:
    for name, edits in MUTATIONS.items():
        changed = dict(sources)
        for a, b in (edits if isinstance(edits, list) else [edits]):
            target = next(n for n, t in changed.items() if a in t)
            changed[target] = changed[target].replace(a, b, 1)
        if run(changed).returncode == 0:
            raise SystemExit('FAIL: mutation %s was not detected' % name)
        print('detected mutation', name)

r = run(sources)
if r.stdout.strip(): print(r.stdout.strip())
if r.stderr.strip(): print(r.stderr.strip()[-2000:])
if r.returncode:
    raise SystemExit('FAIL: the collector or the magic comments differ from what is expected')
print('PASS: the root and the .tex files naming it are collected and read as TeXShop opens them, with the round-trip check')
