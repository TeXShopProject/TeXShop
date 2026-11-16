#!/usr/bin/env python3
"""Replace All in the TeX sources of a root, the parts that need no window (Issue #45, spec §2.5, §2.6):
the plan fixed when Replace All is approved, the check of the files' versions against a new collection, the backup
folder, writing one file on the disk, and where the items that were off are after the replacements.

A real folder is used: UTF-8 with CRLF, UTF-8 with a byte order mark and no last line break, Shift JIS, mixed line
endings, permissions, an extended attribute and a creation date. Failures are injected: a file changed with the same
size and date, a file gone, a file changed right before it is replaced, attributes that cannot be copied, a backup
folder that cannot be written, and a text that does not read back. With --mutations, broken copies must be caught."""
from pathlib import Path
import shutil, subprocess, sys, tempfile

root = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(root / 'Tests'))
from source_tree import include_args

ENGINE = ['TSRegexFindOptions.m', 'TSRegexFindPattern.m', 'TSRegexReplacementTemplate.m', 'TSRegexTextFind.m', 'TSRegexFindReplacement.m',
          'TSRegexReplaceAllResult.m', 'TSRegexMultipleReplace.m', 'TSRegexReplacementRule.m', 'TSRegexPatternLexer.m',
          'TSRegexOnigmoIncompatibility.m']
SOURCES = {**{name: f'Sources/Find/{name}' for name in ENGINE},
           'TSTeXRootSearch.m': 'Sources/Find/TeXRoot/TSTeXRootSearch.m',
           'TSTeXRootReplace.m': 'Sources/Find/TeXRoot/TSTeXRootReplace.m',
           'TSTeXRootSearchModel.m': 'Sources/Find/TeXRoot/TSTeXRootSearchModel.m',
           'TSTeXRootProject.m': 'Sources/Document/TSTeXRootProject.m',
           'TSRootFileResolver.m': 'Sources/Document/TSRootFileResolver.m',
           'TSSourceMagicComments.m': 'Sources/Document/TSSourceMagicComments.m'}
HEADERS = ['Sources/Find/TeXRoot/TSTeXRootReplace.h', 'Sources/Find/TeXRoot/TSTeXRootSearchModel.h', 'Sources/Find/TeXRoot/TSTeXRootSearch.h']

