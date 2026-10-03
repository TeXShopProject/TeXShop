#!/usr/bin/env python3
# added by Terada: Test the actual syntax-coloring range clamp against out-of-bounds access.
from pathlib import Path
import subprocess
import shutil

root = Path(__file__).resolve().parent.parent
source = (root / 'Sources/TSDocument-Syntax.m').read_text()
start = source.index('    // Clip the given range')
end = source.index('    // NSLog(@"got here");', start)
block = source[start:end]
program = r'''
#import <Cocoa/Cocoa.h>
static BOOL highlight;
static NSString *AlwaysHighlightEnabledKey = @"test";
@interface ProbePreferences : NSObject
- (BOOL)boolForKey:(NSString *)key;
@end
@implementation ProbePreferences
- (BOOL)boolForKey:(NSString *)key { return highlight; }
@end
#define SUD ([ProbePreferences new])
static NSRange observed;
static void checkRange(NSString *textString, NSRange range) {
    NSUInteger length = textString.length;
    NSUInteger aLineStart = 0, aLineEnd = 0;
    observed = NSMakeRange(NSNotFound, 0);
BLOCK
    observed = range;
}
int main(void) {
    @autoreleasepool {
        NSTextStorage *storage = [[NSTextStorage alloc] initWithString:@"abc\ndef\n"];
        NSRange inputs[] = { {0, 8}, {4, 100}, {0, 100}, {7, NSUIntegerMax},
                            {8, 1}, {NSNotFound, 1}, {3, 0} };
        NSRange expected[] = { {0, 8}, {4, 4}, {0, 8}, {7, 1},
                              {NSNotFound, 0}, {NSNotFound, 0}, {3, 0} };
        for (int mode = 1; mode >= 0; mode--) {
            highlight = mode;
            for (int i = 0; i < 7; i++) {
                @try { checkRange(storage.string, inputs[i]); }
                @catch (NSException *e) {
                    fprintf(stderr, "FAIL mode=%d case=%d: %s\n", mode, i, e.description.UTF8String);
                    return 1;
                }
                if (!NSEqualRanges(observed, expected[i])) return 2;
            }
            checkRange(@"", NSMakeRange(0, NSUIntegerMax));
            if (observed.location != NSNotFound) return 3;
        }
        puts("PASS: 16 syntax range cases (highlight ON/OFF, overflow, EOF, empty)");
    }
    return 0;
}
'''.replace('BLOCK', block)
temporary = Path(subprocess.check_output(['mktemp', '-d', '/tmp/texshop-range.XXXXXX'], text=True).strip())
try:
    (temporary / 'test.m').write_text(program)
    subprocess.run(['xcrun', 'clang', '-fobjc-arc', '-framework', 'Cocoa', str(temporary / 'test.m'), '-o', str(temporary / 'test')], check=True)
    subprocess.run([str(temporary / 'test')], check=True)
finally:
    shutil.rmtree(temporary)
