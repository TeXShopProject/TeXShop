#!/usr/bin/env python3
"""Modified NFC composes everything except characters with Full_Composition_Exclusion.
Also checks, over every code point, that the property equals the explicit list the
earlier implementation used, so that current text normalizes exactly as before."""
from pathlib import Path
import re
import subprocess
import sys
import tempfile
from source_tree import git_show, include_args

root = Path(__file__).resolve().parents[1]
old = git_show(root, 'f318be79', 'Sources/Utilities/NSString-Extras.m')
old_class = re.search(r'@"\(\[(.*?)\]\*\)\(\[\^', old).group(1).replace('\\\\', '\\')
program = r'''
#import <Foundation/Foundation.h>
#import "NSString-Extras.h"
static int failures;
static void Check(const char *name, NSString *got, NSString *expected) {
    if (![got isEqualToString:expected]) { printf("FAIL %s: %s\n", name, got.UTF8String); failures++; }
}
static NSIndexSet *Matches(NSString *pattern, NSString *text) {
    NSMutableIndexSet *set = [NSMutableIndexSet indexSet];
    NSRegularExpression *re = [NSRegularExpression regularExpressionWithPattern:pattern options:0 error:NULL];
    for (NSTextCheckingResult *m in [re matchesInString:text options:0 range:NSMakeRange(0, text.length)]) [set addIndexesInRange:m.range];
    return set;
}
int main(int argc, char **argv) { @autoreleasepool {
    Check("U+FA19 alone", [@"神" normalizedStringWithModifiedNFC], @"神");
    Check("U+212B alone", [@"Å" normalizedStringWithModifiedNFC], @"Å");
    Check("U+1F71 alone", [@"ά" normalizedStringWithModifiedNFC], @"ά");
    Check("excluded only, twice", [@"神神" normalizedStringWithModifiedNFC], @"神神");
    Check("U+FA19 then ka + voicing mark", [@"神が" normalizedStringWithModifiedNFC], @"神が");
    Check("a + U+0340", [@"à" normalizedStringWithModifiedNFC], @"à");
    Check("tab, CR and form feed", [@"\t\r\f" normalizedStringWithModifiedNFC], @"\t\r\f");
    Check("empty", [@"" normalizedStringWithModifiedNFC], @"");
    Check("composes around excluded", [@"éÅö" normalizedStringWithModifiedNFC], @"éÅö");
    // Every code point, surrogates excluded.
    NSMutableString *all = [NSMutableString string];
    for (UTF32Char c = 0; c <= 0x10FFFF; c++) {
        if (c >= 0xD800 && c <= 0xDFFF) continue;
        UTF32Char le = NSSwapHostIntToLittle(c);
        [all appendString:[[NSString alloc] initWithBytes:&le length:4 encoding:NSUTF32LittleEndianStringEncoding]];
    }
    NSIndexSet *list = Matches([NSString stringWithFormat:@"[%@]", [NSString stringWithUTF8String:argv[1]]], all);
    NSIndexSet *property = Matches(@"\\p{Full_Composition_Exclusion}", all);
    if (![list isEqualToIndexSet:property]) { printf("FAIL: the earlier list (%lu) differs from Full_Composition_Exclusion (%lu)\n", (unsigned long)list.count, (unsigned long)property.count); failures++; }
    if (failures) return 1;
    printf("PASS: modified NFC cases; Full_Composition_Exclusion equals the earlier list (%lu UTF-16 units) for all code points\n", (unsigned long)property.count);
} return 0; }
'''
with tempfile.TemporaryDirectory(prefix='texshop-modified-nfc-') as tmp:
    (Path(tmp) / 'test.m').write_text(program)
    exe = Path(tmp) / 'test'
    subprocess.run(['xcrun', 'clang', '-w', '-fobjc-arc', '-framework', 'Foundation', *include_args(root), str(Path(tmp) / 'test.m'),
                    str(root / 'Sources/Utilities/NSString-Extras.m'), '-o', str(exe)], check=True)
    result = subprocess.run([str(exe), old_class], capture_output=True, text=True, timeout=300)
    print(result.stdout, end='')
    if result.returncode:
        sys.exit('FAIL')
