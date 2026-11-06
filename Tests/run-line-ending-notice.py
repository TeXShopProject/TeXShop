#!/usr/bin/env python3
"""A file whose line endings are converted to LF when it is opened is reported once.

The production -lineEndingNoticeForText:URL: of TSDocument runs on texts with LF, CRLF, CR
and mixed line endings, and on a file the user asked not to be told about again."""
from pathlib import Path
import subprocess, tempfile
root = Path(__file__).resolve().parents[1]
s = (root/'Sources/TSDocument.m').read_text(encoding='latin1')
a = s.index('static const char *TSLineEndingNoticeAttribute')
b = s.index('- (void)tryLineEndingNotice:', a)
code = s[a:b]
program = r'''
#import <Foundation/Foundation.h>
#include <sys/xattr.h>
@interface TSDocument : NSObject
- (NSInteger)lineEndingNoticeForText:(NSString *)text URL:(NSURL *)url;
@end
@implementation TSDocument
CODE
@end
int main(int argc, char **argv) { @autoreleasepool {
    TSDocument *doc = [TSDocument new];
    NSURL *plain = [NSURL fileURLWithPath:@(argv[1])], *quiet = [NSURL fileURLWithPath:@(argv[2])];
    struct { NSString *text; NSURL *url; NSInteger expected; const char *name; } cases[] = {
        {@"a\nb\nc\n", plain, 0, "LF only"},
        {@"a\r\nb\r\n", plain, 1, "CRLF"},
        {@"a\rb\r", plain, 2, "CR"},
        {@"a\r\nb\nc\r", plain, 3, "mixed"},
        {@"a\nb\r\n", plain, 3, "LF and CRLF"},
        {@"a\r\nb\r\n", quiet, 0, "CRLF, told not to show again"},
        {@"", plain, 0, "empty"},
    };
    int failures = 0;
    for (size_t i = 0; i < sizeof(cases) / sizeof(cases[0]); i++) {
        NSInteger got = [doc lineEndingNoticeForText:cases[i].text URL:cases[i].url];
        BOOL ok = got == cases[i].expected;
        failures += ! ok;
        printf("%s %-30s -> %ld (expected %ld)\n", ok ? "ok  " : "FAIL", cases[i].name, (long)got, (long)cases[i].expected);
    }
    return failures ? 1 : 0;
}}
'''.replace('CODE', code)
with tempfile.TemporaryDirectory(prefix='texshop-line-ending-notice-') as folder:
    p = Path(folder); (p/'test.m').write_text(program, encoding='latin1')
    plain = p/'plain.tex'; plain.write_text('x')
    quiet = p/'quiet.tex'; quiet.write_text('x')
    subprocess.run(['xattr', '-w', 'org.texshop.line-ending-notice-off', '1', str(quiet)], check=True)
    subprocess.run(['xcrun', 'clang', '-fobjc-arc', '-framework', 'Foundation', str(p/'test.m'), '-o', str(p/'test')], check=True)
    r = subprocess.run([str(p/'test'), str(plain), str(quiet)])
    if r.returncode:
        raise SystemExit('FAIL: line endings are reported wrongly')
    print('PASS: converted line endings are reported once, and not for a file the user silenced')
