#!/usr/bin/env python3
"""TeX's backslash and tilde are written as the bytes 0x5C and 0x7E in Japanese encodings.

Mac Japanese and Shift JIS X0213 read 0x5C as a yen sign and write a typed backslash as
another byte (0x80, or the full-width backslash 81 5F); Shift JIS X0213 also reads 0x7E as
an overline and writes a typed tilde as the wave dash 81 60. Windows Shift JIS, EUC-JP and
ISO-2022-JP cannot write a yen sign, which TeXShop types for a backslash in its Mac Japanese
mode. The production code of TSEncodingSupport reads sample files as the editor shows them,
in both modes, adds text as it is typed in that mode, and saves. Every backslash, yen sign
used for one, and tilde must come out as 0x5C and 0x7E, and a file saved unchanged must keep
its bytes. --mutation=save or --mutation=read removes the conversion on that side."""
from pathlib import Path
import subprocess, sys, tempfile
root = Path(__file__).resolve().parents[1]
mutation = next((a.split('=', 1)[1] for a in sys.argv[1:] if a.startswith('--mutation=')), None)
s = (root/'Sources/App/TSEncodingSupport.m').read_text(encoding='latin1')
table = s[s.index('typedef struct {'):s.index('// List of the supported encodings.', s.index('static TSEncoding _availableEncodings[]'))]
start = s.index('- (BOOL)isAvailableEncoding:(NSStringEncoding)encoding')
code = s[start:s.index('- (BOOL)ptexUtfOutputCheck:', start)]
mutations = {
    'save': ('\ttext = TSTextForSaving(text, encoding);\n', ''),
    'read': ('- (NSString *)textForEditing:(NSString *)text encoding:(NSStringEncoding)encoding\n{\n', '- (NSString *)textForEditing:(NSString *)text encoding:(NSStringEncoding)encoding\n{\n\treturn text;\n'),
}
if mutation:
    old, new = mutations[mutation]; assert old in code, mutation; code = code.replace(old, new)