PROGRAM = r'''
#import <Foundation/Foundation.h>
#import "TSTeXRootReplace.h"
#import "TSTeXRootSearchModel.h"
#include <sys/xattr.h>
#include <sys/stat.h>
#include <fcntl.h>

static int failures = 0;
static void Check(BOOL ok, NSString *what) { if (!ok) { printf("FAIL: %s\n", what.UTF8String); failures++; } }
static NSString *Folder;
static NSStringEncoding SJIS(void) { return CFStringConvertEncodingToNSStringEncoding(kCFStringEncodingShiftJIS); }
static NSString *P(NSString *relative) { return [Folder stringByAppendingPathComponent:relative]; }
static NSData *Bytes(NSString *relative) { return [NSData dataWithContentsOfFile:P(relative)]; }
static void WriteBytes(NSString *relative, NSData *data) {
    [NSFileManager.defaultManager createDirectoryAtPath:P(relative).stringByDeletingLastPathComponent withIntermediateDirectories:YES attributes:nil error:NULL];
    [data writeToFile:P(relative) atomically:NO];
}
static NSData *U8(NSString *s) { return [s dataUsingEncoding:NSUTF8StringEncoding]; }
static BOOL Spin(BOOL (^done)(void), NSTimeInterval timeout) {
    NSDate *limit = [NSDate dateWithTimeIntervalSinceNow:timeout];
    while (!done() && limit.timeIntervalSinceNow > 0)
        [NSRunLoop.currentRunLoop runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.005]];
    return done();
}

static TSTeXRootSourceCodec *Codec(BOOL latin1) {
    return [[TSTeXRootSourceCodec alloc] initWithEncodingForData:^NSStringEncoding(NSData *data, NSURL *url) {
        if (latin1) return NSISOLatin1StringEncoding;
        return [url.lastPathComponent hasPrefix:@"sjis"] ? SJIS() : NSUTF8StringEncoding;
    } textForEditing:^NSString *(NSString *t, NSStringEncoding e) { return t; } textForSaving:^NSString *(NSString *t, NSStringEncoding e) { return t; }];
}

static TSTeXRootProject *CollectWithOpen(NSDictionary *open) {
    TSTeXRootProjectCollector *collector = [[TSTeXRootProjectCollector alloc] initWithRootURL:[NSURL fileURLWithPath:P(@"root.tex")] codec:Codec(NO)
                                                                             allowsSourceDoc:NO jobNameToken:@"\\jobname"];
    if (open)
        collector.openDocumentTexts = open;
    return [collector collect];
}
static TSTeXRootProject *Collect(void) { return CollectWithOpen(nil); }
static id Identity(NSString *relative) {
    id identifier = nil;
    [[NSURL fileURLWithPath:P(relative)] getResourceValue:&identifier forKey:NSURLFileResourceIdentifierKey error:NULL];
    return identifier;
}

static NSArray<TSTeXRootSearchSource *> *Sources(TSTeXRootProject *project) {
    NSMutableArray *sources = [NSMutableArray array];
    for (TSTeXRootProjectFile *file in project.files)
        [sources addObject:file.isOpen ? [[TSTeXRootSearchSource alloc] initWithFile:file openDocumentText:file.text lineEnding:nil searchOnlyReason:TSTeXRootSearchOnlyReasonNone]
                                       : [[TSTeXRootSearchSource alloc] initWithFile:file]];
    return sources;
}

static TSTeXRootSearchResult *Search(TSTeXRootProject *project, NSString *find, NSString *replace) {
    TSTeXRootSearchQuery *query = [TSTeXRootSearchQuery replaceQueryWithString:find replacement:replace options:TSRegexFindRegularExpression | TSRegexFindUnescapesReplacement syntax:TSRegexReplacementSyntaxICU error:NULL];
    return [TSTeXRootSearch searchSources:Sources(project) query:query generation:1 codec:Codec(NO) maximumItemsPerFile:5000 maximumItems:500000 cancellation:nil progress:nil];
}

static TSTeXRootSearchFileResult *Named(TSTeXRootSearchResult *result, NSString *relative) {
    for (TSTeXRootSearchFileResult *file in result.files) if ([file.source.file.relativePath isEqualToString:relative]) return file;
    return nil;
}

static void MakeFixture(void) {
    Folder = [[NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString] stringByResolvingSymlinksInPath];
    WriteBytes(@"root.tex", U8(@"\\documentclass{article}\nfoo in root\n"));
    WriteBytes(@"chapters/crlf.tex", U8(@"% !TEX root = ../root.tex\r\nfoo one\r\nkeep foo two\r\n"));
    NSMutableData *bom = [NSMutableData dataWithBytes:"\xEF\xBB\xBF" length:3];
    [bom appendData:U8(@"% !TEX root = ../root.tex\nfoo with BOM, no last line break")];
    WriteBytes(@"chapters/bom.tex", bom);
    WriteBytes(@"chapters/sjis.tex", [@"% !TEX root = ../root.tex\n\u65e5\u672c\u8a9e foo\n" dataUsingEncoding:SJIS()]);
    WriteBytes(@"chapters/mixed.tex", U8(@"% !TEX root = ../root.tex\r\nfoo A\nfoo B\rfoo C"));
    chmod(P(@"chapters/crlf.tex").fileSystemRepresentation, 0640);
    setxattr(P(@"chapters/crlf.tex").fileSystemRepresentation, "org.texshop.test", "kept", 4, 0, 0);
    [NSFileManager.defaultManager setAttributes:@{NSFileCreationDate: [NSDate dateWithTimeIntervalSince1970:1000000000]} ofItemAtPath:P(@"chapters/crlf.tex") error:NULL];
}

static BOOL Included(TSTeXRootSearchItem *item, TSTeXRootSearchFileResult *file) {
    // "keep foo two" stays off
    return ![[item.beforeText substringToIndex:MIN(item.beforeText.length, (NSUInteger)4)] isEqualToString:@"keep"];
}

static NSArray<NSString *> *Leftovers(void) {
    NSMutableArray *found = [NSMutableArray array];
    for (NSString *path in [NSFileManager.defaultManager enumeratorAtPath:Folder])
        if ([path containsString:@".texshop-"]) [found addObject:path];
    return found;
}

int main(void) { @autoreleasepool {
    MakeFixture();
    // The root is open with a text of its own: replaced on screen, after the files on the disk.
    TSTeXRootProject *project = CollectWithOpen(@{Identity(@"root.tex"): @"\\documentclass{article}\nfoo foo open\n"});
    TSTeXRootSearchResult *result = Search(project, @"foo", @"bar\\n");
    TSTeXRootReplacePlan *plan = [TSTeXRootReplacePlan planWithResults:result.files isIncluded:^BOOL(TSTeXRootSearchItem *item, TSTeXRootSearchFileResult *file) { return Included(item, file); } codec:Codec(NO) error:NULL];
    Check(plan.numberOfItems == 8 && plan.numberOfFilesOnDisk == 4 && plan.files.count == 5, [NSString stringWithFormat:@"plan: %lu items in %lu files", (unsigned long)plan.numberOfItems, (unsigned long)plan.files.count]);
    Check(plan.files.lastObject.openDocument && plan.files.lastObject.file.isRoot && !plan.files.lastObject.replacedData && !plan.files.firstObject.openDocument
          && [plan.files.lastObject.replacedText isEqualToString:@"\\documentclass{article}\nbar\n bar\n open\n"], @"the open document comes last, with its text only");
    TSTeXRootReplaceFile *crlf = nil, *bomFile = nil, *sjis = nil, *mixed = nil;
    for (TSTeXRootReplaceFile *file in plan.files) {
        if ([file.file.relativePath isEqualToString:@"chapters/crlf.tex"]) crlf = file;
        if ([file.file.relativePath isEqualToString:@"chapters/bom.tex"]) bomFile = file;
        if ([file.file.relativePath isEqualToString:@"chapters/sjis.tex"]) sjis = file;
        if ([file.file.relativePath isEqualToString:@"chapters/mixed.tex"]) mixed = file;
    }
    Check([crlf.replacedData isEqualToData:U8(@"% !TEX root = ../root.tex\r\nbar\r\n one\r\nkeep foo two\r\n")], @"CRLF kept, the line break put in is CRLF, the item off left as it is");
    NSMutableData *bomExpected = [NSMutableData dataWithBytes:"\xEF\xBB\xBF" length:3];
    [bomExpected appendData:U8(@"% !TEX root = ../root.tex\nbar\n with BOM, no last line break")];
    Check([bomFile.replacedData isEqualToData:bomExpected], @"the byte order mark and the missing last line break are kept");
    Check([sjis.replacedData isEqualToData:[@"% !TEX root = ../root.tex\n\u65e5\u672c\u8a9e bar\n\n" dataUsingEncoding:SJIS()]], @"Shift JIS is kept");
    Check([mixed.replacedData isEqualToData:U8(@"% !TEX root = ../root.tex\r\nbar\n A\nbar\r B\rbar\r\n C")], @"mixed line endings: each line's own, the first one's on the last line");
    Check([crlf.originalSHA256 isEqualToData:[TSTeXRootProjectCollector sha256OfData:Bytes(@"chapters/crlf.tex")]], @"the approved SHA-256 is that of the bytes read");
    // The open document is backed up from its text as approved; written in UTF-8, it is named in the notes.
    NSArray<NSString *> *notes = nil;
    NSURL *openBackup = [TSTeXRootBackup backUpPlan:plan inFolder:[NSURL fileURLWithPath:Folder] date:[NSDate dateWithTimeIntervalSince1970:1600000000]
                                   openDocumentData:^NSData *(TSTeXRootReplaceFile *f, BOOL *utf8) { *utf8 = YES; return U8(f.originalText); } notes:&notes cancellation:nil error:NULL];
    Check([[NSData dataWithContentsOfURL:[openBackup URLByAppendingPathComponent:@"root.tex"]] isEqualToData:U8(@"\\documentclass{article}\nfoo foo open\n")]
          && [notes isEqualToArray:@[@"root.tex"]], [NSString stringWithFormat:@"the open document's backup and the note (%@)", notes]);
    [NSFileManager.defaultManager removeItemAtPath:P(@"TeXShop Backups") error:NULL];

    // Checks 1 and 2 of §2.5.1: a file changed with the same size and date, a file gone.
    Check([plan filesOnDiskChangedInProject:Collect()].count == 0, @"nothing changed: no file reported");
    struct stat times;
    stat(P(@"chapters/mixed.tex").fileSystemRepresentation, &times);
    NSMutableData *same = [Bytes(@"chapters/mixed.tex") mutableCopy];
    ((char *)same.mutableBytes)[same.length - 1] = 'D';
    [same writeToFile:P(@"chapters/mixed.tex") atomically:NO];
    struct timespec kept[2] = {times.st_atimespec, times.st_mtimespec};
    utimensat(AT_FDCWD, P(@"chapters/mixed.tex").fileSystemRepresentation, kept, 0);
    for (TSTeXRootProjectFile *file in Collect().files)
        if ([file.relativePath isEqualToString:@"chapters/mixed.tex"])
            Check([file.modificationDate isEqualToDate:mixed.file.modificationDate] && file.size == mixed.file.size, @"the test keeps the size and the date");
    NSArray *changed = [plan filesOnDiskChangedInProject:Collect()];
    Check(changed.count == 1 && changed.firstObject == mixed, @"a change with the same size and date is found by its content");
    NSData *mixedNow = Bytes(@"chapters/mixed.tex");
    [NSFileManager.defaultManager removeItemAtPath:P(@"chapters/bom.tex") error:NULL];
    changed = [plan filesOnDiskChangedInProject:Collect()];
    Check(changed.count == 2 && [changed containsObject:bomFile], @"a file gone is reported");
    WriteBytes(@"chapters/bom.tex", bomExpected); // another file at the same path
    changed = [plan filesOnDiskChangedInProject:Collect()];
    Check([changed containsObject:bomFile], @"another file at the same path is reported (its identity)");

    // The backup: never an existing folder; the bytes approved; the attributes; all or nothing.
    TSTeXRootProject *fresh = Collect();
    result = Search(fresh, @"foo", @"bar\\n");
    plan = [TSTeXRootReplacePlan planWithResults:result.files isIncluded:^BOOL(TSTeXRootSearchItem *item, TSTeXRootSearchFileResult *file) { return Included(item, file); } codec:Codec(NO) error:NULL];
    for (TSTeXRootReplaceFile *file in plan.files) if ([file.file.relativePath isEqualToString:@"chapters/crlf.tex"]) crlf = file;
    NSDate *date = [NSDate dateWithTimeIntervalSince1970:1800000000];
    NSString *name = [TSTeXRootBackup folderNameForDate:date];
    Check(name.length == 19 && [name characterAtIndex:4] == '-' && [name characterAtIndex:13] == '.', [@"folder name " stringByAppendingString:name]);
    NSError *error = nil;
    NSURL *backup = [TSTeXRootBackup backUpPlan:plan inFolder:[NSURL fileURLWithPath:Folder] date:date openDocumentData:^NSData *(TSTeXRootReplaceFile *f, BOOL *utf8) { return nil; } notes:NULL cancellation:nil error:&error];
    Check(backup && [backup.lastPathComponent isEqualToString:name] && [backup.URLByDeletingLastPathComponent.lastPathComponent isEqualToString:@"TeXShop Backups"], @"the backup folder");
    Check([[NSData dataWithContentsOfURL:[backup URLByAppendingPathComponent:@"chapters/crlf.tex"]] isEqualToData:Bytes(@"chapters/crlf.tex")]
          && [[NSData dataWithContentsOfURL:[backup URLByAppendingPathComponent:@"chapters/sjis.tex"]] isEqualToData:Bytes(@"chapters/sjis.tex")], @"the backup has the bytes approved under the relative paths");
    char value[8] = {0};
    struct stat info;
    stat([backup URLByAppendingPathComponent:@"chapters/crlf.tex"].fileSystemRepresentation, &info);
    Check(getxattr([backup URLByAppendingPathComponent:@"chapters/crlf.tex"].fileSystemRepresentation, "org.texshop.test", value, sizeof value, 0, 0) == 4 && (info.st_mode & 0777) == 0640,
          @"the backup keeps the extended attributes and permissions");
    NSURL *second = [TSTeXRootBackup backUpPlan:plan inFolder:[NSURL fileURLWithPath:Folder] date:date openDocumentData:^NSData *(TSTeXRootReplaceFile *f, BOOL *utf8) { return nil; } notes:NULL cancellation:nil error:&error];
    Check([second.lastPathComponent isEqualToString:[name stringByAppendingString:@" 2"]], @"a second backup in the same second gets \" 2\"");
    // A file changed before the backup: nothing is left.
    NSData *rootBytes = Bytes(@"root.tex");
    WriteBytes(@"root.tex", U8(@"\\documentclass{article}\nfoo changed\n"));
    NSURL *third = [TSTeXRootBackup backUpPlan:plan inFolder:[NSURL fileURLWithPath:Folder] date:date openDocumentData:^NSData *(TSTeXRootReplaceFile *f, BOOL *utf8) { return nil; } notes:NULL cancellation:nil error:&error];
    Check(!third && error.code == TSTeXRootReplaceErrorChanged && ![NSFileManager.defaultManager fileExistsAtPath:[backup.path stringByAppendingString:@" 3"]],
          @"a file changed before the backup: an error, and the folder made is removed");
    WriteBytes(@"root.tex", rootBytes);
    // A folder that cannot be written.
    NSString *backups = P(@"TeXShop Backups");
    chmod(backups.fileSystemRepresentation, 0555);
    error = nil;
    NSURL *refused = [TSTeXRootBackup backUpPlan:plan inFolder:[NSURL fileURLWithPath:Folder] date:[NSDate dateWithTimeIntervalSince1970:1900000000] openDocumentData:^NSData *(TSTeXRootReplaceFile *f, BOOL *utf8) { return nil; } notes:NULL cancellation:nil error:&error];
    chmod(backups.fileSystemRepresentation, 0755);
    Check(!refused && error.code == TSTeXRootReplaceErrorBackup, @"a backup folder that cannot be written: an error");
    // Stopped while backing up: nothing left.
    __block NSUInteger asked = 0;
    NSURL *stopped = [TSTeXRootBackup backUpPlan:plan inFolder:[NSURL fileURLWithPath:Folder] date:[NSDate dateWithTimeIntervalSince1970:1700000000] openDocumentData:^NSData *(TSTeXRootReplaceFile *f, BOOL *utf8) { return nil; } notes:NULL
                                     cancellation:^BOOL { return ++asked > 2; } error:&error];
    NSArray *made = [NSFileManager.defaultManager contentsOfDirectoryAtPath:backups error:NULL];
    Check(!stopped && error.code == TSTeXRootReplaceErrorStopped && made.count == 2, [NSString stringWithFormat:@"stopped while backing up: the folder goes (%@)", made]);

    // A file that got a second name (a hard link) or became read-only since it was approved: its content is the same,
    // but it can no longer be replaced in (spec §2.5.2). The check stops, and so does the writer.
    NSString *extraName = P(@"chapters/link-to-sjis.tex");
    link(P(@"chapters/sjis.tex").fileSystemRepresentation, extraName.fileSystemRepresentation);
    NSArray *linked = [plan filesOnDiskChangedInProject:Collect()];
    BOOL sjisReported = NO;
    for (TSTeXRootReplaceFile *file in linked) sjisReported |= [file.file.relativePath isEqualToString:@"chapters/sjis.tex"];
    NSData *sjisBefore = Bytes(@"chapters/sjis.tex");
    TSTeXRootReplaceFile *sjisPlanned = nil;
    for (TSTeXRootReplaceFile *file in plan.files) if ([file.file.relativePath isEqualToString:@"chapters/sjis.tex"]) sjisPlanned = file;
    TSTeXRootDiskWriter *strict = [[TSTeXRootDiskWriter alloc] initWithCodec:Codec(NO)];
    error = nil;
    Check(sjisReported && ![strict writeFile:sjisPlanned error:&error] && error.code == TSTeXRootReplaceErrorChanged
          && [Bytes(@"chapters/sjis.tex") isEqualToData:sjisBefore] && [[NSData dataWithContentsOfFile:extraName] isEqualToData:sjisBefore] && Leftovers().count == 0,
          @"a hard link added since: the check reports it, the writer refuses, both names keep the content");
    unlink(extraName.fileSystemRepresentation);
    chmod(P(@"chapters/sjis.tex").fileSystemRepresentation, 0444);
    linked = [plan filesOnDiskChangedInProject:Collect()];
    sjisReported = NO;
    for (TSTeXRootReplaceFile *file in linked) sjisReported |= [file.file.relativePath isEqualToString:@"chapters/sjis.tex"];
    Check(sjisReported, @"a file made read-only since: the check reports it");
    chmod(P(@"chapters/sjis.tex").fileSystemRepresentation, 0644);
    // A hard link made right before the writer looks again (inside the coordination).
    strict.beforeCheck = ^(NSURL *url) { link(url.fileSystemRepresentation, extraName.fileSystemRepresentation); };
    error = nil;
    Check(![strict writeFile:sjisPlanned error:&error] && error.code == TSTeXRootReplaceErrorChanged && [Bytes(@"chapters/sjis.tex") isEqualToData:sjisBefore]
          && [[NSData dataWithContentsOfFile:extraName] isEqualToData:sjisBefore] && Leftovers().count == 0, @"a hard link made right before replacing: refused, nothing written");
    unlink(extraName.fileSystemRepresentation);

    // Writing: check 3, attributes, and the text read back.
    TSTeXRootDiskWriter *writer = [[TSTeXRootDiskWriter alloc] initWithCodec:Codec(NO)];
    NSDate *created = [NSFileManager.defaultManager attributesOfItemAtPath:P(@"chapters/crlf.tex") error:NULL][NSFileCreationDate];
    writer.failsCopyingAttributes = YES;
    NSData *before = Bytes(@"chapters/crlf.tex");
    Check(![writer writeFile:crlf error:&error] && error.code == TSTeXRootReplaceErrorAttributes && [Bytes(@"chapters/crlf.tex") isEqualToData:before] && Leftovers().count == 0,
          @"attributes that cannot be copied: nothing written, no file left");
    writer.failsCopyingAttributes = NO;
    writer.beforeCheck = ^(NSURL *url) { [U8(@"% !TEX root = ../root.tex\r\nchanged by another app\r\n") writeToURL:url atomically:NO]; };
    Check(![writer writeFile:crlf error:&error] && error.code == TSTeXRootReplaceErrorChanged
          && [Bytes(@"chapters/crlf.tex") isEqualToData:U8(@"% !TEX root = ../root.tex\r\nchanged by another app\r\n")] && Leftovers().count == 0,
          @"a change right before replacing: the other app's text is kept, no file left");
    [before writeToFile:P(@"chapters/crlf.tex") atomically:NO];
    chmod(P(@"chapters/crlf.tex").fileSystemRepresentation, 0640);
    setxattr(P(@"chapters/crlf.tex").fileSystemRepresentation, "org.texshop.test", "kept", 4, 0, 0);
    [NSFileManager.defaultManager setAttributes:@{NSFileCreationDate: created} ofItemAtPath:P(@"chapters/crlf.tex") error:NULL];
    writer.beforeCheck = nil;
    Check([writer writeFile:crlf error:&error] && [Bytes(@"chapters/crlf.tex") isEqualToData:crlf.replacedData] && Leftovers().count == 0, [@"written: " stringByAppendingString:error.description ?: @""]);
    memset(value, 0, sizeof value);
    stat(P(@"chapters/crlf.tex").fileSystemRepresentation, &info);
    NSDate *createdAfter = [NSFileManager.defaultManager attributesOfItemAtPath:P(@"chapters/crlf.tex") error:NULL][NSFileCreationDate];
    Check(getxattr(P(@"chapters/crlf.tex").fileSystemRepresentation, "org.texshop.test", value, sizeof value, 0, 0) == 4 && (info.st_mode & 0777) == 0640
          && [createdAfter isEqualToDate:created], @"the written file keeps the permissions, the extended attributes and the creation date");
    TSTeXRootDiskWriter *misreading = [[TSTeXRootDiskWriter alloc] initWithCodec:Codec(YES)];
    TSTeXRootReplaceFile *sjisNow = nil;
    for (TSTeXRootReplaceFile *file in plan.files) if ([file.file.relativePath isEqualToString:@"chapters/sjis.tex"]) sjisNow = file;
    Check(![misreading writeFile:sjisNow error:&error] && error.code == TSTeXRootReplaceErrorVerification, @"a file that does not read back as meant is reported");
    (void)mixedNow;

    // Where the items that were off are after the replacements (spec §2.6: "x x").
    TSRegexFindReplacement *first = [[TSRegexFindReplacement alloc] initWithRange:NSMakeRange(0, 1) string:@"xxxx"];
    NSArray *moved = [TSTeXRootReplaceMapping ranges:@[[NSValue valueWithRange:NSMakeRange(2, 1)]] afterReplacements:@[first]];
    Check(NSEqualRanges([moved.firstObject rangeValue], NSMakeRange(5, 1)), @"x x: the x off moves from 2 to 5");
    Check([TSTeXRootReplaceMapping range:NSMakeRange(5, 1) overlapsRange:NSMakeRange(5, 1)] && ![TSTeXRootReplaceMapping range:NSMakeRange(3, 1) overlapsRange:NSMakeRange(5, 1)]
          && ![TSTeXRootReplaceMapping range:NSMakeRange(4, 1) overlapsRange:NSMakeRange(5, 1)] && [TSTeXRootReplaceMapping range:NSMakeRange(5, 0) overlapsRange:NSMakeRange(4, 1)]
          && [TSTeXRootReplaceMapping range:NSMakeRange(6, 0) overlapsRange:NSMakeRange(5, 1)] && [TSTeXRootReplaceMapping range:NSMakeRange(4, 3) overlapsRange:NSMakeRange(5, 1)],
          @"overlapping: sharing a character, or an empty range within, ends included");
    TSRegexFindReplacement *shorter = [[TSRegexFindReplacement alloc] initWithRange:NSMakeRange(10, 5) string:@""];
    moved = [TSTeXRootReplaceMapping ranges:@[[NSValue valueWithRange:NSMakeRange(2, 1)], [NSValue valueWithRange:NSMakeRange(20, 2)]] afterReplacements:@[first, shorter]];
    Check(NSEqualRanges([moved[0] rangeValue], NSMakeRange(5, 1)) && NSEqualRanges([moved[1] rangeValue], NSMakeRange(18, 2)), @"ranges after several replacements, longer and shorter");

    // The search after Replace All: "x x", the second x off; after replacing the first by xxxx, the x at 5 stays off.
    WriteBytes(@"chapters/xx.tex", U8(@"% !TEX root = ../root.tex\nx x\n"));
    TSTeXRootSearchEnvironment *environment = [TSTeXRootSearchEnvironment new];
    environment.codec = Codec(NO);
    environment.collectorForRoot = ^TSTeXRootProjectCollector *(NSURL *rootURL) {
        return [[TSTeXRootProjectCollector alloc] initWithRootURL:rootURL codec:Codec(NO) allowsSourceDoc:NO jobNameToken:@"\\jobname"];
    };
    environment.performAfterDelay = ^(NSTimeInterval delay, dispatch_block_t block) { dispatch_async(dispatch_get_main_queue(), block); };
    TSTeXRootSearchModel *model = [[TSTeXRootSearchModel alloc] initWithRootURL:[NSURL fileURLWithPath:P(@"root.tex")] environment:environment];
    [model setMode:TSTeXRootSearchModeReplace findString:@"\\bx\\b" replaceString:@"xxxx" options:TSRegexFindRegularExpression syntax:TSRegexReplacementSyntaxICU multipleReplace:nil];
    [model collect];
    Spin(^BOOL { return model.activity == TSTeXRootSearchActivityIdle && model.project && model.resultGeneration == model.generation; }, 30);
    TSTeXRootSearchFileResult *xx = nil;
    for (TSTeXRootSearchFileResult *file in model.results) if ([file.source.file.relativePath isEqualToString:@"chapters/xx.tex"]) xx = file;
    [model setItems:@[xx.items[1]] inFile:xx included:NO];
    TSTeXRootReplacePlan *xPlan = [TSTeXRootReplacePlan planWithResults:@[xx] isIncluded:^BOOL(TSTeXRootSearchItem *item, TSTeXRootSearchFileResult *file) { return [model isItemIncluded:item inFile:file]; } codec:Codec(NO) error:NULL];
    Check(xPlan.numberOfItems == 1 && [writer writeFile:xPlan.files.firstObject error:&error], @"the first x replaced");
    NSArray *off = [TSTeXRootReplaceMapping ranges:@[[NSValue valueWithRange:xx.items[1].range]] afterReplacements:xPlan.files.firstObject.replacements];
    [model searchAgainAfterReplacingWithRangesOff:@{xx.source.file.relativePath: off} message:@"Replaced"];
    Spin(^BOOL { return model.activity == TSTeXRootSearchActivityIdle && model.resultGeneration == model.generation && model.numberOfCollections == 2; }, 30);
    TSTeXRootSearchFileResult *after = nil;
    for (TSTeXRootSearchFileResult *file in model.results) if ([file.source.file.relativePath isEqualToString:@"chapters/xx.tex"]) after = file;
    // \bx\b in "xxxx x": the x at 5 only (xxxx is one word)
    Check(after.items.count == 1 && after.items[0].range.location == after.source.text.length - 2 && ![model isItemIncluded:after.items[0] inFile:after]
          && [model.eventMessage isEqualToString:@"Replaced"], [NSString stringWithFormat:@"after Replace All the item that was off stays off, and the status says what was done (%@)", model.eventMessage]);
    model.findString = @"x";
    Check(model.eventMessage == nil, @"the next change clears the status");

    // New conditions while the search after Replace All runs: every item is on (spec §2.7.4), none of the old ranges.
    [model setMode:TSTeXRootSearchModeReplace findString:@"\\bx\\b" replaceString:@"y" options:TSRegexFindRegularExpression syntax:TSRegexReplacementSyntaxICU multipleReplace:nil];
    [model searchNow];
    Spin(^BOOL { return model.activity == TSTeXRootSearchActivityIdle && model.resultGeneration == model.generation; }, 30);
    for (TSTeXRootSearchFileResult *file in model.results) if ([file.source.file.relativePath isEqualToString:@"chapters/xx.tex"]) after = file;
    NSUInteger collections = model.numberOfCollections;
    [model searchAgainAfterReplacingWithRangesOff:@{after.source.file.relativePath: @[[NSValue valueWithRange:after.items[0].range]]} message:@"Replaced"];
    model.findString = @"x";
    Spin(^BOOL { return model.activity == TSTeXRootSearchActivityIdle && model.resultGeneration == model.generation && model.numberOfCollections > collections; }, 30);
    Spin(^BOOL { return model.activity == TSTeXRootSearchActivityIdle && model.resultGeneration == model.generation && model.results.count > 0; }, 30);
    Check(model.numberOfIncludedItems == model.numberOfItems && model.numberOfItems > 0,
          [NSString stringWithFormat:@"new conditions during the search after Replace All: every item on (%lu of %lu)", (unsigned long)model.numberOfIncludedItems, (unsigned long)model.numberOfItems]);

    // Many items and many ranges off: taken in one pass, the main thread is not held (spec §2.9).
    for (int f = 0; f < 10; f++) {
        NSMutableString *many = [NSMutableString stringWithString:@"% !TEX root = ../root.tex\n"];
        for (int i = 0; i < 4999; i++) [many appendString:@"x\n"];
        WriteBytes([NSString stringWithFormat:@"chapters/many%d.tex", f], U8(many));
    }
    [model setMode:TSTeXRootSearchModeReplace findString:@"^x$" replaceString:@"y" options:TSRegexFindRegularExpression | TSRegexFindAnchorsMatchLines syntax:TSRegexReplacementSyntaxICU multipleReplace:nil];
    [model collect];
    Spin(^BOOL { return model.activity == TSTeXRootSearchActivityIdle && model.resultGeneration == model.generation && model.results.count >= 10; }, 60);
    NSMutableDictionary *manyOff = [NSMutableDictionary dictionary];
    for (TSTeXRootSearchFileResult *file in model.results) {
        if (![file.source.file.relativePath hasPrefix:@"chapters/many"]) continue;
        NSMutableArray *ranges = [NSMutableArray array];
        for (NSUInteger i = 0; i < file.items.count; i += 2) [ranges addObject:[NSValue valueWithRange:file.items[i].range]];
        manyOff[file.source.file.relativePath] = ranges;
    }
    __block double longest = 0, last = CFAbsoluteTimeGetCurrent();
    NSTimer *timer = [NSTimer timerWithTimeInterval:0.002 repeats:YES block:^(NSTimer *t) { double now = CFAbsoluteTimeGetCurrent(); longest = MAX(longest, now - last); last = now; }];
    [NSRunLoop.currentRunLoop addTimer:timer forMode:NSRunLoopCommonModes];
    collections = model.numberOfCollections;
    [model searchAgainAfterReplacingWithRangesOff:manyOff message:@"Replaced"];
    last = CFAbsoluteTimeGetCurrent();
    Spin(^BOOL { return model.numberOfCollections > collections && model.activity == TSTeXRootSearchActivityIdle && model.resultGeneration == model.generation && model.results.count >= 10; }, 60);
    longest = MAX(longest, CFAbsoluteTimeGetCurrent() - last); // the last pause, which no firing of the timer follows
    [timer invalidate];
    NSUInteger offCount = model.numberOfItems - model.numberOfIncludedItems;
    Check(offCount == 10 * 2500 && longest < 0.1, [NSString stringWithFormat:@"10 × 4,999 items with 2,500 ranges off each: %lu off, the main thread held %.0f ms at most", (unsigned long)offCount, longest * 1000]);

    [NSFileManager.defaultManager removeItemAtPath:Folder error:NULL];
    if (failures) { printf("%d failures\n", failures); return 1; }
    printf("PASS: the plan of Replace All, the checks of the files' versions, the backup, writing on the disk, and the items off after replacing\n");
    return 0;
} }
'''

