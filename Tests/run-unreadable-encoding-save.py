#!/usr/bin/env python3
"""A file that could not be read in the encoding of its magic comment is saved as it was read.

TeXShop reads such a file in Latin 9 and says so. The production serializedSourceOfType:
reads the magic comment again when saving; it must not then write the Latin 9 text in the
encoding that could not read the file, which would garble every non-ASCII byte. Once the file
is read in its encoding, the magic comment decides again, and a magic comment naming another
encoding is followed, also when it is later changed back. --mutation=unreadable removes the check;
--mutation=kept-record keeps the record of the failed reading after another encoding is named."""
from pathlib import Path
import subprocess, sys, tempfile
root = Path(__file__).resolve().parents[1]
mutation = next((a.split('=', 1)[1] for a in sys.argv[1:] if a.startswith('--mutation=')), None)
s = (root/'Sources/TSDocument.m').read_text(encoding='latin1')
def method(signature):
    a = s.index(signature); return s[a:s.index('\n}\n', a)+3]
methods = method('- (NSString *)encodingNameInMagicComment') + method('- (NSData *)serializedSourceOfType:(NSString *)typeName error:(NSError **)outError {') + method('- (void)takeMagicCommentEncoding:')
if mutation == 'unreadable':
    old = '\tif (_unreadableEncoding && encoding == _unreadableEncoding)\n\t\treturn;\n'
    assert old in methods; methods = methods.replace(old, '')
if mutation == 'kept-record':
    old = '\t_unreadableEncoding = 0;\n'
    assert old in methods; methods = methods.replace(old, '')
