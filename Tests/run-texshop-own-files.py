#!/usr/bin/env python3
"""TeXShop's own text files are plain text, read and saved as TeXShop reads them, and edited in TeXShop.

The spell checking rules (~/Library/TeXShop/SpellCheck/SpellingExclusions.txt) are read only as
UTF-8; the command completion file as UTF-8, or else in the encoding of new files. Neither is TeX
source. The production TSOwnTextFileForURL, readFromURL:ofType:error:, serializedSourceOfType:error:,
writeSafelyToURL:ofType:forSaveOperation:error:, opensForPreview and doNotReadSource of TSDocument
run here in an NSDocument; the encoding detection, the magic comment scan, \\UTF decoding and the
character conversions for TeX are stand-ins that record their use.
- The rules are read in UTF-8 even with an encoding magic comment and another encoding for new
  files, keep \\UTF{...} as written, and are saved as the exact UTF-8 of their text, with their byte
  order mark, whatever magic comment they then have; through a symbolic link or in other letter case
  they are the same file. Rules that are not UTF-8 are read in Latin 9, even with an encoding magic
  comment, and saved in UTF-8.
- The command completion file is read as the completion reader reads it: UTF-8, or else the
  encoding of new files, and saved in it.
- Where a document is saved decides: an ordinary document saved as the rules file is written in
  UTF-8, and the rules saved as an ordinary file follow its magic comment; an autosave elsewhere is
  written as the document's own file.
- With an external editor, TeXShop's own files are opened as sources, other files for preview only.
- An ordinary file with the same bytes still follows its magic comment.
- The encoding chosen when saving or for the document does not change how an own file is written;
  a copy written elsewhere, or a failed save, leaves the document as it was; a command completion
  file whose new text does not fit its old encoding is written in UTF-8; a duplicate is read as
  the same kind of file; while a command completion file is open, nothing is registered in it.
--mutation=own-read, own-save, own-convert, own-unreadable-magic, save-target, autosave-elsewhere,
completion-encoding, own-preview, chosen-encoding, duplicate-plain, completion-registration,
record-kind, move-kind, panel-encoding, save-to-list, preview-counts check that each of these is tested."""
from pathlib import Path
import subprocess, sys, tempfile
root = Path(__file__).resolve().parents[1]
mutation = next((a.split('=', 1)[1] for a in sys.argv[1:] if a.startswith('--mutation=')), None)
s = (root/'Sources/Document/TSDocument.m').read_text(encoding='utf-8')
def cut(start, end):
    a = s.index(start); return s[a:s.index(end, a)]
def method(signature):
    a = s.index(signature); return s[a:s.index('\n}\n', a)+3]
helpers = cut('typedef NS_ENUM(NSInteger, TSOwnTextFileKind)', '@implementation TSDocument\n')
methods = (cut('- (BOOL)readFromURL: (NSURL *)absoluteURL', '- (BOOL)writeToURL:')
    + method('- (NSString *)encodingNameInMagicComment')
    + method('- (NSData *)serializedSourceOfType:(NSString *)typeName error:(NSError **)outError {')
    + method('- (void)takeMagicCommentEncoding:')
    + method('- (BOOL)writeSafelyToURL:(NSURL *)url ofType:(NSString *)typeName')
    + method('- (BOOL)opensForPreview')
    + method('-(BOOL)doNotReadSource;')
    + method('- (NSDocument *)duplicateAndReturnError:(NSError **)outError')
    + method('- (NSStringEncoding)ownTextEncodingForKind:(NSInteger)kind')
    + method('- (void)takeOwnTextFileKindOfURL:(NSURL *)url')
    + method('- (void)setFileURL:(NSURL *)url')
    + method('- (void)setUpEncodingMenuInSavePanel: (NSPopUpButton *)menu')
    + method('- (BOOL)isCommandCompletionFile'))
def mutate(text, old, new):
    assert text.count(old) == 1, old; return text.replace(old, new)
if mutation == 'own-read':
    methods = mutate(methods, '\t_ownTextFile = TSOwnTextFileForURL([self fileURL] ?: absoluteURL);\n', '\t_ownTextFile = TSOwnTextFileNone;\n')
if mutation == 'own-save':
    methods = mutate(methods, '\tif (target != TSOwnTextFileNone) {\n\t\tNSString *text', '\tif (NO) {\n\t\tNSString *text')
if mutation == 'own-convert':
    methods = mutate(methods, '\t\tif (_ownTextFile == TSOwnTextFileNone) {\n\t\t\tcontent = [content stringByDecodingUTFCommandsForReading];', '\t\tif (YES) {\n\t\t\tcontent = [content stringByDecodingUTFCommandsForReading];')