MUTATIONS = {
    'open documents first': ('TSTeXRootReplace.m', 'plan.files = [onDisk arrayByAddingObjectsFromArray:open];', 'plan.files = [open arrayByAddingObjectsFromArray:onDisk];'),
    'the content is not compared': ('TSTeXRootReplace.m', '            && now.sha256 && [now.sha256 isEqualToData:(NSData *_Nonnull)planned.originalSHA256]\n', '\n'),
    'check 3 is skipped': ('TSTeXRootReplace.m', 'if (!current || ![[TSTeXRootProjectCollector sha256OfData:current] isEqualToData:(NSData *_Nonnull)file.originalSHA256]) {', 'if (!current) {'),
    'attributes are not required': ('TSTeXRootReplace.m', 'if (self.failsCopyingAttributes || !TSCopyAttributes(url, temporary, NO, &problem)) {', 'if (NO) {'),
    'the backup reuses a folder': ('TSTeXRootReplace.m', '        else if (errno != EEXIST) {', '        else if (errno == EEXIST) {\n            made = url;\n        } else {'),
    'a failed backup is left': ('TSTeXRootReplace.m', '        [manager removeItemAtURL:made error:NULL];\n', ''),
    'the backup takes changed bytes': ('TSTeXRootReplace.m', '            if (data && ![[TSTeXRootProjectCollector sha256OfData:data] isEqualToData:(NSData *_Nonnull)file.originalSHA256]) {', '            if (NO) {'),
    'the text is not read back': ('TSTeXRootReplace.m', '|| !reading.decodedStrictly || ![reading.text isEqualToString:file.replacedText]) {', ') {'),
    'ranges do not move': ('TSTeXRootReplace.m', 'shift += (NSInteger)replacements[next].string.length - (NSInteger)replaced.length;', 'shift += 0;'),
    'empty ranges never overlap': ('TSTeXRootReplace.m', '        return a.location >= b.location && a.location <= NSMaxRange(b);', '        return NO;'),
    # Taken both when the first list streams in and when it is complete; either alone is enough.
    'items off are forgotten after replacing': ('TSTeXRootSearchModel.m', 'NSArray<NSValue *> *ranges = self.rangesOff[path];', 'NSArray<NSValue *> *ranges = nil;'),
    'a hard link added since is not seen': ('TSTeXRootReplace.m', 'BOOL same = now && !now.isOpen && now.searchOnlyReason == TSTeXRootSearchOnlyReasonNone', 'BOOL same = now && !now.isOpen'),
    'the writer does not look at the file again': ('TSTeXRootReplace.m', '        if (!TSStillReplaceable(writing)) {', '        if (NO) {'),
    'new conditions keep the ranges off': ('TSTeXRootSearchModel.m', '    [self.excludedItems removeAllObjects];\n    [self.rangesOff removeAllObjects];', '    [self.excludedItems removeAllObjects];'),
    'every item against every range': ('TSTeXRootSearchModel.m', 'for (NSUInteger i = first; i < count && ranges[i].rangeValue.location <= NSMaxRange(range); i++)', 'for (NSUInteger i = 0; i < count; i++)'),
    'the UTF-8 note is lost': ('TSTeXRootReplace.m', '                [utf8 addObject:file.file.relativePath];', '                ;'),
    'the temporary file is left': ('TSTeXRootReplace.m', '    if (failure) {\n        [manager removeItemAtURL:temporary error:NULL];', '    if (failure) {'),
}