program = r'''
#import <Cocoa/Cocoa.h>
#define GetCurrentKeyModifiers() 0
#define optionKey 0x0800
#define UseOldHeadingCommandsKey @"UseOldHeadingCommands"
#define AutomaticUTF8MACtoUTF8ConversionKey @"AutomaticUTF8MACtoUTF8Conversion"
#define ptexUtfOutputEnabledKey @"ptexUtfOutputEnabled"
#define NSISOLatin9StringEncoding CFStringConvertEncodingToNSStringEncoding(kCFStringEncodingISOLatin9)
@implementation NSString (TSNormalization)
- (NSString *)normalizedStringWithModifiedNFC { return self; }
@end
typedef NS_ENUM(NSInteger, TSByteOrderMark) { TSNoByteOrderMark = 0 };
// In-memory stand-in for the user defaults: nothing is written to disk.
@interface FakeDefaults : NSObject
- (BOOL)boolForKey:(NSString *)key;
@end
@implementation FakeDefaults
- (BOOL)boolForKey:(NSString *)key { return NO; }
@end
static FakeDefaults *gDefaults;
#define SUD gDefaults
@interface TSEncodingSupport : NSObject
+ (instancetype)sharedInstance;
- (NSStringEncoding)stringEncodingForKey:(NSString *)key;
- (BOOL)ptexUtfOutputCheck:(NSString *)s withEncoding:(NSStringEncoding)e;
- (NSData *)ptexUtfOutput:(NSTextView *)v withEncoding:(NSStringEncoding)e;
- (NSData *)dataForText:(NSString *)text encoding:(NSStringEncoding)encoding byteOrderMark:(TSByteOrderMark)mark;
@end
@implementation TSEncodingSupport
+ (instancetype)sharedInstance { static id shared; if (!shared) shared = [self new]; return shared; }
- (NSStringEncoding)stringEncodingForKey:(NSString *)key {
    if ([key isEqualToString:@"UTF-8 Unicode"]) return NSUTF8StringEncoding;
    if ([key isEqualToString:@"IsoLatin"]) return NSISOLatin1StringEncoding;
    return NSISOLatin9StringEncoding;
}
- (BOOL)ptexUtfOutputCheck:(NSString *)s withEncoding:(NSStringEncoding)e { return NO; }
- (NSData *)ptexUtfOutput:(NSTextView *)v withEncoding:(NSStringEncoding)e { return nil; }
- (NSData *)dataForText:(NSString *)text encoding:(NSStringEncoding)encoding byteOrderMark:(TSByteOrderMark)mark {
    return [text dataUsingEncoding:encoding allowLossyConversion:YES];
}
@end
@interface TSDocument : NSObject {
@public
    NSTextStorage *_textStorage; NSTextView *textView;
    NSStringEncoding _encoding, _tempencoding, _sourceMarkEncoding, _unreadableEncoding;
    NSInteger _sourceByteOrderMark;
}
@end
@implementation TSDocument
METHODS
@end
static void check(BOOL v, const char *m) { if (!v) { fprintf(stderr, "FAIL %s\n", m); exit(1); } }
int main(void) { @autoreleasepool {
    gDefaults = [FakeDefaults new];
    // Latin 1 bytes under a UTF-8 magic comment: UTF-8 cannot read them, so TeXShop read Latin 9.
    NSData *file = [@"% !TEX encoding = UTF-8 Unicode\nCaf\u00e9 cr\u00e8me\n" dataUsingEncoding:NSISOLatin1StringEncoding];
    check([[NSString alloc] initWithData:file encoding:NSUTF8StringEncoding] == nil, "the sample is not UTF-8");
    TSDocument *doc = [TSDocument new];
    doc->_textStorage = [[NSTextStorage alloc] initWithString:[[NSString alloc] initWithData:file encoding:NSISOLatin9StringEncoding]];
    doc->_unreadableEncoding = NSUTF8StringEncoding;
    doc->_encoding = doc->_tempencoding = NSISOLatin9StringEncoding;
    NSData *saved = [doc serializedSourceOfType:@"tex" error:NULL];
    check([saved isEqualToData:file], "a file read in Latin 9 after its magic comment failed is saved unchanged");
    check(doc->_encoding == NSISOLatin9StringEncoding, "the document stays in Latin 9");
    // A magic comment changed to another encoding is followed.
    [doc->_textStorage replaceCharactersInRange:NSMakeRange(0, doc->_textStorage.length) withString:@"% !TEX encoding = IsoLatin\nCaf\u00e9\n"];
    saved = [doc serializedSourceOfType:@"tex" error:NULL];
    check(doc->_encoding == NSISOLatin1StringEncoding, "a magic comment naming another encoding is followed");
    // Changed back to UTF-8 by the user, the magic comment is followed again.
    [doc->_textStorage replaceCharactersInRange:NSMakeRange(0, doc->_textStorage.length) withString:@"% !TEX encoding = UTF-8 Unicode\nCaf\u00e9\n"];
    saved = [doc serializedSourceOfType:@"tex" error:NULL];
    check(doc->_encoding == NSUTF8StringEncoding && [saved isEqualToData:[doc->_textStorage.string dataUsingEncoding:NSUTF8StringEncoding]], "a magic comment changed back to the unreadable encoding is followed");
    // A file that was read in its encoding is saved in the encoding of its magic comment.
    TSDocument *readable = [TSDocument new];
    readable->_textStorage = [[NSTextStorage alloc] initWithString:@"% !TEX encoding = UTF-8 Unicode\nCaf\u00e9\n"];
    readable->_encoding = readable->_tempencoding = NSISOLatin9StringEncoding;
    saved = [readable serializedSourceOfType:@"tex" error:NULL];
    check(readable->_encoding == NSUTF8StringEncoding && [saved isEqualToData:[readable->_textStorage.string dataUsingEncoding:NSUTF8StringEncoding]], "the magic comment decides for a readable file");
    fprintf(stderr, "PASS: a file read in Latin 9 after its magic comment failed is saved unchanged\n");
}}
'''.replace('METHODS', methods)
with tempfile.TemporaryDirectory(prefix='texshop-unreadable-save-') as folder:
    p = Path(folder); (p/'test.m').write_text(program, encoding='latin1')
    subprocess.run(['xcrun', 'clang', '-fobjc-arc', '-Wno-deprecated-declarations', '-framework', 'Cocoa', str(p/'test.m'), '-o', str(p/'test')], check=True)
    subprocess.run([str(p/'test')], check=True, timeout=30)
