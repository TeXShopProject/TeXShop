#!/usr/bin/env python3
"""Output, logs and unknown encoding names fall back to UTF-8 rather than Latin 9.

The production helpers of TSEncodingSupport run on console output and logs that are not
in the document's encoding, on output split in the middle of a character, and on an
unknown encoding name. No alert is shown: the alert function is replaced by a message."""
from pathlib import Path
import subprocess, tempfile
root = Path(__file__).resolve().parents[1]
s = (root/'Sources/TSEncodingSupport.m').read_text(encoding='latin1')
table = s[s.index('typedef struct {'):s.index('+ (void)initialize')]
a = s.index('// UTF-8 in which each byte that does not start or continue a valid character is replaced')
helpers = s[a:s.index('// The byte order mark that starts data', a)]
lookup = s[s.index('- (NSStringEncoding)stringEncodingForKey: (NSString *)key'):s.index('- (NSString *)keyForStringEncoding:')]
names = s[s.index('myArray = [NSMutableArray arrayWithObjects:'):]
names = names[names.index('@"MacOSRoman"'):names.index('nil];')]
texworks = s[s.index('texWorksArray = [NSMutableArray arrayWithObjects:'):]
texworks = texworks[texworks.index('@"'):texworks.index('nil];')]
fallback = s[s.index('        // An unknown encoding name falls back to UTF-8.'):]
fallback = fallback[:fallback.index('self.defaultEncodingNumber = i;') + len('self.defaultEncodingNumber = i;')]
program = r'''
#import <Foundation/Foundation.h>
#define ARRAYSIZE(x) ((NSInteger)(sizeof(x)/sizeof(x[0])))
#define NSRunAlertPanel(title, message, ...) (fprintf(stderr, "alert: %s\n", [message UTF8String]), 0)
@interface TSEncodingSupport : NSObject
@property NSArray *availableEncodingsNames, *availableTexworksEncodingNames;
@property NSInteger defaultEncodingNumber;
+ (NSString *)displayStringForData:(NSData *)data encoding:(NSStringEncoding)encoding;
+ (NSUInteger)lengthOfIncompleteCharacterAtEndOfData:(NSData *)data encoding:(NSStringEncoding)encoding;
- (NSStringEncoding)stringEncodingForKey:(NSString *)key;
@end
@implementation TSEncodingSupport
TABLE
+ (void)initialize {
    for (NSInteger i = 0; i < ARRAYSIZE(_availableEncodings); ++i)
        _availableEncodings[i].nsEnc = CFStringConvertEncodingToNSStringEncoding(_availableEncodings[i].cfEnc);
    for (NSInteger i = 0; i < ARRAYSIZE(_availableTexworksEncodings); ++i)
        _availableTexworksEncodings[i].nsEnc = CFStringConvertEncodingToNSStringEncoding(_availableTexworksEncodings[i].cfEnc);
}
- (instancetype)init {
    self = [super init];
    self.availableEncodingsNames = @[NAMES];
    self.availableTexworksEncodingNames = @[TEXWORKS];
FALLBACK
    return self;
}
HELPERS
LOOKUP
@end
static int failures = 0;
static void check(BOOL ok, NSString *what) { printf("%s %s\n", ok ? "ok  " : "FAIL", what.UTF8String); failures += ! ok; }
static NSData *B(const char *bytes) { return [NSData dataWithBytes:bytes length:strlen(bytes)]; }
int main(int argc, char **argv) { @autoreleasepool {
    NSStringEncoding utf8 = NSUTF8StringEncoding, sjis = CFStringConvertEncodingToNSStringEncoding(kCFStringEncodingDOSJapanese);
    NSString *aiu = @"\u3042\u3044\u3046";   // three hiragana
    NSData *aiuUTF8 = [aiu dataUsingEncoding:utf8];
    // Display strings.
    check([[TSEncodingSupport displayStringForData:aiuUTF8 encoding:utf8] isEqualToString:aiu], @"UTF-8 output of a UTF-8 document");
    check([[TSEncodingSupport displayStringForData:aiuUTF8 encoding:sjis] isEqualToString:aiu], @"UTF-8 output of a Shift JIS document reads as UTF-8");
    NSMutableData *cut = [NSMutableData dataWithData:[@"! Undefined control sequence. \u3042\u3044" dataUsingEncoding:utf8]];
    [cut appendBytes:"\xE3\x81" length:2];   // TeX cut the next character in two
    [cut appendData:[@"\nl.3 \u65e5\u672c\u8a9e\n" dataUsingEncoding:utf8]];
    NSString *shown = [TSEncodingSupport displayStringForData:cut encoding:utf8];
    check([shown containsString:@"\u3042\u3044\ufffd"] && [shown containsString:@"\u65e5\u672c\u8a9e"], @"a log with a character cut in two keeps the Japanese around it");
    check([[TSEncodingSupport displayStringForData:B("caf\xE9 cr\xE8me") encoding:utf8] isEqualToString:@"caf\u00e9 cr\u00e8me"], @"Latin output that is not UTF-8 reads as Latin 9");
    check([[TSEncodingSupport displayStringForData:B("") encoding:utf8] isEqualToString:@""], @"empty output");
    // Characters split between pieces of output.
    check([TSEncodingSupport lengthOfIncompleteCharacterAtEndOfData:B("ab\xE3\x81") encoding:utf8] == 2, @"UTF-8: two bytes of a three-byte character are kept");
    check([TSEncodingSupport lengthOfIncompleteCharacterAtEndOfData:aiuUTF8 encoding:utf8] == 0, @"UTF-8: complete output keeps nothing");
    check([TSEncodingSupport lengthOfIncompleteCharacterAtEndOfData:B("ab\x82") encoding:sjis] == 3, @"Shift JIS: an unfinished line with bytes beyond ASCII is kept whole");
    check([TSEncodingSupport lengthOfIncompleteCharacterAtEndOfData:B("x\x82\x60\nab") encoding:sjis] == 0, @"Shift JIS: an unfinished line of ASCII is not kept");
    check([TSEncodingSupport lengthOfIncompleteCharacterAtEndOfData:B("a\xFF\xFE b") encoding:utf8] == 0, @"broken bytes inside the output are not kept");
    // Output split at every byte reads back whole when carried as TeXShop does.
    NSData *whole = [@"\u65e5\u672c\u8a9e: \u5b8c\u74a7\u306a\u725b\u4e3c\n" dataUsingEncoding:utf8];
    NSMutableString *joined = [NSMutableString string];
    NSData *carry = nil;
    for (NSUInteger i = 0; i < whole.length; i++) {
        NSMutableData *piece = [NSMutableData dataWithData:carry ?: [NSData data]];
        [piece appendData:[whole subdataWithRange:NSMakeRange(i, 1)]];
        NSUInteger incomplete = [TSEncodingSupport lengthOfIncompleteCharacterAtEndOfData:piece encoding:utf8];
        carry = incomplete ? [piece subdataWithRange:NSMakeRange(piece.length - incomplete, incomplete)] : nil;
        NSData *ready = [piece subdataWithRange:NSMakeRange(0, piece.length - incomplete)];
        if (ready.length) [joined appendString:[TSEncodingSupport displayStringForData:ready encoding:utf8]];
    }
    check([joined isEqualToString:[[NSString alloc] initWithData:whole encoding:utf8]], @"output arriving one byte at a time reads back whole");
    // TeX breaks long lines after a number of bytes, inside a character (tex-jp-build PR #198).
    NSString *path = @"/tmp/\u65e5\u672c\u8a9e\u65e5\u672c\u8a9e\u65e5\u672c\u8a9e\u65e5\u672c\u8a9e\u65e5\u672c\u8a9e\u65e5\u672c\u8a9e\u65e5\u672c\u8a9e\u65e5\u672c\u8a9e/test.tex";
    NSArray *texLines = @[[@"(" stringByAppendingString:path], [path stringByAppendingString:@":1: Undefined control sequence."], @"l.1 \\hoge", @"", @"No pages of output."];
    NSMutableData *wrapped = [NSMutableData data];
    for (NSString *line in texLines) {
        NSData *d = [line dataUsingEncoding:utf8];
        for (NSUInteger at = 0; at < d.length; at += 60) {
            if (at) [wrapped appendBytes:"\n" length:1];
            [wrapped appendData:[d subdataWithRange:NSMakeRange(at, MIN(60, d.length - at))]];
        }
        [wrapped appendBytes:"\n" length:1];
    }
    check([[NSString alloc] initWithData:wrapped encoding:utf8] == nil, @"the wrapped output is not UTF-8 as it stands");
    NSString *unwrapped = [[texLines componentsJoinedByString:@""] stringByReplacingOccurrencesOfString:@"\n" withString:@""];
    for (NSNumber *e in @[@(utf8), @(sjis)]) {
        NSStringEncoding enc = e.unsignedIntegerValue;
        shown = [TSEncodingSupport displayStringForData:wrapped encoding:enc];
        check(! [shown containsString:@"\ufffd"] && [[shown stringByReplacingOccurrencesOfString:@"\n" withString:@""] isEqualToString:unwrapped]
              && [shown containsString:@"\u8a9e/test.tex:1: Undefined control sequence.\nl.1"],
              [NSString stringWithFormat:@"a line break inside a character is moved before it (%@ document)", enc == utf8 ? @"UTF-8" : @"Shift JIS"]);
    }
    // The same output arriving one byte at a time, carried as TeXShop does, with what is
    // still kept shown when the output ends.
    for (NSUInteger step = 1; step <= 7; step++) {
        joined = [NSMutableString string]; carry = nil;
        for (NSUInteger i = 0; i < wrapped.length; i += step) {
            NSMutableData *piece = [NSMutableData dataWithData:carry ?: [NSData data]];
            [piece appendData:[wrapped subdataWithRange:NSMakeRange(i, MIN(step, wrapped.length - i))]];
            NSUInteger incomplete = [TSEncodingSupport lengthOfIncompleteCharacterAtEndOfData:piece encoding:utf8];
            carry = incomplete ? [piece subdataWithRange:NSMakeRange(piece.length - incomplete, incomplete)] : nil;
            NSData *ready = [piece subdataWithRange:NSMakeRange(0, piece.length - incomplete)];
            if (ready.length) [joined appendString:[TSEncodingSupport displayStringForData:ready encoding:utf8]];
        }
        if (carry) [joined appendString:[TSEncodingSupport displayStringForData:carry encoding:utf8]];
        check([joined isEqualToString:[TSEncodingSupport displayStringForData:wrapped encoding:utf8]],
              [NSString stringWithFormat:@"wrapped output arriving %lu byte(s) at a time reads as a whole", (unsigned long)step]);
    }
    check([TSEncodingSupport lengthOfIncompleteCharacterAtEndOfData:B("ab\xE6\n") encoding:utf8] == 2, @"a character broken by a line break at the end is kept with the break");
    check([TSEncodingSupport lengthOfIncompleteCharacterAtEndOfData:B("ab\xE6\n\x97") encoding:utf8] == 3, @"and so is its continuation after the break");
    check([TSEncodingSupport lengthOfIncompleteCharacterAtEndOfData:B("\xFF ok\n? ") encoding:utf8] == 0, @"a prompt waiting for input is not kept");
    check([TSEncodingSupport lengthOfIncompleteCharacterAtEndOfData:B("ab\xE6\nxy") encoding:utf8] == 0, @"a broken line followed by another line is not kept");
    // Broken bytes spoil only their own line.
    shown = [TSEncodingSupport displayStringForData:B("ab\xE6\nxyz") encoding:utf8];
    check(shown.length == 7 && [shown hasPrefix:@"ab"] && [shown hasSuffix:@"\nxyz"], @"a lead byte that the next line does not continue stays where it is");
    NSMutableData *mixed = [NSMutableData dataWithData:[@"\u65e5\u672c\u8a9e\n" dataUsingEncoding:utf8]];
    [mixed appendBytes:"caf\xE9\n\xFF\xFE\xFD\xFC\xFB\xFA\n" length:12];
    [mixed appendData:[@"\u725b\u4e3c\n" dataUsingEncoding:utf8]];
    check([[TSEncodingSupport displayStringForData:mixed encoding:utf8] isEqualToString:@"\u65e5\u672c\u8a9e\ncaf\u00e9\n\u00ff\u00fe\u00fd\u00fc\u00fb\u00fa\n\u725b\u4e3c\n"],
          @"Latin and broken lines between UTF-8 lines spoil only themselves");
    NSData *sjisText = [@"\u65e5\u672c\u8a9e\n\uff76\uff85\n" dataUsingEncoding:sjis];
    check([[TSEncodingSupport displayStringForData:sjisText encoding:sjis] isEqualToString:@"\u65e5\u672c\u8a9e\n\uff76\uff85\n"], @"Shift JIS output of a Shift JIS document is left alone");
    // Unknown encoding names.
    TSEncodingSupport *support = [TSEncodingSupport new];
    check([support stringEncodingForKey:@"UTF8"] == utf8, @"an unknown encoding name falls back to UTF-8");
    check([support stringEncodingForKey:@"GB 2312"] == CFStringConvertEncodingToNSStringEncoding(kCFStringEncodingEUC_CN), @"GB 2312 is EUC-CN");
    return failures ? 1 : 0;
}}
'''.replace('TABLE', table).replace('HELPERS', helpers).replace('LOOKUP', lookup).replace('NAMES', names).replace('TEXWORKS', texworks).replace('FALLBACK', fallback)
with tempfile.TemporaryDirectory(prefix='texshop-utf8-fallbacks-') as folder:
    p = Path(folder); (p/'test.m').write_text(program, encoding='latin1')
    subprocess.run(['xcrun', 'clang', '-fobjc-arc', '-framework', 'Foundation', str(p/'test.m'), '-o', str(p/'test')], check=True)
    r = subprocess.run([str(p/'test')])
    if r.returncode:
        raise SystemExit('FAIL: output, logs or encoding names fall back wrongly')
    print('PASS: output, logs and unknown encoding names fall back to UTF-8')
