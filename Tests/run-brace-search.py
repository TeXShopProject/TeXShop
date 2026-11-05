#!/usr/bin/env python3
"""Matching-brace search used when the cursor moves next to a brace."""
from pathlib import Path
import subprocess, sys, tempfile
root = Path(__file__).resolve().parents[1]
source = (root / 'Sources/TSDocument.m').read_text(encoding='latin-1')
start = source.index('static const NSInteger kTSBraceSearchLimit')
end = source.index('\n}\n', source.index('static NSInteger TSFindMatchingBrace')) + 3
helper = source[start:end]
mutation = sys.argv[1] if len(sys.argv) > 1 else ''
if mutation == 'no-limit':
    helper = helper.replace('if (ABS(location - origin) > limit)', 'if (NO)')
program = r'''
#import <Foundation/Foundation.h>
HELPER
// The previous character-by-character loop, as a reference for equal results.
static NSInteger Reference(NSString *s, NSInteger origin, unichar cur, unichar target, NSInteger inc, unichar esc) {
    NSInteger len = s.length, loc = origin; NSUInteger skip = 0;
    while ((loc += inc) >= 0 && loc < len) {
        unichar c = [s characterAtIndex:loc];
        BOOL notCS = ((loc > 0) ? [s characterAtIndex:loc - 1] : 0) != esc;
        if (c == target && notCS) { if (!skip) return loc; skip += inc; }
        else if (c == cur && notCS) skip -= inc;
    }
    return -1;
}
int main(void) { @autoreleasepool {
    int failures = 0;
    srandom(7);
    const unichar pieces[] = {'{', '}', '\\', 'a', ' ', '{', '}'};
    for (int n = 0; n < 20000; n++) {
        NSMutableString *s = [NSMutableString string];
        int len = 1 + (int)(random() % 60);
        for (int i = 0; i < len; i++) [s appendFormat:@"%C", pieces[random() % 7]];
        for (NSInteger o = 0; o < (NSInteger)s.length; o++) {
            unichar c = [s characterAtIndex:o];
            if (c != '{' && c != '}') continue;
            NSInteger inc = c == '{' ? 1 : -1; unichar t = c == '{' ? '}' : '{';
            NSInteger a = TSFindMatchingBrace(s, o, c, t, inc, '\\', kTSBraceSearchLimit), b = Reference(s, o, c, t, inc, '\\');
            if (a != b) { if (failures++ < 5) printf("FAIL: mismatch in \"%s\" at %ld: %ld vs %ld\n", s.UTF8String, (long)o, (long)a, (long)b); }
        }
    }
    // A partner far beyond the limit, and a missing partner, in a long text.
    NSMutableString *big = [NSMutableString stringWithString:@"{"];
    for (int i = 0; i < 400000; i++) [big appendString:@"abcdefghi\n"];
    NSString *far = [big stringByAppendingString:@"}"];
    NSDate *t0 = [NSDate date];
    NSInteger r1 = TSFindMatchingBrace(far, 0, '{', '}', 1, '\\', kTSBraceSearchLimit);
    NSInteger r2 = TSFindMatchingBrace(big, 0, '{', '}', 1, '\\', kTSBraceSearchLimit);
    NSInteger r3 = TSFindMatchingBrace(far, far.length - 1, '}', '{', -1, '\\', kTSBraceSearchLimit);
    NSTimeInterval elapsed = -[t0 timeIntervalSinceNow];
    if (r1 != kTSBraceSearchGaveUp || r2 != kTSBraceSearchGaveUp || r3 != kTSBraceSearchGaveUp) { printf("FAIL: limit not applied (%ld %ld %ld)\n", (long)r1, (long)r2, (long)r3); failures++; }
    NSInteger r4 = TSFindMatchingBrace(far, 0, '{', '}', 1, '\\', 10000000);
    if (r4 != (NSInteger)far.length - 1) { printf("FAIL: far partner not found without limit\n"); failures++; }
    if (elapsed > 0.2) { printf("FAIL: limited search took %.3f s\n", elapsed); failures++; }
    printf("limited searches over %lu characters: %.1f ms\n", (unsigned long)far.length, elapsed * 1000);
    return failures ? 1 : 0;
} }
'''.replace('HELPER', helper)
with tempfile.TemporaryDirectory(prefix='texshop-brace-') as tmp:
    src, exe = Path(tmp) / 'test.m', Path(tmp) / 'test'
    src.write_text(program)
    subprocess.run(['xcrun', 'clang', '-O0', '-w', '-fobjc-arc', '-framework', 'Foundation', str(src), '-o', str(exe)], check=True)
    r = subprocess.run([str(exe)], capture_output=True, text=True)
    print(r.stdout.strip())
    if mutation:
        if r.returncode == 0: raise SystemExit('FAIL: mutation %s was not detected' % mutation)
        print('detected mutation', mutation)
    elif r.returncode:
        raise SystemExit(r.stderr)
    else:
        print('PASS: same partners as the previous loop on random input; long searches stop at the limit')
