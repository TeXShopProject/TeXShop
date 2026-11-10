#!/usr/bin/env python3
"""Saving with utf.sty output writes \\UTF and \\CID only for what they stand for.

The production -[TSEncodingSupport ptexUtfOutput:withEncoding:] is extracted verbatim
and run on an off-screen text view whose font is Menlo, which is not an Adobe-Japan1
font, so its glyph numbers are not CIDs. Preferences stay in memory."""
from pathlib import Path
import re, subprocess, sys, tempfile
from source_tree import include_args

root = Path(__file__).resolve().parents[1]
source = (root / 'Sources/App/TSEncodingSupport.m').read_text()
start = source.index('- (NSData *)ptexUtfOutput:')
method = source[start:source.index('\n}\n', start) + 3]

program = r'''
#import <Cocoa/Cocoa.h>
#import "NSString-CharacterConversion.h"
#import "NSString-Extras.h"
#import "TestAppKitIsolation.h"
NSInteger g_texChar = '\\';
#define SUD TSIsolatedAppKitDefaults
#define AutomaticUTF8MACtoUTF8ConversionKey @"AutomaticUTF8MACtoUTF8Conversion"
#define TSNoByteOrderMark 0
static int failures;
@interface SaveProbe : NSObject
@end
@implementation SaveProbe
- (NSData *)dataForText:(NSString *)text encoding:(NSStringEncoding)encoding byteOrderMark:(NSInteger)mark { return [text dataUsingEncoding:encoding]; }
METHOD
@end
static void Check(NSString *name, NSString *input, NSString *expected, NSTextView *view, SaveProbe *probe) {
    view.string = input;
    NSString *got = [[NSString alloc] initWithData:[probe ptexUtfOutput:view withEncoding:NSUTF8StringEncoding] encoding:NSUTF8StringEncoding];
    if (![got isEqualToString:expected]) { printf("FAIL %s: got %s expected %s\n", name.UTF8String, got.UTF8String, expected.UTF8String); failures++; }
}
int main(void) { @autoreleasepool {
    TSInstallAppKitIsolation();
    [NSApplication sharedApplication]; [NSApp setActivationPolicy:NSApplicationActivationPolicyProhibited];
    SaveProbe *probe = [SaveProbe new];
    NSTextView *view = [[NSTextView alloc] initWithFrame:NSMakeRect(0, 0, 600, 500)];
    view.font = [NSFont fontWithName:@"Menlo" size:12];
    Check(@"character outside JIS X 0208", @"\u9DD7a", @"\\UTF{9DD7}a", view, probe);
    Check(@"line end", @"\u9DD7\nx", @"\\UTF{9DD7}%\nx", view, probe);
    Check(@"non-BMP character", @"\U00020BB7x", @"\\CID{13706}x", view, probe);
    Check(@"registered variation sequence", @"\u8FBB\U000E0101x", @"\\CID{8267}x", view, probe);
    Check(@"registered non-default variation", @"\u845B\U000E0100x", @"\\CID{1481}x", view, probe);
    Check(@"unregistered selector keeps the base", @"\u845B\U000E01EF|\u845B\uFE0F", @"\u845B|\u845B", view, probe);
    Check(@"unregistered selector at line end", @"\u845B\U000E01EF\nx", @"\u845B\nx", view, probe);
    Check(@"combining sequence", @"e\u0301x", @"\\CID{201}x", view, probe);
    // A line break before a combining mark is kept; the mark is written on its own.
    Check(@"line break before a combining mark", @"a\ńb|\r\ń|\t́x", @"a\n\\UTF{0301}b|\r\n\\UTF{0301}|\t\\UTF{0301}x", view, probe);
    Check(@"combining mark alone on a line", @"\ń\nx", @"\n\\UTF{0301}%\nx", view, probe);
    // Known limitation: a sequence Hiragino cannot draw as one glyph (emoji) still gets
    // the editor font's glyph number, as before; the encoding cannot keep it.
    view.string = @"\U0001F600";
    NSString *emoji = [[NSString alloc] initWithData:[probe ptexUtfOutput:view withEncoding:NSUTF8StringEncoding] encoding:NSUTF8StringEncoding];
    if (![emoji hasPrefix:@"\\CID{"]) { printf("FAIL emoji fallback: %s\n", emoji.UTF8String); failures++; }
    if (failures) return 1;
    printf("PASS: utf.sty output writes registered CIDs, keeps the base of unregistered variation sequences\n");
} return 0; }
'''.replace('METHOD', method)

with tempfile.TemporaryDirectory(prefix='texshop-ptex-utf-') as tmp:
    tmp = Path(tmp)
    (tmp / 'probe.m').write_text(program)
    subprocess.run(['xcrun', 'clang', '-fobjc-arc', '-w', '-framework', 'Cocoa', '-framework', 'CoreText',
                    *include_args(root), '-I', str(root / 'Tests'), str(tmp / 'probe.m'),
                    str(root / 'Sources/Utilities/NSString-CharacterConversion.m'),
                    str(root / 'Sources/Utilities/NSString-Extras.m'),
                    str(root / 'Sources/Utilities/NSMutableString-Extras.m'),
                    '-o', str(tmp / 'probe')], check=True)
    result = subprocess.run([str(tmp / 'probe')], capture_output=True, text=True, timeout=120)
    print(result.stdout, end='')
    if result.returncode:
        sys.exit('FAIL')
