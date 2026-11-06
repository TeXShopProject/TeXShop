#!/usr/bin/env python3
"""TeX output reaches the console whole, however the pipe divides it.

The production -writeTexOutput:, -showConsoleOutputData: and -doTexCommand: of TSDocument
run with the output helpers of TSEncodingSupport, on a real pipe and on pieces of output of
every width from 1 to 7 bytes. They check that the console keeps waiting for output when a
whole piece is kept for the next one, that a kept piece is shown when nothing more comes,
that a UTF-8 line in a Shift JIS or EUC-JP document reads the same however it is divided,
that line breaks TeX puts inside a character are mended for LF, CRLF and CR, and that a
backslash and a tilde typed in the console reach TeX as 0x5C and 0x7E in every Japanese
encoding. Nothing is shown on screen. --mutation=NAME undoes one of these (rearm, hold,
flush, cr, input, order) and the test must then fail."""
from pathlib import Path
import subprocess, sys, tempfile
root = Path(__file__).resolve().parents[1]
mutation = next((a.split('=', 1)[1] for a in sys.argv[1:] if a.startswith('--mutation=')), None)

def cut(text, start, end):
    a = text.index(start); return text[a:text.index(end, a)]

enc = (root/'Sources/TSEncodingSupport.m').read_text(encoding='latin1')
helpers = cut(enc, '// UTF-8 in which each byte that does not start or continue a valid character is replaced',
              '// The byte order mark that starts data')
japanese = cut(enc, '// Japanese encodings read the byte 0x5C', '- (BOOL)ptexUtfOutputCheck:')
doc = (root/'Sources/TSDocument.m').read_text(encoding='latin1')
output = cut(doc, '// Show a piece of TeX output in the console and look in it for errors.', '// Code by Nicolas Ojeda Bar')
jobs = (root/'Sources/TSDocument-Jobs.m').read_text(encoding='latin1')
command = jobs[jobs.index('- (void) doTexCommand: sender'):]
command = command[:command.index('\n}\n') + 3]

def mutate(text, old, new):
    assert old in text, old; return text.replace(old, new)
if mutation == 'rearm':
    output = mutate(output, '        if ([myData length])\n            [self showConsoleOutputData: myData];\n'
                    '        // Wait for more output even when all of this piece was kept for the next one.\n        if (! atEnd)\n',
                    '        if ([myData length])\n            [self showConsoleOutputData: myData];\n        if (! atEnd && [myData length])\n')
elif mutation == 'hold':
    helpers = mutate(helpers, 'if (encoding != NSUTF8StringEncoding && length - lineStart <= TSLongestKeptLine)',
                     'if (NO && length - lineStart <= TSLongestKeptLine)')
elif mutation == 'flush':
    output = mutate(output, '[self showConsoleOutputData: kept];', '')
elif mutation == 'cr':
    helpers = mutate(helpers, "if (b[i] == '\\r') {", "if (NO) {")
elif mutation == 'input':
    command = mutate(command, '[[TSEncodingSupport sharedInstance] dataForText: command\n\t\t\tencoding: (_encoding == NSUnicodeStringEncoding ? NSUTF8StringEncoding : _encoding) byteOrderMark: TSNoByteOrderMark]',
                     '[command dataUsingEncoding: (_encoding == NSUnicodeStringEncoding ? NSUTF8StringEncoding : _encoding) allowLossyConversion:YES]')
elif mutation == 'order':
    helpers = mutate(helpers, '\tif ((text = [[NSString alloc] initWithBytes:bytes length:length encoding:NSUTF8StringEncoding]))\n\t\treturn text;\n',
                     '\tif ((text = [[NSString alloc] initWithBytes:bytes length:length encoding:encoding]))\n\t\treturn text;\n')
elif mutation:
    raise SystemExit('unknown mutation ' + mutation)