def build(tmp, sources):
    program = tmp / 'probe.m'
    program.write_text(PROGRAM, encoding='utf-8')
    probe = tmp / 'probe'
    compiled = subprocess.run(['xcrun', 'clang', '-fobjc-arc', '-fmodules', '-mmacosx-version-min=14.6', '-Wall', '-Wno-unused-parameter',
                               '-I', str(sources), *include_args(root), str(program), *(str(sources / name) for name in SOURCES),
                               '-framework', 'Foundation', '-o', str(probe)], capture_output=True, text=True)
    return (probe, '') if compiled.returncode == 0 else (None, compiled.stderr)


def copy_sources(tmp):
    sources = tmp / 'sources'
    sources.mkdir()
    for name, path in SOURCES.items():
        shutil.copy(root / path, sources / name)
    for path in HEADERS:
        shutil.copy(root / path, sources / Path(path).name)
    return sources


def main():
    with tempfile.TemporaryDirectory() as directory:
        tmp = Path(directory)
        probe, errors = build(tmp, copy_sources(tmp))
        if not probe:
            print(errors)
            return 1
        result = subprocess.run([str(probe)], capture_output=True, text=True, timeout=300)
        print(result.stdout.strip() or result.stderr.strip())
        if result.returncode:
            return 1
        if '--mutations' in sys.argv:
            survived = []
            for name, (file, old, new) in MUTATIONS.items():
                mutated = tmp / ('m' + str(abs(hash(name))))
                mutated.mkdir()
                sources = copy_sources(mutated)
                text = (sources / file).read_text(encoding='utf-8')
                if text.count(old) != 1:
                    print(f'mutation {name!r}: the text to break is found {text.count(old)} times')
                    return 1
                (sources / file).write_text(text.replace(old, new), encoding='utf-8')
                mprobe, errors = build(mutated, sources)
                if not mprobe:
                    print(f'mutation {name!r} does not compile:\n{errors}')
                    return 1
                caught = subprocess.run([str(mprobe)], capture_output=True, text=True, timeout=300).returncode != 0
                print(f"{'caught' if caught else 'SURVIVED'}: {name}")
                if not caught:
                    survived.append(name)
            if survived:
                print(f'{len(survived)} mutations survived')
                return 1
            print(f'PASS: all {len(MUTATIONS)} mutations caught')
    return 0


if __name__ == '__main__':
    sys.exit(main())