if mutation == 'save-target':
    methods = mutate(methods, '\tTSOwnTextFileKind target = _savingOwnTextFile ? _savingOwnTextFile - 1 : _ownTextFile;\n', '\tTSOwnTextFileKind target = _ownTextFile;\n')
if mutation == 'autosave-elsewhere':
    methods = mutate(methods, 'BOOL copy = _duplicating || operation == NSAutosaveElsewhereOperation;', 'BOOL copy = _duplicating;')
if mutation == 'completion-encoding':
    methods = mutate(methods, '(utf8 || _ownTextFile == TSOwnTextFileSpellingRules) ?', '(YES) ?')
if mutation == 'chosen-encoding':
    methods = mutate(methods, '{\n\treturn NSUTF8StringEncoding;\n}', '{\n\treturn _encoding;\n}')
if mutation == 'save-to-list':
    methods = mutate(methods, '        if (result && ! copy && TSOwnTextFileForURL(url) == TSOwnTextFileCommandCompletion)\n', '        if (NO)\n')
if mutation == 'preview-counts':
    methods = mutate(methods, '    return _ownTextFile == TSOwnTextFileCommandCompletion && ! _externalEditor;', '    return _ownTextFile == TSOwnTextFileCommandCompletion;')
if mutation == 'record-kind':
    methods = mutate(methods, '            TSRecordOwnTextFileKind(url, target);\n', '            ;\n')
if mutation == 'move-kind':
    methods = mutate(methods, '    if (_hasReadSource)\n        [self takeOwnTextFileKindOfURL:url];\n', '')
if mutation == 'panel-encoding':
    methods = mutate(methods, '\tif (_ownTextFile != TSOwnTextFileNone) {\n\t\t_tempencoding = [self ownTextEncodingForKind: _ownTextFile];', '\tif (NO) {\n\t\t_tempencoding = [self ownTextEncodingForKind: _ownTextFile];')
if mutation == 'duplicate-plain':
    methods = mutate(methods, '\tif (_ownTextFile == TSOwnTextFileNone && [self fileURL] == nil)\n\t\t_ownTextFile = TSRecordedOwnTextFileKind(absoluteURL);\n', '')
if mutation == 'completion-registration':
    methods = mutate(methods, '\tif (_ownTextFile == TSOwnTextFileCommandCompletion)\n\t\tg_canRegisterCommandCompletion = NO;\n', '')
if mutation == 'own-preview':
    methods = mutate(methods, ' &&\n\t\tTSOwnTextFileForURL([self fileURL]) == TSOwnTextFileNone;', ';')
