#!/usr/bin/env python3
"""Files without an encoding magic comment open in the encoding they were written in,
and saving them unchanged writes the same bytes.

The production detection and save code of TSEncodingSupport runs on sample TeX files in
many encodings, for users with different languages and default encodings. A file opens
correctly when its text equals the text read in its true encoding; cases marked exact must
also choose that very encoding. The user's languages are set for the test process only
(-AppleLanguages), so no preferences are written. --mutation=NAME removes one rule to show
that the checks fail. The rules for runs of accented letters, mixed scripts in a word,
Serbian in Latin letters, the first candidate without a guess and Windows encodings for C1
characters are checked on real documents instead; the files used are listed in the audit notes."""
from pathlib import Path
import os, subprocess, sys, tempfile
root = Path(__file__).resolve().parents[1]
mutation = next((a.split('=', 1)[1] for a in sys.argv[1:] if a.startswith('--mutation=')), None)
s = (root/'Sources/TSEncodingSupport.m').read_text(encoding='latin1')
table = s[s.index('typedef struct {'):s.index('// List of the supported encodings.', s.index('static TSEncoding _availableEncodings[]'))]
start = s.index('- (BOOL)isAvailableEncoding:(NSStringEncoding)encoding')
code = s[start:s.index('- (BOOL)ptexUtfOutputCheck:', start)]
mutations = {
    'foundation': ('NSStringEncoding guess = [NSString stringEncodingForData:data encodingOptions:options convertedString:&converted usedLossyConversion:&lossy];', 'NSStringEncoding guess = 0;'),
    'decodes': ('if (lossy || (guess && ! (available(guess) && TSDataDecodes(data, guess))))\n\t\tguess = 0;', ''),
    'japanese-score': ('if (guess && [TSEncodingFamily(@"ja") containsObject:@(guess)] && bestJapanese)', 'if (0)'),
    'japanese-override': ('&& japanese.score > 0 && 4 * japanese.unlikely <= japanese.japanese)', '&& 0)'),
    'chinese-for-japanese': ('&& ! [families containsObject:@"zh-Hans"] && ! [families containsObject:@"zh-Hant"]) {', '&& 0) {'),
    'clean-guess': ('if (guess && guessReading.suspicious == 0 && [oneByte containsObject:@(guess)])', 'if (0)'),
    'japanese-without-guess': ('else if (bestJapanese && ! guess && [families containsObject:@"ja"] && japanese.score > 0', 'else if (0'),
    'one-byte-score': ('if (! guess || TSIsSingleByteEncoding(guess)) {\n\t\tNSMutableOrderedSet *oneByte', 'if (0) {\n\t\tNSMutableOrderedSet *oneByte'),
    'gb18030': ('&& guess != gb18030 && available(gb18030) && TSDataRoundTrips(data, gb18030))', '&& 0)'),
    'preferred-variant': ('if (preferred != guess && [variants containsObject:@(preferred)] && TSDataRoundTrips(data, preferred))', 'if (0)'),
    'round-trip': ('if (! TSDataRoundTrips(data, guess))\n\t\t\tfor', 'if (0)\n\t\t\tfor'),
    'recorded': ('if (recorded && [self isAvailableEncoding:recorded]', 'if (0 && recorded'),
    'byte-order-mark': ('if (encoding == NSUTF8StringEncoding && mark == TSUTF8ByteOrderMark) {', 'if (0) {'),
}
if mutation:
    old, new = mutations[mutation]; assert old in code, mutation; code = code.replace(old, new)