program = r'''
#import <Cocoa/Cocoa.h>
#define NUMBEROFERRORS 20
typedef enum { kNoFilterMode = 0, kMacJapaneseFilterMode = 1, kOtherJapaneseFilterMode = 2 } TSFilterMode;
static TSFilterMode g_shouldFilter = kNoFilterMode;
typedef enum { TSNoByteOrderMark = 0, TSUTF8ByteOrderMark, TSUTF16BigEndianByteOrderMark, TSUTF16LittleEndianByteOrderMark } TSByteOrderMark;
@interface FakeDefaults : NSObject
- (BOOL)boolForKey:(NSString *)key;
@end
@implementation FakeDefaults
- (BOOL)boolForKey:(NSString *)key { return NO; }
@end
#define SUD ((FakeDefaults *)[FakeDefaults new])
#define RedConsoleAfterErrorKey @"RedConsoleAfterError"
@interface TSEncodingSupport : NSObject
+ (instancetype)sharedInstance;
+ (NSString *)displayStringForData:(NSData *)data encoding:(NSStringEncoding)encoding;
+ (NSUInteger)lengthOfIncompleteCharacterAtEndOfData:(NSData *)data encoding:(NSStringEncoding)encoding;
- (NSData *)dataForText:(NSString *)text encoding:(NSStringEncoding)encoding byteOrderMark:(TSByteOrderMark)mark;
@end
@implementation TSEncodingSupport
+ (instancetype)sharedInstance { static TSEncodingSupport *s; if (! s) s = [self new]; return s; }
HELPERS
JAPANESE
@end
@interface FakeHandle : NSObject
@property NSData *nextData;
@property NSUInteger arms;
@property NSMutableData *written;
@end
@implementation FakeHandle
- (void)waitForDataInBackgroundAndNotify { self.arms++; }
- (void)writeData:(NSData *)data { if (! self.written) self.written = [NSMutableData data]; [self.written appendData:data]; }
@end
@interface FakeText : NSObject
@property NSMutableString *text;
@property NSString *stringValue;
@end
@implementation FakeText
- (instancetype)init { if ((self = [super init])) _text = [NSMutableString new]; return self; }
- (NSRange)selectedRange { return NSMakeRange(_text.length, 0); }
- (void)replaceCharactersInRange:(NSRange)range withString:(NSString *)s { [_text appendString:s]; }
- (void)scrollRangeToVisible:(NSRange)r {}
- (void)setTextColor:(NSColor *)c range:(NSRange)r {}
@end
@interface Probe : NSObject {
@public
    dispatch_queue_t process_queue;
    NSData *_consoleCarry;
    id _consoleCarryHandle;
    NSUInteger _consoleCarryGeneration;
    NSStringEncoding _encoding;
    BOOL makeError, typesetStart, consoleCleanStart;
    NSInteger errorNumber, errorLine[NUMBEROFERRORS];
    NSString *errorText[NUMBEROFERRORS], *errorLinePath[NUMBEROFERRORS];
    NSWindow *outputWindow;
    NSTextView *outputText;
    NSTextField *texCommand;
    NSForm *statisticsForm;
}
@property id readHandle, texloganalyserHandle, detexHandle, inputPipe;
@property FakeHandle *writeHandle;
@property NSTextView *logTextView;
@property NSString *statTempFile;
@property BOOL automaticCorrection;
@property NSInteger numberingCorrection;
@end
@implementation Probe
- (NSData *)availableDataOrError:(id)h { return [h isKindOfClass:[FakeHandle class]] ? [(FakeHandle *)h nextData] : [(NSFileHandle *)h availableData]; }
- (NSString *)filterBackslashes:(NSString *)s { return s; }
OUTPUT
COMMAND
@end
static int failures = 0;
static void check(BOOL ok, NSString *what) { printf("%s %s\n", ok ? "ok  " : "FAIL", what.UTF8String); failures += ! ok; }
static NSData *B(const char *b) { return [NSData dataWithBytes:b length:strlen(b)]; }
static NSStringEncoding CF(CFStringEncoding e) { return CFStringConvertEncodingToNSStringEncoding(e); }
static Probe *P(NSStringEncoding e) {
    Probe *p = [Probe new]; p->_encoding = e; p->process_queue = dispatch_queue_create("console", DISPATCH_QUEUE_SERIAL);
    p->outputText = (id)[FakeText new]; p->consoleCleanStart = YES; return p;
}
static NSString *shown(Probe *p) { return [(FakeText *)(id)p->outputText text]; }
static void run(double seconds) {
    NSDate *until = [NSDate dateWithTimeIntervalSinceNow:seconds];
    while (until.timeIntervalSinceNow > 0) [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.005]];
}
static void drain(Probe *p) {
    __block BOOL done = NO;
    dispatch_async(p->process_queue, ^{ dispatch_async(dispatch_get_main_queue(), ^{ done = YES; }); });
    while (! done) [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.001]];
}
static void feed(Probe *p, FakeHandle *h, NSData *d) {
    h.nextData = d; p.readHandle = h;
    [p writeTexOutput:[NSNotification notificationWithName:@"output" object:h]];
    drain(p);
}
// The console text for output given in pieces of width bytes, then the end of the output.
static NSString *pieces(NSStringEncoding e, NSData *whole, NSUInteger width) {
    Probe *p = P(e); FakeHandle *h = [FakeHandle new];
    for (NSUInteger i = 0; i < whole.length; i += width)
        feed(p, h, [whole subdataWithRange:NSMakeRange(i, MIN(width, whole.length - i))]);
    feed(p, h, [NSData data]);
    return shown(p);
}
// A real pipe: bytes written in steps, with pauses, read through the notifications TeXShop uses.
static Probe *throughPipe(NSStringEncoding e, NSArray<NSData *> *steps, double pause, BOOL close) {
    Probe *p = P(e); NSPipe *pipe = [NSPipe pipe]; p.readHandle = pipe.fileHandleForReading;
    [[NSNotificationCenter defaultCenter] addObserver:p selector:@selector(writeTexOutput:) name:NSFileHandleDataAvailableNotification object:p.readHandle];
    [p.readHandle waitForDataInBackgroundAndNotify];
    for (NSData *d in steps) { [pipe.fileHandleForWriting writeData:d]; run(pause); }
    if (close) { [pipe.fileHandleForWriting closeFile]; run(pause); }
    drain(p);
    [[NSNotificationCenter defaultCenter] removeObserver:p];
    return p;
}
int main(int argc, char **argv) { @autoreleasepool {
    NSStringEncoding utf8 = NSUTF8StringEncoding, sjis = CF(kCFStringEncodingDOSJapanese), euc = NSJapaneseEUCStringEncoding;
    // The console keeps waiting for output when all of a piece is kept for the next one.
    Probe *p = throughPipe(utf8, @[B("\xE3"), B("\x81\x82\n")], 0.1, YES);
    check([shown(p) isEqualToString:@"\u3042\n"] && p->_consoleCarry.length == 0, @"real pipe: E3, then 81 82 LF and the end, shows the character once");
    p = throughPipe(utf8, @[B("ok \xE3"), B("\x81"), B("\x82 done\n")], 0.1, YES);
    check([shown(p) isEqualToString:@"ok \u3042 done\n"], @"real pipe: a character in three pieces after ASCII");
    p = P(utf8); FakeHandle *h = [FakeHandle new]; feed(p, h, B("\xE3"));
    check(h.arms == 1 && p->_consoleCarry.length == 1, @"a piece kept whole still waits for more output");
    // What is kept is shown when nothing more comes, as when TeX waits for input.
    NSData *prompt = [@"\u65e5\u672c\u8a9e\u306e\u5165\u529b: " dataUsingEncoding:utf8];
    p = throughPipe(sjis, @[prompt], 0.6, NO);
    check([shown(p) isEqualToString:@"\u65e5\u672c\u8a9e\u306e\u5165\u529b: "] && p->_consoleCarry.length == 0, @"a Japanese line without a line break is shown after a pause");
    p = throughPipe(utf8, @[B("? ")], 0.1, NO);
    check([shown(p) isEqualToString:@"? "], @"TeX's prompt is shown at once");
    // A line reads the same however the output is divided.
    NSString *mixed = @"\u65e5\u672c\u8a9e\n\u3042\u3044\u3046\nl.3 \u5b8c\u74a7\u306a\u725b\u4e3c\n? ";
    struct { NSStringEncoding doc; NSData *data; const char *name; } outputs[] = {
        {sjis, [mixed dataUsingEncoding:utf8], "UTF-8 output, Shift JIS document"},
        {euc, [mixed dataUsingEncoding:utf8], "UTF-8 output, EUC-JP document"},
        {sjis, [mixed dataUsingEncoding:sjis], "Shift JIS output, Shift JIS document"},
        {euc, [mixed dataUsingEncoding:euc], "EUC-JP output, EUC-JP document"},
        {utf8, [mixed dataUsingEncoding:utf8], "UTF-8 output, UTF-8 document"},
        {NSUnicodeStringEncoding, [mixed dataUsingEncoding:utf8], "UTF-8 output, UTF-16 document"},
    };
    for (size_t i = 0; i < sizeof(outputs) / sizeof(outputs[0]); i++) {
        NSString *once = pieces(outputs[i].doc, outputs[i].data, outputs[i].data.length);
        BOOL same = YES;
        for (NSUInteger w = 1; w <= 7; w++) same = same && [pieces(outputs[i].doc, outputs[i].data, w) isEqualToString:once];
        check(same && [once isEqualToString:mixed], [NSString stringWithFormat:@"%s: right, and the same in pieces of 1 to 7 bytes", outputs[i].name]);
    }
    // A Shift JIS line that also reads as UTF-8 keeps reading as Shift JIS in a Shift JIS document.
    NSData *both = [@"\u9b31" dataUsingEncoding:sjis];
    check([[TSEncodingSupport displayStringForData:both encoding:sjis] isEqualToString:@"\u9b31"], @"output all in the document's encoding is shown as before");
    // Line breaks TeX puts inside a character, for each kind of line break.
    NSArray *breaks = @[@"\n", @"\r\n", @"\r"], *breakNames = @[@"LF", @"CRLF", @"CR"];
    for (NSUInteger n = 0; n < breaks.count; n++) {
        NSString *br = breaks[n];
        NSMutableData *d = [B("x\xE6") mutableCopy]; [d appendData:[br dataUsingEncoding:utf8]]; [d appendData:B("\x97\xA5y")];
        NSString *expected = [NSString stringWithFormat:@"x%@\u65e5y", br];
        BOOL ok = [[TSEncodingSupport displayStringForData:d encoding:utf8] isEqualToString:expected];
        for (NSUInteger w = 1; w <= 7; w++) ok = ok && [pieces(utf8, d, w) isEqualToString:expected];
        check(ok, [NSString stringWithFormat:@"a character broken by %@ is mended, in any pieces", breakNames[n]]);
    }
    NSMutableData *crLines = [[@"\u65e5\u672c\r" dataUsingEncoding:utf8] mutableCopy];
    [crLines appendData:B("caf\xE9\r")]; [crLines appendData:[@"\u65e5\u672c" dataUsingEncoding:utf8]];
    check([[TSEncodingSupport displayStringForData:crLines encoding:utf8] isEqualToString:@"\u65e5\u672c\rcaf\u00e9\r\u65e5\u672c"], @"lines ended by CR are read one by one");
    // A backslash and a tilde typed in the console reach TeX as 0x5C and 0x7E.
    struct { NSStringEncoding doc; const char *name; } docs[] = {
        {CF(kCFStringEncodingMacJapanese), "Mac Japanese"}, {CF(kCFStringEncodingShiftJIS_X0213_00), "Shift JIS X0213"},
        {sjis, "Windows Shift JIS"}, {euc, "EUC-JP"}, {CF(kCFStringEncodingISO_2022_JP), "ISO-2022-JP"},
        {utf8, "UTF-8"}, {NSUnicodeStringEncoding, "UTF-16"},
    };
    for (size_t i = 0; i < sizeof(docs) / sizeof(docs[0]); i++)
        for (int filter = 0; filter <= 1; filter++)
            for (int yen = 0; yen <= (docs[i].doc == utf8 || docs[i].doc == NSUnicodeStringEncoding ? 0 : 1); yen++) {
                g_shouldFilter = filter ? kMacJapaneseFilterMode : kNoFilterMode;
                Probe *c = P(docs[i].doc); FakeHandle *w = [FakeHandle new]; FakeText *field = [FakeText new];
                field.stringValue = yen ? @"\u00a5relax~" : @"\\relax~";
                c->typesetStart = YES; c.inputPipe = w; c.writeHandle = w; c->texCommand = (id)field;
                [c doTexCommand:nil];
                BOOL ok = [w.written isEqualToData:B("\\relax~\n")];
                if (! ok || (filter == 0 && yen == 0))
                    check(ok, [NSString stringWithFormat:@"console input in %s (%s, typed %s) is 5C ... 7E", docs[i].name,
                               filter ? "yen mode" : "backslash mode", yen ? "yen" : "backslash"]);
            }
    return failures ? 1 : 0;
}}
'''
program = program.replace('HELPERS', helpers).replace('JAPANESE', japanese).replace('OUTPUT', output).replace('COMMAND', command)
with tempfile.TemporaryDirectory(prefix='texshop-console-output-') as folder:
    p = Path(folder); (p/'test.m').write_text(program, encoding='latin1')
    subprocess.run(['xcrun', 'clang', '-fobjc-arc', '-w', '-framework', 'Cocoa', str(p/'test.m'), '-o', str(p/'test')], check=True)
    r = subprocess.run([str(p/'test')], timeout=120)
    if r.returncode:
        raise SystemExit('FAIL: TeX output or console input is divided or converted wrongly')
    print('PASS: TeX output reaches the console whole however it is divided, and console input keeps 0x5C and 0x7E')