program = r'''
#import <Cocoa/Cocoa.h>
#import "TestAppKitIsolation.h"
#import <sys/stat.h>
#import <sys/xattr.h>
#define GetCurrentKeyModifiers() 0
#define optionKey 0x0800
#define NSISOLatin9StringEncoding CFStringConvertEncodingToNSStringEncoding(kCFStringEncodingISOLatin9)
static NSString *ConvertLFKey = @"ConvertLF", *UseOldHeadingCommandsKey = @"UseOldHeadingCommands",
    *AutomaticUTF8MACtoUTF8ConversionKey = @"AutomaticUTF8MACtoUTF8Conversion", *ptexUtfOutputEnabledKey = @"ptexUtfOutputEnabled";
NSString *CommandCompletionPathRegular, *CommandCompletionPathXML;
BOOL g_canRegisterCommandCompletion = YES;
enum { OgreLfNewlineCharacter = 0 };
typedef NS_ENUM(NSInteger, TSByteOrderMark) { TSNoByteOrderMark = 0, TSUTF8ByteOrderMark = 1 };
static NSUInteger gConversions;
// In-memory stand-in for the user defaults: nothing is written to disk.
@interface FakeDefaults : NSObject
@end
@implementation FakeDefaults
- (BOOL)boolForKey:(NSString *)key { return NO; }
@end
static FakeDefaults *gDefaults;
#define SUD gDefaults
@implementation NSString (TSStandIns)
- (NSString *)normalizedStringWithModifiedNFC { return self; }
// As TeXShop does, \UTF{20AC} becomes the euro sign.
- (NSString *)stringByDecodingUTFCommandsForReading { gConversions++; return [self stringByReplacingOccurrencesOfString:@"\\UTF{20AC}" withString:@"\u20AC"]; }
@end
@interface OGRegularExpression : NSObject
@end
@implementation OGRegularExpression
+ (NSString *)replaceNewlineCharactersInString:(NSString *)s withCharacter:(int)c { return s; }
@end
static NSString *gRulesPath;
@interface TSSpellExclusions : NSObject
@end
@implementation TSSpellExclusions
+ (NSString *)userRulesPath { return gRulesPath; }
@end
@interface TSEncodingSupport : NSObject
@end
@implementation TSEncodingSupport
+ (instancetype)sharedInstance { static id shared; if (!shared) shared = [self new]; return shared; }
+ (TSByteOrderMark)byteOrderMarkOfData:(NSData *)data {
    return (data.length >= 3 && memcmp(data.bytes, "\xEF\xBB\xBF", 3) == 0) ? TSUTF8ByteOrderMark : TSNoByteOrderMark;
}
// New files are Latin 1 here.
- (NSStringEncoding)defaultEncoding { return NSISOLatin1StringEncoding; }
- (BOOL)knowsEncodingKey:(NSString *)key { return YES; }
- (NSStringEncoding)stringEncodingForKey:(NSString *)key {
    if ([key isEqualToString:@"IsoLatin"]) return NSISOLatin1StringEncoding;
    if ([key isEqualToString:@"MacOSRoman"]) return NSMacOSRomanStringEncoding;
    return NSUTF8StringEncoding;
}
- (NSString *)textForEditing:(NSString *)text encoding:(NSStringEncoding)encoding { gConversions++; return text; }
- (BOOL)ptexUtfOutputCheck:(NSString *)s withEncoding:(NSStringEncoding)e { return NO; }
- (NSData *)ptexUtfOutput:(NSTextView *)v withEncoding:(NSStringEncoding)e { return nil; }
- (NSData *)dataForText:(NSString *)text encoding:(NSStringEncoding)encoding byteOrderMark:(TSByteOrderMark)mark {
    gConversions++; return [text dataUsingEncoding:encoding allowLossyConversion:YES];
}
@end
// No encoding is chosen in the Open dialog in these tests.
@interface TSDocumentController : NSObject
@end
@implementation TSDocumentController
+ (instancetype)sharedDocumentController { static id shared; if (!shared) shared = [self new]; return shared; }
- (BOOL)takeEncoding:(NSStringEncoding *)encoding chosenForURL:(NSURL *)url { return NO; }
@end
@interface TSAppDelegate : NSObject
@property BOOL forPreview;
@property NSUInteger completionReads;
@end
@implementation TSAppDelegate
- (void)reReadCommandCompletionData { self.completionReads++; g_canRegisterCommandCompletion = YES; }
@end
static NSData *TSSourceFingerprint(NSData *data) { return data; }
@interface TSDocument : NSDocument {
@public
    NSTextStorage *_textStorage; NSTextView *textView;
    NSStringEncoding _encoding, _tempencoding, _badEncoding, _sourceMarkEncoding, _unreadableEncoding;
    NSInteger _sourceByteOrderMark, _lineEndingNotice, _ownTextFile, _savingOwnTextFile;
    NSStringEncoding _savingOwnTextEncoding;
    BOOL _externalEditor, _encodingFromMagicComment, _hasReadSource, showBadEncodingDialog, isLoading, firstTime, sourceSaving, _duplicating;
    NSData *sourceReloadData, *sourceReloadFingerprint, *sourceAcceptedFingerprint, *sourceWrittenFingerprint;
    NSUInteger sourceIOGeneration;
}
@end
HELPERS
@implementation TSDocument
+ (BOOL)autosavesInPlace { return NO; }
+ (NSArray *)writableTypes { return @[@"public.plain-text"]; }
- (void)watchFile:(NSString *)path {}
- (void)refreshPreviewTitle {}
- (void)cancelWatchFile {}
- (void)readPreviewArrangementFromData:(NSData *)data {}
- (NSInteger)lineEndingNoticeForText:(NSString *)text URL:(NSURL *)url { return 0; }
- (NSStringEncoding)encodingForUnmarkedData:(NSData *)data URL:(NSURL *)url { return NSISOLatin1StringEncoding; }
// The magic comment scan: an IsoLatin or MacOSRoman magic comment in the first lines names it.
- (NSStringEncoding)dataEncoding:(NSData *)data {
    NSString *head = [[NSString alloc] initWithData:data encoding:NSISOLatin1StringEncoding];
    _encodingFromMagicComment = YES;
    if ([head containsString:@"% !TEX encoding = IsoLatin"]) return NSISOLatin1StringEncoding;
    if ([head containsString:@"% !TEX encoding = MacOSRoman"]) return NSMacOSRomanStringEncoding;
    _encodingFromMagicComment = NO;
    return _encoding;
}
- (NSData *)dataOfType:(NSString *)type error:(NSError **)error { return [self serializedSourceOfType:type error:error]; }
- (instancetype)init { if ((self = [super init])) { _textStorage = [NSTextStorage new]; _encoding = NSISOLatin1StringEncoding; } return self; }
METHODS
@end
@interface Controller : NSDocumentController
@end
@implementation Controller
- (NSString *)typeForContentsOfURL:(NSURL *)url error:(NSError **)error { return @"public.plain-text"; }
- (Class)documentClassForType:(NSString *)type { return [TSDocument class]; }
- (NSString *)defaultType { return @"public.plain-text"; }
@end
static void check(BOOL v, NSString *m) { if (!v) { fprintf(stderr, "FAIL %s\n", m.UTF8String); exit(1); } }
static TSDocument *Open(NSURL *url) {
    TSDocument *d = [TSDocument new]; d->_textStorage = [NSTextStorage new]; d->_encoding = NSISOLatin1StringEncoding;
    d.fileURL = url; d.fileType = @"public.plain-text"; NSError *e = nil;
    check([d readFromURL:url ofType:@"public.plain-text" error:&e], [NSString stringWithFormat:@"%@ is read", url.lastPathComponent]);
    return d;
}
static BOOL Write(TSDocument *d, NSURL *url, NSSaveOperationType op) {
    NSError *e = nil; BOOL ok = [d writeSafelyToURL:url ofType:@"public.plain-text" forSaveOperation:op error:&e];
    if (ok && (op == NSSaveAsOperation)) d.fileURL = url;
    return ok;
}
static NSData *Bytes(NSString *path) { return [NSData dataWithContentsOfFile:path]; }
static NSData *UTF8(NSString *s) { return [s dataUsingEncoding:NSUTF8StringEncoding]; }
int main(int argc, char **argv) { @autoreleasepool {
    TSInstallAppKitIsolation(); [NSApplication sharedApplication];
    gDefaults = [FakeDefaults new];
    TSAppDelegate *delegate = [TSAppDelegate new]; NSApp.delegate = (id)delegate;
    [Controller new];
    NSString *folder = @(argv[1]);
    NSString *spell = [folder stringByAppendingPathComponent:@"SpellCheck"], *complete = [folder stringByAppendingPathComponent:@"CommandCompletion"];
    for (NSString *f in @[spell, complete]) [[NSFileManager defaultManager] createDirectoryAtPath:f withIntermediateDirectories:YES attributes:nil error:NULL];
    gRulesPath = [spell stringByAppendingPathComponent:@"SpellingExclusions.txt"];
    CommandCompletionPathRegular = [complete stringByAppendingPathComponent:@"CommandCompletion.txt"];
    CommandCompletionPathXML = [complete stringByAppendingPathComponent:@"CommandCompletionXML.txt"];
    NSURL *rulesURL = [NSURL fileURLWithPath:gRulesPath], *completionURL = [NSURL fileURLWithPath:CommandCompletionPathRegular];
    NSString *rules = @"# % !TEX encoding = IsoLatin\n# caf\u00e9 \u8a2d\u5b9a\ndelimited \\UTF{20AC} END\nskip-args 1 mycommand\n";
    [UTF8(rules) writeToFile:gRulesPath atomically:YES];

    // The rules: read in UTF-8 whatever the magic comment and the encoding of new files, with nothing converted.
    gConversions = 0;
    TSDocument *d = Open(rulesURL);
    check(d->_ownTextFile == TSOwnTextFileSpellingRules, @"the rules file is recognised");
    check(d->_encoding == NSUTF8StringEncoding && !d->_encodingFromMagicComment, @"the rules file is read in UTF-8 despite the magic comment");
    check([d->_textStorage.string isEqualToString:rules], @"the rules text is read exactly, \\UTF{20AC} included");
    check(gConversions == 0, @"nothing in the rules file is converted for TeX when it is read");
    [d->_textStorage.mutableString appendString:@"% !TEX encoding = IsoLatin\n# \u00e9t\u00e9 \u8a2d\u5b9a\n"];
    check(Write(d, rulesURL, NSSaveOperation) && [Bytes(gRulesPath) isEqualToData:UTF8(d->_textStorage.string)] && d->_encoding == NSUTF8StringEncoding,
          @"the rules file is saved as the UTF-8 of its text");
    check(gConversions == 0, @"nothing in the rules file is converted for TeX when it is saved");
    TSDocument *again = Open(rulesURL);
    check(again->_ownTextFile == TSOwnTextFileSpellingRules && [again->_textStorage.string isEqualToString:d->_textStorage.string], @"the rules file reads back the same");
    NSString *link = [folder stringByAppendingPathComponent:@"rules-link.txt"];
    [[NSFileManager defaultManager] createSymbolicLinkAtPath:link withDestinationPath:gRulesPath error:NULL];
    check(Open([NSURL fileURLWithPath:link])->_ownTextFile == TSOwnTextFileSpellingRules, @"the rules file through a symbolic link is recognised");
    check(Open([NSURL fileURLWithPath:[spell stringByAppendingPathComponent:@"spellingexclusions.TXT"]])->_ownTextFile == TSOwnTextFileSpellingRules,
          @"the rules file in other letter case is recognised");
    // An autosave elsewhere is written as the document's own file.
    NSString *elsewhere = [folder stringByAppendingPathComponent:@"autosave.txt"];
    check(Write(again, [NSURL fileURLWithPath:elsewhere], NSAutosaveElsewhereOperation) && [Bytes(elsewhere) isEqualToData:UTF8(again->_textStorage.string)],
          @"an autosave elsewhere of the rules is written as the rules file");

    // A byte order mark is kept.
    NSMutableData *marked = [NSMutableData dataWithBytes:"\xEF\xBB\xBF" length:3]; [marked appendData:UTF8(rules)];
    [marked writeToFile:gRulesPath atomically:YES];
    check(Write(Open(rulesURL), rulesURL, NSSaveOperation) && [Bytes(gRulesPath) isEqualToData:marked], @"a rules file with a byte order mark is saved with it, unchanged");

    // Rules that are not UTF-8 are read in Latin 9, also with an encoding magic comment, and saved in UTF-8.
    NSMutableData *latin = [[@"% !TEX encoding = MacOSRoman\n# \u20AC caf\u00e9\n" dataUsingEncoding:NSISOLatin9StringEncoding] mutableCopy];
    [latin writeToFile:gRulesPath atomically:YES];
    TSDocument *broken = Open(rulesURL);
    check(broken->_encoding == NSISOLatin9StringEncoding, @"a rules file that is not UTF-8 is read in Latin 9");
    [broken->_textStorage.mutableString appendString:@"skip-body proof\n"]; [latin appendData:UTF8(@"skip-body proof\n")];
    check(Write(broken, rulesURL, NSSaveOperation) && [Bytes(gRulesPath) isEqualToData:UTF8(broken->_textStorage.string)],
          @"a rules file that is not UTF-8 is saved in UTF-8, which TeXShop reads, with the text as it was read");

    // The command completion file: UTF-8 when it is UTF-8, else the encoding of new files, as the completion reader reads it.
    NSString *entries = @"\\section\nfirst caf\u00e9\n\\UTF{20AC}\n";
    [UTF8(entries) writeToFile:CommandCompletionPathRegular atomically:YES];
    gConversions = 0;
    TSDocument *c = Open(completionURL);
    check(c->_ownTextFile == TSOwnTextFileCommandCompletion && c->_encoding == NSUTF8StringEncoding && [c->_textStorage.string isEqualToString:entries] && gConversions == 0,
          @"a UTF-8 command completion file is read in UTF-8 as written");
    [c->_textStorage.mutableString appendString:@"second \u00e9t\u00e9\n"];
    check(Write(c, completionURL, NSSaveOperation) && [Bytes(CommandCompletionPathRegular) isEqualToData:UTF8(c->_textStorage.string)],
          @"a UTF-8 command completion file is saved in UTF-8");
    NSData *legacy = [@"\\section\nold caf\u00e9\n" dataUsingEncoding:NSISOLatin1StringEncoding];
    NSString *xml = CommandCompletionPathXML; [legacy writeToFile:xml atomically:YES];
    TSDocument *old = Open([NSURL fileURLWithPath:xml]);
    check(old->_ownTextFile == TSOwnTextFileCommandCompletion && old->_encoding == NSISOLatin1StringEncoding && [old->_textStorage.string hasSuffix:@"old caf\u00e9\n"],
          @"a command completion file that is not UTF-8 is read in the encoding of new files");
    check(Write(old, [NSURL fileURLWithPath:xml], NSSaveOperation) && [Bytes(xml) isEqualToData:UTF8(old->_textStorage.string)],
          @"a command completion file is saved in UTF-8, which TeXShop reads first, so it reads back as it was edited");

    // Where a document is saved decides. An ordinary Latin 1 document saved as the rules file is written in UTF-8.
    NSString *paper = [folder stringByAppendingPathComponent:@"paper.tex"];
    [[@"caf\u00e9\n" dataUsingEncoding:NSISOLatin1StringEncoding] writeToFile:paper atomically:YES];
    TSDocument *p = Open([NSURL fileURLWithPath:paper]);
    check(p->_ownTextFile == TSOwnTextFileNone && p->_encoding == NSISOLatin1StringEncoding, @"an ordinary file is read in the encoding of new files");
    check(Write(p, rulesURL, NSSaveAsOperation) && [Bytes(gRulesPath) isEqualToData:UTF8(p->_textStorage.string)], @"a document saved as the rules file is written in UTF-8");
    [p->_textStorage.mutableString appendString:@"skip-body proof\n"];
    check(Write(p, rulesURL, NSSaveOperation) && [Bytes(gRulesPath) isEqualToData:UTF8(p->_textStorage.string)], @"and it stays UTF-8 when saved again");
    // The rules saved as an ordinary file follow its magic comment.
    [UTF8(@"% !TEX encoding = IsoLatin\ncaf\u00e9\n") writeToFile:gRulesPath atomically:YES];
    TSDocument *r = Open(rulesURL);
    NSString *copy = [folder stringByAppendingPathComponent:@"copy.tex"];
    check(Write(r, [NSURL fileURLWithPath:copy], NSSaveAsOperation) && [Bytes(copy) isEqualToData:UTF8(r->_textStorage.string)],
          @"the rules saved elsewhere are written as the save panel shows, in UTF-8");
    check(r->_ownTextFile == TSOwnTextFileNone, @"saved elsewhere, the document is an ordinary file");

    // With an external editor, TeXShop's own files are opened as sources, other files for preview only.
    delegate.forPreview = YES;
    check(![Open(rulesURL) opensForPreview] && ![Open(rulesURL) doNotReadSource] && ![Open(completionURL) doNotReadSource],
          @"with an external editor TeXShop's own files are edited in TeXShop");
    TSDocument *preview = [TSDocument new]; preview.fileURL = [NSURL fileURLWithPath:paper];
    check([preview opensForPreview] && [preview doNotReadSource], @"with an external editor other sources are for preview only");
    delegate.forPreview = NO;

    // The encoding chosen when saving or for the document does not change how the rules are written.
    NSMutableData *bomRules = [NSMutableData dataWithBytes:"\xEF\xBB\xBF" length:3]; [bomRules appendData:UTF8(@"% !TEX encoding = IsoLatin\ncaf\u00e9\n")];
    [bomRules writeToFile:gRulesPath atomically:YES];
    TSDocument *chosen = Open(rulesURL);
    chosen->_encoding = chosen->_tempencoding = NSISOLatin1StringEncoding;
    [chosen->_textStorage.mutableString appendString:@"skip-body proof\n"];
    NSMutableData *expected = [NSMutableData dataWithBytes:"\xEF\xBB\xBF" length:3]; [expected appendData:UTF8(chosen->_textStorage.string)];
    check(Write(chosen, rulesURL, NSSaveOperation) && [Bytes(gRulesPath) isEqualToData:expected], @"the rules are written in UTF-8 whatever encoding was chosen");
    // A copy written as an ordinary file, or a failed save, leaves the document as it was.
    NSString *exported = [folder stringByAppendingPathComponent:@"exported.tex"];
    check(Write(chosen, [NSURL fileURLWithPath:exported], NSSaveToOperation), @"a copy of the rules is written as an ordinary file");
    NSString *locked = [folder stringByAppendingPathComponent:@"locked"]; [[NSFileManager defaultManager] createDirectoryAtPath:locked withIntermediateDirectories:YES attributes:nil error:NULL];
    chmod(locked.fileSystemRepresentation, 0555);
    check(chosen->_encoding == NSUTF8StringEncoding && chosen->_tempencoding == NSUTF8StringEncoding, @"writing a copy as an ordinary file leaves the document's encoding");
    check(!Write(chosen, [NSURL fileURLWithPath:[locked stringByAppendingPathComponent:@"x.tex"]], NSSaveAsOperation), @"saving where it cannot be written fails");
    chmod(locked.fileSystemRepresentation, 0755);
    check(chosen->_encoding == NSUTF8StringEncoding, @"a failed save leaves the document's encoding");
    [chosen->_textStorage.mutableString appendString:@"# \u8a2d\u5b9a\n"];
    expected = [NSMutableData dataWithBytes:"\xEF\xBB\xBF" length:3]; [expected appendData:UTF8(chosen->_textStorage.string)];
    check(Write(chosen, rulesURL, NSAutosaveInPlaceOperation) && [Bytes(gRulesPath) isEqualToData:expected] && chosen->_ownTextFile == TSOwnTextFileSpellingRules,
          @"after a copy and a failed save the rules are still written in UTF-8 with their byte order mark");

    // A command completion file in Latin 1 whose new text does not fit Latin 1 is written in UTF-8, all of it.
    [legacy writeToFile:xml atomically:YES];
    TSDocument *grow = Open([NSURL fileURLWithPath:xml]);
    [grow->_textStorage.mutableString appendString:@"\u8ffd\u52a0 \u6771\u4eac\n"];
    check(Write(grow, [NSURL fileURLWithPath:xml], NSSaveOperation) && [Bytes(xml) isEqualToData:UTF8(grow->_textStorage.string)] && grow->_encoding == NSUTF8StringEncoding,
          @"a command completion file whose new text does not fit its encoding is written in UTF-8");

    // Written to the command completion file by a document that stays an ordinary file (Save To), the list is read again.
    NSString *ordinaryPath = [folder stringByAppendingPathComponent:@"ordinary.txt"];
    [UTF8(@"ordinary-dictionary-content\n") writeToFile:ordinaryPath atomically:YES];
    TSDocument *ordinary = Open([NSURL fileURLWithPath:ordinaryPath]);
    [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.1]];
    NSUInteger before = delegate.completionReads;
    check(Write(ordinary, completionURL, NSSaveToOperation) && ordinary->_ownTextFile == TSOwnTextFileNone, @"a copy is saved where the completion file is");
    for (int i = 0; i < 20 && delegate.completionReads == before; i++) [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.02]];
    check(delegate.completionReads == before + 1, @"the list is read again after a copy is saved where the completion file is");
    // A copy open for preview only is not a completion file being edited.
    TSDocument *previewCopy = Open(completionURL);
    check([previewCopy isCommandCompletionFile], @"a completion file being edited counts");
    previewCopy->_externalEditor = YES;
    check(![previewCopy isCommandCompletionFile], @"a copy of the completion file open for preview only does not count");

    // While a command completion file is open, however it was opened, nothing is registered in it.
    g_canRegisterCommandCompletion = YES;
    Open(completionURL);
    check(!g_canRegisterCommandCompletion, @"opening a command completion file stops registering");

    // A duplicate of the rules is read as the rules are, \UTF{20AC} and non-ASCII text included.
    NSMutableData *dupBytes = [NSMutableData dataWithBytes:"\xEF\xBB\xBF" length:3]; [dupBytes appendData:UTF8(rules)];
    [dupBytes writeToFile:gRulesPath atomically:YES];
    TSDocument *original = Open(rulesURL);
    NSError *dupError = nil;
    TSDocument *dup = (TSDocument *)[original duplicateAndReturnError:&dupError];
    check(dup != nil && [dup->_textStorage.string isEqualToString:original->_textStorage.string] && dup->_ownTextFile == TSOwnTextFileSpellingRules,
          @"a duplicate of the rules has the same text and is the same kind of file");
    [dup close];

    // Rules that are not UTF-8 and get text Latin 9 cannot hold are written in UTF-8.
    NSData *latinRules = [@"# caf\u00e9\n" dataUsingEncoding:NSISOLatin9StringEncoding];
    [latinRules writeToFile:gRulesPath atomically:YES];
    TSDocument *lr = Open(rulesURL);
    [lr->_textStorage.mutableString appendString:@"# \u6771\u4eac\n"];
    check(Write(lr, rulesURL, NSSaveOperation) && [Bytes(gRulesPath) isEqualToData:UTF8(lr->_textStorage.string)], @"rules that no longer fit Latin 9 are written in UTF-8");

    // An untitled duplicate is autosaved and read back (as when it is restored) as the same kind of file.
    NSMutableData *dupRules = [NSMutableData dataWithBytes:"\xEF\xBB\xBF" length:3]; [dupRules appendData:UTF8(rules)];
    [dupRules writeToFile:gRulesPath atomically:YES];
    TSDocument *source = Open(rulesURL);
    TSDocument *untitled = (TSDocument *)[source duplicateAndReturnError:NULL];
    [untitled->_textStorage.mutableString appendString:@"# \u6771\u4eac\n"];
    NSString *autosaved = [folder stringByAppendingPathComponent:@"Untitled (Autosaved).txt"];
    check(Write(untitled, [NSURL fileURLWithPath:autosaved], NSAutosaveElsewhereOperation), @"the untitled duplicate is autosaved");
    NSMutableData *autosavedBytes = [NSMutableData dataWithBytes:"\xEF\xBB\xBF" length:3]; [autosavedBytes appendData:UTF8(untitled->_textStorage.string)];
    check([Bytes(autosaved) isEqualToData:autosavedBytes], @"the untitled duplicate is autosaved as the rules, with its byte order mark");
    TSDocument *restored = [TSDocument new]; NSError *re = nil;
    check([restored readFromURL:[NSURL fileURLWithPath:autosaved] ofType:@"public.plain-text" error:&re] && restored->_ownTextFile == TSOwnTextFileSpellingRules &&
          [restored->_textStorage.string isEqualToString:untitled->_textStorage.string], @"the restored untitled duplicate is the rules, with the same text");
    [untitled close];

    // Moved to where the command completion file is, a document becomes it, and stops registering; moved away, the list is read again.
    NSString *plain = [folder stringByAppendingPathComponent:@"plain.txt"];
    [UTF8(@"ordinary content\n") writeToFile:plain atomically:YES];
    TSDocument *moved = Open([NSURL fileURLWithPath:plain]);
    g_canRegisterCommandCompletion = YES;
    [[NSFileManager defaultManager] removeItemAtPath:CommandCompletionPathRegular error:NULL];
    [[NSFileManager defaultManager] moveItemAtPath:plain toPath:CommandCompletionPathRegular error:NULL];
    moved.fileURL = completionURL;
    check(moved->_ownTextFile == TSOwnTextFileCommandCompletion && !g_canRegisterCommandCompletion, @"moved to the completion file, the document is it and registering stops");
    [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.1]];  // earlier saves read the list again too
    g_canRegisterCommandCompletion = NO;
    NSUInteger reads = delegate.completionReads;
    [[NSFileManager defaultManager] moveItemAtPath:CommandCompletionPathRegular toPath:plain error:NULL];
    moved.fileURL = [NSURL fileURLWithPath:plain];
    check(moved->_ownTextFile == TSOwnTextFileNone && delegate.completionReads == reads + 1 && g_canRegisterCommandCompletion,
          @"moved away, it is an ordinary file, and the list is read again before registering resumes");
    // Saved as the completion file, the list is read again from what was saved.
    TSDocument *saveAs = Open([NSURL fileURLWithPath:plain]);
    [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.1]];  // earlier saves read the list again too
    reads = delegate.completionReads;
    check(Write(saveAs, completionURL, NSSaveAsOperation) && saveAs->_ownTextFile == TSOwnTextFileCommandCompletion && !g_canRegisterCommandCompletion,
          @"saved as the completion file, the document is it and registering stops");
    for (int i = 0; i < 20 && delegate.completionReads == reads; i++) [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.02]];
    check(delegate.completionReads == reads + 1, @"the list is read again from the saved completion file");

    // The save panel shows the encoding an own file is written in, and it cannot be changed.
    [UTF8(@"% !TEX encoding = IsoLatin\ncaf\u00e9\n") writeToFile:gRulesPath atomically:YES];
    TSDocument *panelDoc = Open(rulesURL);
    NSPopUpButton *menu = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
    for (NSNumber *tag in @[@(NSISOLatin1StringEncoding), @(NSUTF8StringEncoding)]) { [menu addItemWithTitle:tag.stringValue]; menu.lastItem.tag = tag.integerValue; }
    [panelDoc setUpEncodingMenuInSavePanel:menu];
    check(menu.selectedTag == NSUTF8StringEncoding && !menu.enabled, @"the save panel shows UTF-8 for the rules, fixed");

    // An ordinary file with the same text still follows its magic comment and is converted for TeX.
    NSString *other = [folder stringByAppendingPathComponent:@"other.txt"];
    [UTF8(rules) writeToFile:other atomically:YES];
    gConversions = 0;
    TSDocument *tex = Open([NSURL fileURLWithPath:other]);
    check(tex->_ownTextFile == TSOwnTextFileNone && tex->_encoding == NSISOLatin1StringEncoding && gConversions > 0, @"an ordinary file follows its magic comment");
    fprintf(stderr, "PASS: TeXShop's own text files are plain text, read and saved as TeXShop reads them, and edited in TeXShop\n");
}}
'''.replace('HELPERS', helpers).replace('METHODS', methods)
with tempfile.TemporaryDirectory(prefix='texshop-own-files-') as folder:
    p = Path(folder); (p/'test.m').write_text(program, encoding='utf-8')
    work = p/'files'; work.mkdir()
    subprocess.run(['xcrun', 'clang', '-I', str(root/'Tests'), '-fobjc-arc', '-Wno-deprecated-declarations', '-Wno-unused-function', '-framework', 'Cocoa',
                    str(p/'test.m'), '-o', str(p/'test')], check=True)
    subprocess.run([str(p/'test'), str(work)], check=True, timeout=60)