CF = {'UTF8': 0x08000100, 'UTF16': 0x0100, 'DOSJapanese': 0x0420, 'EUC_JP': 0x0920, 'ISO_2022_JP': 0x0820,
      'ShiftJIS_X0213': 0x0628, 'MacJapanese': 0x0001, 'DOSKorean': 0x0422, 'GB_18030': 0x0632, 'EUC_CN': 0x0930,
      'DOSChineseTrad': 0x0423, 'WindowsLatin1': 0x0500, 'ISOLatin1': 0x0201, 'ISOLatin9': 0x020F, 'MacRoman': 0,
      'WindowsCyrillic': 0x0502, 'KOI8_R': 0x0A02, 'DOSRussian': 0x041B, 'MacCyrillic': 0x0007, 'DOSCyrillic': 0x0413,
      'WindowsLatin2': 0x0501, 'ISOLatin2': 0x0202, 'MacCentralEurRoman': 0x001D, 'ISOLatinGreek': 0x0207, 'ISOLatin5': 0x0209}

ja = '\\documentclass{jsarticle}\n\\begin{document}\n吾輩は猫である。名前はまだ無い。どこで生れたかとんと見当がつかぬ。\n\\section{はじめに}\nカタカナと漢字。\n\\end{document}\n'
ru = '\\documentclass{article}\n\\usepackage[russian]{babel}\n\\begin{document}\nМатематика изучает величины, количественные отношения и пространственные формы. Теорема Пифагора верна в евклидовой геометрии.\n\\end{document}\n'
doc = lambda body: '\\documentclass{article}\n\\begin{document}\n' + body + '\n\\end{document}\n'
gyudon = '完璧な牛丼'
samples = {
    'ja-sjis': (ja + '半角ｶﾀｶﾅ\n', 'cp932'), 'ja-euc': (ja, 'euc_jp'), 'ja-jis': (ja, 'iso2022_jp'),
    'ja-utf8': (ja, 'utf-8'), 'ja-utf8-bom': (ja, 'utf-8-sig'), 'ja-utf16le': (ja, 'utf-16-le-bom'), 'ja-utf16be': (ja, 'utf-16-be-bom'),
    'short-sjis': ('\\section{序}\nあ\n', 'cp932'), 'short-euc': ('\\section{序}\nあ\n', 'euc_jp'),
    'ascii': (doc('Hello'), 'ascii'),
    'fr-latin1': (doc('La théorie des catégories étudie les structures. Été, élève, où, garçon.'), 'latin-1'),
    'fr-macroman': (doc('La théorie des catégories étudie les structures mathématiques. Été, élève, où, garçon, cœur.'), 'mac_roman'),
    'en-cp1252': (doc('“Quoted” text – a dash, an apostrophe’s use, and 5 € …'), 'cp1252'),
    'zh-gb18030': ('\\documentclass{ctexart}\n\\begin{document}\n数学是研究数量、结构、变化以及空间等概念的一门学科。\n\\end{document}\n', 'gb18030'),
    'zh-gb2312': ('\\documentclass{ctexart}\n\\begin{document}\n数学是研究数量、结构、变化以及空间等概念的一门学科。\n\\end{document}\n', 'gb2312'),
    'tw-big5': (doc('數學是研究數量、結構、變化以及空間等概念的一門學科。'), 'big5'),
    'ko-cp949': (doc('수학은 수, 양, 구조, 공간, 변화 등의 개념을 다루는 학문이다.'), 'cp949'),
    'ru-koi8': (ru, 'koi8_r'), 'ru-cp1251': (ru, 'cp1251'), 'ru-cp866': (ru, 'cp866'), 'ru-maccyr': (ru, 'mac_cyrillic'), 'ru-cp855': (ru, 'cp855'),
    'cs-maclatin2': (doc('Matematika je věda zabývající se strukturami, změnou a prostorem. Příliš žluťoučký kůň úpěl ďábelské ódy.'), 'mac_latin2'),
    'pl-latin2': (doc('Matematyka jest nauką o strukturach i zależnościach. Zażółć gęślą jaźń, śnieg pada.'), 'iso8859_2'),
    'el-greek': (doc('Τα μαθηματικά μελετούν ποσότητες, δομές, χώρο και μεταβολή. Θεώρημα του Πυθαγόρα.'), 'iso8859_7'),
    'tr-latin5': (doc('Matematik; sayı, yapı, uzay ve değişim gibi konuları inceler. Ağaç, çiçek, ışık, şeker, öğrenci.'), 'iso8859_9'),
    'sr-latin-cp1250': (doc('Matematika je nauka o strukturama, promenama i prostoru. Čačak, ćuprija, đak, šuma, žaba.'), 'cp1250'),
    'sr-ligatures-cp1250': ('%% lig.tex\n%% Copyright 2011 Zoran Filipovi\u0107\n%% The maintainer of this work is Zoran Filipovi\u0107\n\\documentclass{article}\n\\begin{document}\n\\verb|po\u010deo je da vadi fleke|\n\\end{document}\n', 'cp1250'),
    'gyudon': (gyudon + '\n', 'euc_jp'), 'gyudon-tex': (doc(gyudon), 'euc_jp'), 'gyudon-sjis': (gyudon + '\n', 'cp932'),
    'kyo': ('京\n', 'euc_jp'), 'gyudon-short': ('牛丼\n', 'euc_jp'), 'shoyu': ('醤油をかける\n', 'euc_jp'), 'shoyu-kanji': ('醤油\n', 'euc_jp'),
    'tex-section-sign': ('\\catcode`\\\u00a713\n\\long\\def\u00a7#1\u00a7{\\def\\Comment{#1}}\n\u00a7Note\u00a7 Caf\u00e9.\n', 'cp1252'),
    'accent-utf8': (doc('Café au lait, naïve résumé.'), 'utf-8'),
    # Mac Japanese has circled digits at 85 40; read as Windows Shift JIS they would be written back as 87 40.
    'mac-japanese-digits': (b'\\section{\x82\xa0}\n\x85\x40 \x85\x41\n', None),
}
# (sample, languages, default encoding, true encoding, exact, xattr)
cases = [
    ('ja-sjis', 'ja', 'UTF8', 'DOSJapanese', 0, None), ('ja-euc', 'ja', 'UTF8', 'EUC_JP', 0, None),
    ('ja-jis', 'ja', 'UTF8', 'ISO_2022_JP', 0, None), ('ja-utf8', 'ja', 'UTF8', 'UTF8', 0, None),
    ('ja-utf8-bom', 'ja', 'DOSJapanese', 'UTF8', 0, None), ('ja-utf16le', 'en', 'UTF8', 'UTF16', 0, None),
    ('ja-utf16be', 'ja', 'UTF8', 'UTF16', 0, None),
    ('short-sjis', 'ja', 'UTF8', 'DOSJapanese', 0, None), ('short-euc', 'ja', 'UTF8', 'EUC_JP', 0, None),
    ('ascii', 'ja', 'DOSJapanese', 'DOSJapanese', 1, None), ('ja-euc', 'ja', 'DOSJapanese', 'EUC_JP', 0, None),
    ('ja-utf8', 'ja', 'DOSJapanese', 'UTF8', 0, None), ('ja-sjis', 'en', 'UTF8', 'DOSJapanese', 0, None),
    # The default encoding is kept when a variant of it reads the file, so typed characters fit it.
    ('ja-sjis', 'ja', 'MacJapanese', 'MacJapanese', 1, None),
    ('mac-japanese-digits', 'ja', 'UTF8', 'MacJapanese', 1, None),
    ('zh-gb2312', 'zh-Hans', 'EUC_CN', 'EUC_CN', 1, None), ('zh-gb2312', 'en', 'UTF8', 'GB_18030', 0, None),
    ('fr-latin1', 'en', 'UTF8', 'ISOLatin1', 0, None), ('fr-latin1', 'fr', 'ISOLatin9', 'ISOLatin1', 0, None),
    ('fr-latin1', 'ja', 'UTF8', 'ISOLatin1', 0, None), ('fr-macroman', 'fr', 'UTF8', 'MacRoman', 0, None),
    # C1 bytes of Windows Latin 1 are not kept as control characters of the Latin 9 default.
    ('en-cp1252', 'en', 'ISOLatin9', 'WindowsLatin1', 0, None),
    ('zh-gb18030', 'en', 'UTF8', 'GB_18030', 0, None), ('zh-gb18030', 'zh-Hans', 'UTF8', 'GB_18030', 0, None),
    ('tw-big5', 'zh-Hant', 'UTF8', 'DOSChineseTrad', 0, None), ('ko-cp949', 'ko', 'UTF8', 'DOSKorean', 0, None),
    ('ru-koi8', 'ru', 'UTF8', 'KOI8_R', 0, None), ('ru-cp1251', 'ru', 'UTF8', 'WindowsCyrillic', 0, None),
    ('ru-cp866', 'ru', 'UTF8', 'DOSRussian', 0, None), ('ru-maccyr', 'ru', 'UTF8', 'MacCyrillic', 0, None),
    ('ru-cp855', 'ru', 'UTF8', 'DOSCyrillic', 0, None),
    ('cs-maclatin2', 'cs', 'UTF8', 'MacCentralEurRoman', 0, None), ('pl-latin2', 'pl', 'UTF8', 'ISOLatin2', 0, None),
    ('el-greek', 'el', 'UTF8', 'ISOLatinGreek', 0, None), ('tr-latin5', 'tr', 'UTF8', 'ISOLatin5', 0, None),
    ('sr-latin-cp1250', 'sr', 'UTF8', 'WindowsLatin2', 0, None), ('sr-ligatures-cp1250', 'sr', 'UTF8', 'WindowsLatin2', 0, None),
    ('ja-sjis', 'en', 'UTF8', 'DOSJapanese', 0, 'SHIFT_JIS;1056'),
    # A recorded encoding wins over the guess when it reads the file.
    ('ja-euc', 'ja', 'UTF8', 'ShiftJIS_X0213', 1, 'Shift_JIS-2004;1576'),
    # A recorded encoding that does not read the file is ignored.
    ('ja-sjis', 'ja', 'UTF8', 'DOSJapanese', 0, 'utf-8;134217984'),
    # The EUC-JP bytes of this phrase are also valid Shift JIS, as half-width katakana.
    ('gyudon', 'ja', 'UTF8', 'EUC_JP', 0, None), ('gyudon', 'en', 'UTF8', 'EUC_JP', 0, None),
    ('gyudon-tex', 'en', 'UTF8', 'EUC_JP', 0, None), ('gyudon-sjis', 'ja', 'UTF8', 'DOSJapanese', 0, None),
    ('gyudon-sjis', 'en', 'UTF8', 'DOSJapanese', 0, None),
    # Very short files: Foundation's guess may not read the file, be the wrong Japanese
    # encoding, or be Chinese.
    ('kyo', 'ja', 'UTF8', 'EUC_JP', 0, None), ('gyudon-short', 'ja', 'UTF8', 'EUC_JP', 0, None),
    ('shoyu', 'ja', 'UTF8', 'EUC_JP', 0, None), ('shoyu-kanji', 'ja', 'UTF8', 'EUC_JP', 0, None),
    # Foundation guesses UTF-8, which does not read it; the first Western candidate does.
    ('tex-section-sign', 'en', 'UTF8', 'WindowsLatin1', 0, None),
    # A few accented letters in UTF-8 also read as half-width katakana in Shift JIS.
    ('accent-utf8', 'ja', 'DOSJapanese', 'UTF8', 0, None),
]
program = r'''
#import <Foundation/Foundation.h>
#include <sys/xattr.h>
#define ARRAYSIZE(x) ((NSInteger)(sizeof(x)/sizeof(x[0])))
typedef NS_ENUM(NSInteger, TSByteOrderMark) { TSNoByteOrderMark = 0, TSUTF8ByteOrderMark, TSUTF16BigEndianByteOrderMark, TSUTF16LittleEndianByteOrderMark };
@interface TSEncodingSupport : NSObject
- (NSStringEncoding)detectedEncodingForData:(NSData *)data fileURL:(NSURL *)url preferredEncoding:(NSStringEncoding)preferred;
- (NSData *)dataForText:(NSString *)text encoding:(NSStringEncoding)encoding byteOrderMark:(TSByteOrderMark)mark;
+ (TSByteOrderMark)byteOrderMarkOfData:(NSData *)data;
@end
@implementation TSEncodingSupport
TABLE
+ (void)initialize {
    for (NSInteger i = 0; i < ARRAYSIZE(_availableEncodings); ++i)
        _availableEncodings[i].nsEnc = CFStringConvertEncodingToNSStringEncoding(_availableEncodings[i].cfEnc);
}
CODE
@end
static NSStringEncoding NS(const char *cf) { return CFStringConvertEncodingToNSStringEncoding((CFStringEncoding)strtoul(cf, 0, 0)); }
int main(int argc, char **argv) { @autoreleasepool {
    // argv: file preferredCF trueCF exact
    NSURL *url = [NSURL fileURLWithPath:@(argv[1])];
    NSData *data = [NSData dataWithContentsOfURL:url];
    NSStringEncoding expected = NS(argv[3]);
    TSEncodingSupport *support = [TSEncodingSupport new];
    NSStringEncoding got = [support detectedEncodingForData:data fileURL:url preferredEncoding:NS(argv[2])];
    NSString *text = [[NSString alloc] initWithData:data encoding:got];
    NSString *truth = [[NSString alloc] initWithData:data encoding:expected];
    // Saving unchanged: the same text in the same encoding, with the same byte order mark.
    NSData *saved = text ? [support dataForText:text encoding:got byteOrderMark:[TSEncodingSupport byteOrderMarkOfData:data]] : nil;
    BOOL opens = atoi(argv[4]) ? got == expected : (text && [text isEqualToString:truth]);
    BOOL keeps = [saved isEqualToData:data];
    printf("%s%s%s\n", [(__bridge NSString *)CFStringGetNameOfEncoding(CFStringConvertNSStringEncodingToEncoding(got)) UTF8String],
           opens ? "" : "  [wrong text]", keeps ? "" : "  [saved bytes differ]");
    return opens && keeps ? 0 : 1;
}}
'''.replace('TABLE', table).replace('CODE', code)
with tempfile.TemporaryDirectory(prefix='texshop-encoding-detection-') as folder:
    p = Path(folder); (p/'test.m').write_text(program, encoding='latin1')
    subprocess.run(['xcrun', 'clang', '-fobjc-arc', '-framework', 'Foundation', str(p/'test.m'), '-o', str(p/'test')], check=True)
    failures = 0
    for n, (name, languages, preferred, truth, exact, recorded) in enumerate(cases):
        text, codec = samples[name]
        if codec is None: data = text
        elif codec == 'utf-16-le-bom': data = b'\xff\xfe' + text.encode('utf-16-le')
        elif codec == 'utf-16-be-bom': data = b'\xfe\xff' + text.encode('utf-16-be')
        else: data = text.encode(codec)
        f = p/f'{n:02d}-{name}.tex'; f.write_bytes(data)
        if recorded:
            subprocess.run(['xattr', '-w', 'com.apple.TextEncoding', recorded, str(f)], check=True)
        r = subprocess.run([str(p/'test'), str(f), hex(CF[preferred]), hex(CF[truth]), str(exact), '-AppleLanguages', f'({languages})'],
                           capture_output=True, text=True)
        ok = r.returncode == 0
        failures += not ok
        print(f"{'ok  ' if ok else 'FAIL'} {name:20} languages={languages:8} default={preferred:12} xattr={recorded or '-':22} -> {r.stdout.strip() or r.stderr.strip()[:80]}  (true {truth}{', exact' if exact else ''})")
    if failures:
        raise SystemExit(f'FAIL: {failures} of {len(cases)} files opened or saved wrongly')
    print(f'PASS: {len(cases)} files without a magic comment open in their encoding and save back unchanged')
