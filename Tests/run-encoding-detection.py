#!/usr/bin/env python3
"""Files without an encoding magic comment open in the encoding they were written in.

The production detection code of TSEncodingSupport runs on sample TeX files in
many encodings, for users with different languages and default encodings. The
user's languages are set for the test process only (-AppleLanguages), so no
preferences are written. --mutation=NAME removes one step to show that the checks fail."""
from pathlib import Path
import os, subprocess, sys, tempfile
root = Path(__file__).resolve().parents[1]
mutation = next((a.split('=', 1)[1] for a in sys.argv[1:] if a.startswith('--mutation=')), None)
s = (root/'Sources/TSEncodingSupport.m').read_text(encoding='latin1')
table = s[s.index('typedef struct {'):s.index('// List of the supported encodings.', s.index('static TSEncoding _availableEncodings[]'))]
start = s.index('- (BOOL)isAvailableEncoding:(NSStringEncoding)encoding')
code = s[start:s.index('- (BOOL)ptexUtfOutputCheck:', start)]
mutations = {
    'foundation': ('if (guess && ! lossy && [self isAvailableEncoding:guess]) {', 'if (0) {'),
    'japanese-score': ('if (guess && [TSEncodingFamily(@"ja") containsObject:@(guess)] && bestJapanese)', 'if (0)'),
    'japanese-override': ('&& japanese.score > 0 && 4 * japanese.unlikely <= japanese.japanese) {', '&& 0) {'),
    'decodes': ('if (guess && ! TSDataDecodes(data, guess))\n\t\tguess = 0;', ''),
    'gb18030': ('&& [self isAvailableEncoding:gb18030] && TSDataDecodes(data, gb18030))', '&& 0)'),
    'single-byte': ('TSIsSingleByteEncoding(guess) && TSIsSingleByteEncoding(preferred)', '0'),
    'recorded': ('if (recorded && [self isAvailableEncoding:recorded]', 'if (0 && recorded'),
}
if mutation:
    old, new = mutations[mutation]; assert old in code, mutation; code = code.replace(old, new)

def cf(name):
    return {'UTF8': 0x08000100, 'DOSJapanese': 0x0420, 'EUC_JP': 0x0920, 'ISO_2022_JP': 0x0820,
            'ShiftJIS_X0213': 0x0628, 'DOSKorean': 0x0422, 'GB_18030': 0x0632, 'DOSChineseTrad': 0x0423,
            'WindowsLatin1': 0x0500, 'ISOLatin9': 0x020F, 'ISOLatin1': 0x0201, 'WindowsCyrillic': 0x0502, 'MacRoman': 0}[name]