YEN, BS = '\u00a5', '\\'
# (name, encoding, Mac Japanese mode, file bytes, typed text, bytes after saving, character the editor shows for 0x5C)
kanji = b'\x88\x9f'  # the kanji 亜 in Shift JIS
cases = [
    ('x0213', 0x0628, 0, b'\\section{' + kanji + b'}~\n', BS + 'textbf{a}~', b'\\section{' + kanji + b'}~\n\\textbf{a}~', BS),
    ('macjapanese', 0x0001, 0, b'\\section{' + kanji + b'}~\n', BS + 'textbf{a}~', b'\\section{' + kanji + b'}~\n\\textbf{a}~', BS),
    ('x0213-yen-mode', 0x0628, 1, b'\\section{' + kanji + b'}~\n', YEN + 'textbf{a}~', b'\\section{' + kanji + b'}~\n\\textbf{a}~', YEN),
    ('macjapanese-yen-mode', 0x0001, 1, b'\\section{' + kanji + b'}\n', YEN + 'textbf{a}' + BS + 'b', b'\\section{' + kanji + b'}\n\\textbf{a}\\b', YEN),
    ('windows-sjis-yen-mode', 0x0420, 1, b'\\section{' + kanji + b'}~\n', YEN + 'textbf{a}~', b'\\section{' + kanji + b'}~\n\\textbf{a}~', YEN),
    ('euc-yen-mode', 0x0920, 1, b'\\section{\xb0\xa1}~\n', YEN + 'textbf{a}', b'\\section{\xb0\xa1}~\n\\textbf{a}', YEN),
    ('windows-sjis', 0x0420, 0, b'\\section{' + kanji + b'}~\n', BS + 'textbf{a}' + YEN, b'\\section{' + kanji + b'}~\n\\textbf{a}\\', BS),
    ('jis-yen-mode', 0x0820, 1, b'\\section{\x1b$B0!\x1b(B}\n', YEN + 'textbf{a}', b'\\section{\x1b$B0!\x1b(B}\n\\textbf{a}', YEN),
    # Full-width backslash and wave dash stay full-width.
    ('x0213-full-width', 0x0628, 0, b'\\section{\x81\x5f\x81\x60}\n', '\uff3c\u301c', b'\\section{\x81\x5f\x81\x60}\n\x81\x5f\x81\x60', BS),
    # UTF-8 writes a yen sign as a yen sign.
    ('utf8', 0x08000100, 0, '\\section{亜}~\n'.encode(), BS + 'a' + YEN, '\\section{亜}~\n\\a¥'.encode(), BS),
]
program = r'''
#import <Foundation/Foundation.h>
#include <sys/xattr.h>
#define ARRAYSIZE(x) ((NSInteger)(sizeof(x)/sizeof(x[0])))
typedef enum { kNoFilterMode = 0, kMacJapaneseFilterMode = 1, kOtherJapaneseFilterMode = 2 } TSFilterMode;
static TSFilterMode g_shouldFilter = kNoFilterMode;
typedef NS_ENUM(NSInteger, TSByteOrderMark) { TSNoByteOrderMark = 0, TSUTF8ByteOrderMark, TSUTF16BigEndianByteOrderMark, TSUTF16LittleEndianByteOrderMark };
@interface TSEncodingSupport : NSObject
- (NSData *)dataForText:(NSString *)text encoding:(NSStringEncoding)encoding byteOrderMark:(TSByteOrderMark)mark;
- (NSString *)textForEditing:(NSString *)text encoding:(NSStringEncoding)encoding;
@end
@implementation TSEncodingSupport
TABLE
+ (void)initialize {
    for (NSInteger i = 0; i < ARRAYSIZE(_availableEncodings); ++i)
        _availableEncodings[i].nsEnc = CFStringConvertEncodingToNSStringEncoding(_availableEncodings[i].cfEnc);
}
CODE
@end
int main(int argc, char **argv) { @autoreleasepool {
    // argv: file encodingCF macJapaneseMode typedFile expectedFile shownCharacterFile
    NSData *data = [NSData dataWithContentsOfFile:@(argv[1])];
    NSStringEncoding encoding = CFStringConvertEncodingToNSStringEncoding((CFStringEncoding)strtoul(argv[2], 0, 0));
    g_shouldFilter = atoi(argv[3]) ? kMacJapaneseFilterMode : kNoFilterMode;
    NSString *typed = [NSString stringWithContentsOfFile:@(argv[4]) encoding:NSUTF8StringEncoding error:NULL];
    NSData *expected = [NSData dataWithContentsOfFile:@(argv[5])];
    NSString *shown = [NSString stringWithContentsOfFile:@(argv[6]) encoding:NSUTF8StringEncoding error:NULL];
    TSEncodingSupport *support = [TSEncodingSupport new];
    NSString *text = [support textForEditing:[[NSString alloc] initWithData:data encoding:encoding] encoding:encoding];
    BOOL showsOne = [text hasPrefix:[shown stringByAppendingString:@"section"]] && [text rangeOfString:@"\u203E"].location == NSNotFound;
    NSData *unchanged = [support dataForText:text encoding:encoding byteOrderMark:TSNoByteOrderMark];
    NSData *saved = [support dataForText:[text stringByAppendingString:typed] encoding:encoding byteOrderMark:TSNoByteOrderMark];
    printf("%s%s%s\n", [[saved description] UTF8String], showsOne ? "" : "  [editor shows the wrong character]",
           [unchanged isEqualToData:data] ? "" : "  [unchanged file saved differently]");
    return showsOne && [unchanged isEqualToData:data] && [saved isEqualToData:expected] ? 0 : 1;
}}
'''.replace('TABLE', table).replace('CODE', code)
with tempfile.TemporaryDirectory(prefix='texshop-japanese-backslash-') as folder:
    p = Path(folder); (p/'test.m').write_text(program, encoding='latin1')
    subprocess.run(['xcrun', 'clang', '-fobjc-arc', '-framework', 'Foundation', str(p/'test.m'), '-o', str(p/'test')], check=True)
    failures = 0
    for n, (name, cf, yen_mode, data, typed, expected, shown) in enumerate(cases):
        files = [p/f'{n}-{k}' for k in ('in', 'typed', 'expected', 'shown')]
        files[0].write_bytes(data); files[1].write_text(typed, encoding='utf-8')
        files[2].write_bytes(expected); files[3].write_text(shown, encoding='utf-8')
        r = subprocess.run([str(p/'test'), str(files[0]), hex(cf), str(yen_mode)] + [str(f) for f in files[1:]], capture_output=True, text=True)
        ok = r.returncode == 0
        failures += not ok
        print(f"{'ok  ' if ok else 'FAIL'} {name:22} -> {r.stdout.strip() or r.stderr.strip()[:120]}  (expected {expected.hex()})")
    if failures:
        raise SystemExit(f'FAIL: {failures} of {len(cases)} Japanese files lose 0x5C or 0x7E')
    print(f'PASS: {len(cases)} Japanese files keep TeX backslashes and tildes as 0x5C and 0x7E in both modes')