ja = '\\documentclass{jsarticle}\n\\begin{document}\n吾輩は猫である。名前はまだ無い。どこで生れたかとんと見当がつかぬ。\n\\section{はじめに}\nカタカナと漢字。\n\\end{document}\n'
samples = {
    'ja-sjis': (ja + '半角ｶﾀｶﾅ\n', 'cp932'), 'ja-euc': (ja, 'euc_jp'), 'ja-jis': (ja, 'iso2022_jp'),
    'ja-utf8': (ja, 'utf-8'), 'ja-utf8-bom': (ja, 'utf-8-sig'), 'short-sjis': ('\\section{序}\nあ\n', 'cp932'),
    'short-euc': ('\\section{序}\nあ\n', 'euc_jp'), 'ascii': ('\\documentclass{article}\n\\begin{document}\nHello\n\\end{document}\n', 'ascii'),
    'fr-latin1': ('\\documentclass{article}\n\\begin{document}\nLa théorie des catégories étudie les structures. Été, élève, où, garçon.\n\\end{document}\n', 'latin-1'),
    'zh-gb18030': ('\\documentclass{ctexart}\n\\begin{document}\n数学是研究数量、结构、变化以及空间等概念的一门学科。\n\\end{document}\n', 'gb18030'),
    'tw-big5': ('\\documentclass{article}\n\\begin{document}\n數學是研究數量、結構、變化以及空間等概念的一門學科。\n\\end{document}\n', 'big5'),
    'accent-utf8': ('\\documentclass{article}\n\\begin{document}\nCaf\u00e9 au lait, na\u00efve r\u00e9sum\u00e9.\n\\end{document}\n', 'utf-8'),
    'gyudon': ('\u5b8c\u74a7\u306a\u725b\u4e3c\n', 'euc_jp'),
    'gyudon-tex': ('\\documentclass{jsarticle}\n\\begin{document}\n\u5b8c\u74a7\u306a\u725b\u4e3c\n\\end{document}\n', 'euc_jp'),
    'gyudon-sjis': ('\u5b8c\u74a7\u306a\u725b\u4e3c\n', 'cp932'),
    'kyo': ('\u4eac\n', 'euc_jp'), 'gyudon-short': ('\u725b\u4e3c\n', 'euc_jp'), 'shoyu': ('\u91a4\u6cb9\u3092\u304b\u3051\u308b\n', 'euc_jp'),
    'ko-cp949': ('\\documentclass{article}\n\\begin{document}\n수학은 수, 양, 구조, 공간, 변화 등의 개념을 다루는 학문이다.\n\\end{document}\n', 'cp949'),
}
# (sample, user's languages, default encoding, expected, xattr or None)
cases = [
    ('ja-sjis', 'ja', 'UTF8', 'DOSJapanese', None), ('ja-euc', 'ja', 'UTF8', 'EUC_JP', None),
    ('ja-jis', 'ja', 'UTF8', 'ISO_2022_JP', None), ('ja-utf8', 'ja', 'UTF8', 'UTF8', None),
    ('ja-utf8-bom', 'ja', 'DOSJapanese', 'UTF8', None), ('short-sjis', 'ja', 'UTF8', 'DOSJapanese', None),
    ('short-euc', 'ja', 'UTF8', 'EUC_JP', None), ('ascii', 'ja', 'DOSJapanese', 'DOSJapanese', None),
    ('ja-euc', 'ja', 'DOSJapanese', 'EUC_JP', None), ('ja-utf8', 'ja', 'DOSJapanese', 'UTF8', None),
    ('ja-sjis', 'en', 'UTF8', 'DOSJapanese', None), ('fr-latin1', 'en', 'UTF8', 'WESTERN', None),
    ('fr-latin1', 'fr', 'ISOLatin9', 'ISOLatin9', None), ('fr-latin1', 'ja', 'UTF8', 'WESTERN', None),
    ('zh-gb18030', 'en', 'UTF8', 'GB_18030', None), ('zh-gb18030', 'zh-Hans', 'UTF8', 'GB_18030', None),
    ('tw-big5', 'zh-Hant', 'UTF8', 'DOSChineseTrad', None), ('ko-cp949', 'ko', 'UTF8', 'DOSKorean', None),
    # The EUC-JP bytes of this phrase are also valid Shift JIS, as half-width katakana.
    ('gyudon', 'ja', 'UTF8', 'EUC_JP', None), ('gyudon', 'en', 'UTF8', 'EUC_JP', None),
    ('gyudon-tex', 'en', 'UTF8', 'EUC_JP', None), ('gyudon-sjis', 'ja', 'UTF8', 'DOSJapanese', None),
    ('gyudon-sjis', 'en', 'UTF8', 'DOSJapanese', None),
    # Very short files: Foundation's guess may not read the file, or may be the wrong
    # Japanese encoding or Chinese.
    ('kyo', 'ja', 'UTF8', 'EUC_JP', None), ('gyudon-short', 'ja', 'UTF8', 'EUC_JP', None),
    ('shoyu', 'ja', 'UTF8', 'EUC_JP', None),
    # A few accented letters in UTF-8 also read as half-width katakana in Shift JIS.
    ('accent-utf8', 'ja', 'DOSJapanese', 'UTF8', None),
    ('ja-sjis', 'en', 'UTF8', 'DOSJapanese', 'SHIFT_JIS;1056'),
    # A recorded encoding wins over Foundation's guess when it reads the file.
    ('ja-euc', 'ja', 'UTF8', 'ShiftJIS_X0213', 'Shift_JIS-2004;1576'),
    # A recorded encoding that does not read the file is ignored.
    ('ja-sjis', 'ja', 'UTF8', 'DOSJapanese', 'utf-8;134217984'),
]
program = r'''
#import <Foundation/Foundation.h>
#include <sys/xattr.h>
#define ARRAYSIZE(x) ((NSInteger)(sizeof(x)/sizeof(x[0])))
@interface TSEncodingSupport : NSObject
- (NSStringEncoding)detectedEncodingForData:(NSData *)data fileURL:(NSURL *)url preferredEncoding:(NSStringEncoding)preferred;
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
    // argv: file preferredCF expectedCF[,expectedCF...]
    NSURL *url = [NSURL fileURLWithPath:@(argv[1])];
    NSStringEncoding preferred = CFStringConvertEncodingToNSStringEncoding((CFStringEncoding)strtoul(argv[2], 0, 0));
    NSStringEncoding got = [[TSEncodingSupport new] detectedEncodingForData:[NSData dataWithContentsOfURL:url] fileURL:url preferredEncoding:preferred];
    printf("%s\n", [(__bridge NSString *)CFStringGetNameOfEncoding(CFStringConvertNSStringEncodingToEncoding(got)) UTF8String]);
    for (NSString *e in [@(argv[3]) componentsSeparatedByString:@","])
        if (got == CFStringConvertEncodingToNSStringEncoding((CFStringEncoding)strtoul(e.UTF8String, 0, 0))) return 0;
    return 1;
}}
'''.replace('TABLE', table).replace('CODE', code)
with tempfile.TemporaryDirectory(prefix='texshop-encoding-detection-') as folder:
    p = Path(folder); (p/'test.m').write_text(program, encoding='latin1')
    subprocess.run(['xcrun', 'clang', '-fobjc-arc', '-framework', 'Foundation', str(p/'test.m'), '-o', str(p/'test')], check=True)
    failures = 0
    for name, languages, preferred, expected, recorded in cases:
        text, codec = samples[name]
        f = p/f'{name}-{len(os.listdir(p))}.tex'; f.write_bytes(text.encode(codec))
        if recorded:
            subprocess.run(['xattr', '-w', 'com.apple.TextEncoding', recorded, str(f)], check=True)
        r = subprocess.run([str(p/'test'), str(f), hex(cf(preferred)), ','.join(hex(cf(e)) for e in (['WindowsLatin1', 'ISOLatin1', 'ISOLatin9'] if expected == 'WESTERN' else [expected])), '-AppleLanguages', f'({languages})'],
                           capture_output=True, text=True)
        ok = r.returncode == 0
        failures += not ok
        print(f"{'ok  ' if ok else 'FAIL'} {name:12} languages={languages:8} default={preferred:12} xattr={recorded or '-':22} -> {r.stdout.strip()}  (expected {expected})")
    if failures:
        raise SystemExit(f'FAIL: {failures} of {len(cases)} files opened in the wrong encoding')
    print(f'PASS: {len(cases)} files without a magic comment open in the encoding they were written in')
