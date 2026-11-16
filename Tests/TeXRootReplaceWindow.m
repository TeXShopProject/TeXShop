// SPDX-License-Identifier: GPL-2.0-or-later
// Replace All of the window "Find in TeX Sources" (Issue #45, spec §2.5, §2.9): check 1 and the confirmation sheet,
// check 2, the backup, the files on the disk, the open documents a part at a time with one Undo, stopping, the
// report, the controls while it runs, the guard TSDocument asks, and the main thread kept free. Open documents are
// text views with an undo manager. Built by Tests/run-texroot-replace-window.py; nothing is shown and the defaults
// stay in memory.
#import "TestAppKitIsolation.h"
#import "TSTeXRootSearchWindowController.h"
#import "TSTeXRootDocumentApplier.h"
#import "TSTeXRootReplaceRun.h"
#include <sys/stat.h>

static int failures;
static void Check(BOOL ok, NSString *name)
{
    if (!ok) {
        printf("FAIL %s\n", name.UTF8String);
        failures++;
    }
}

static BOOL Spin(BOOL (^done)(void), NSTimeInterval timeout)
{
    NSDate *limit = [NSDate dateWithTimeIntervalSinceNow:timeout];
    while (!done() && limit.timeIntervalSinceNow > 0)
        [NSRunLoop.currentRunLoop runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.005]];
    return done();
}

static NSTimeInterval LongestPause(void (^start)(void), BOOL (^done)(void))
{
    __block CFAbsoluteTime last = CFAbsoluteTimeGetCurrent();
    __block NSTimeInterval longest = 0;
    NSTimer *timer = [NSTimer timerWithTimeInterval:0.005 repeats:YES block:^(NSTimer *t) {
        CFAbsoluteTime now = CFAbsoluteTimeGetCurrent();
        longest = MAX(longest, now - last);
        last = now;
    }];
    [NSRunLoop.currentRunLoop addTimer:timer forMode:NSRunLoopCommonModes];
    last = CFAbsoluteTimeGetCurrent();
    start();
    Spin(done, 300);
    longest = MAX(longest, CFAbsoluteTimeGetCurrent() - last);
    [timer invalidate];
    return longest;
}

#pragma mark Documents

/// An open document: a text view whose undo manager is its own, as a document's is.
@interface TestDocument : NSObject <NSTextViewDelegate>
@property (nonatomic, strong) NSTextView *view;
@property (nonatomic, strong) NSUndoManager *undo;
@end

@implementation TestDocument
- (NSUndoManager *)undoManagerForTextView:(NSTextView *)view { return self.undo; }
@end

static NSString *Folder;
static NSMutableDictionary<NSString *, TestDocument *> *Documents;
/// A slow file system while a collector is prepared (a download waited for), and the collectors made.
static useconds_t PrepareDelay;
static NSMutableArray<TSTeXRootProjectCollector *> *Collectors;
/// Called when a collector is made (TeXShop refreshes its list of open documents there).
static void (^OnCollect)(void);

static NSString *PathOf(NSString *relative) { return [Folder stringByAppendingPathComponent:relative]; }

static void Write(NSString *relative, NSString *text)
{
    NSString *path = PathOf(relative);
    [NSFileManager.defaultManager createDirectoryAtPath:path.stringByDeletingLastPathComponent withIntermediateDirectories:YES attributes:nil error:NULL];
    [text writeToFile:path atomically:NO encoding:NSUTF8StringEncoding error:NULL];
}

static NSString *Read(NSString *relative)
{
    return [NSString stringWithContentsOfFile:PathOf(relative) encoding:NSUTF8StringEncoding error:NULL];
}

static TestDocument *Open(NSString *relative)
{
    TestDocument *document = [TestDocument new];
    document.undo = [NSUndoManager new];
    document.view = [[NSTextView alloc] initWithFrame:NSMakeRect(0, 0, 500, 400)];
    document.view.layoutManager.allowsNonContiguousLayout = YES;
    document.view.allowsUndo = YES;
    document.view.delegate = document;
    [document.view.textStorage replaceCharactersInRange:NSMakeRange(0, 0) withString:Read(relative)];
    Documents[relative] = document;
    return document;
}

static TSTeXRootSourceCodec *Codec(void)
{
    return [[TSTeXRootSourceCodec alloc] initWithEncodingForData:^NSStringEncoding(NSData *data, NSURL *url) { return NSUTF8StringEncoding; }
                                                  textForEditing:^NSString *(NSString *text, NSStringEncoding encoding) { return text; }
                                                   textForSaving:^NSString *(NSString *text, NSStringEncoding encoding) { return text; }];
}

static id Identity(NSString *relative)
{
    id identifier = nil;
    [[NSURL fileURLWithPath:PathOf(relative)] getResourceValue:&identifier forKey:NSURLFileResourceIdentifierKey error:NULL];
    return identifier;
}

/// The environment of TeXShop, with the documents above: their texts are taken when the files are collected.
static TSTeXRootSearchEnvironment *Environment(void)
{
    TSTeXRootSearchEnvironment *environment = [TSTeXRootSearchEnvironment new];
    environment.codec = Codec();
    environment.collectorForRoot = ^TSTeXRootProjectCollector *(NSURL *rootURL) {
        if (OnCollect)
            OnCollect();
        TSTeXRootProjectCollector *collector = [[TSTeXRootProjectCollector alloc] initWithRootURL:rootURL codec:Codec() allowsSourceDoc:NO jobNameToken:@"\\jobname"];
        NSMutableDictionary *texts = [NSMutableDictionary dictionary];
        for (NSString *relative in Documents)
            texts[Identity(relative)] = [Documents[relative].view.string copy];
        collector.openDocumentTexts = texts;
        [Collectors addObject:collector];
        return collector;
    };
    environment.prepareCollector = ^(TSTeXRootProjectCollector *collector) {
        if (PrepareDelay)
            usleep(PrepareDelay);
    };
    environment.sourcesForFiles = ^NSArray<TSTeXRootSearchSource *> *(NSArray<TSTeXRootProjectFile *> *files) {
        NSMutableArray *sources = [NSMutableArray array];
        for (TSTeXRootProjectFile *file in files) {
            TestDocument *document = Documents[file.relativePath];
            [sources addObject:document ? [[TSTeXRootSearchSource alloc] initWithFile:file openDocumentText:[document.view.string copy] lineEnding:@"\n"
                                                                     searchOnlyReason:document.view.isEditable ? TSTeXRootSearchOnlyReasonNone : TSTeXRootSearchOnlyReasonNotEditable]
                                        : [[TSTeXRootSearchSource alloc] initWithFile:file]];
        }
        return sources;
    };
    environment.performAfterDelay = ^(NSTimeInterval delay, dispatch_block_t block) { dispatch_async(dispatch_get_main_queue(), block); };
    return environment;
}

/// The root, three files on the disk with matches, one open document with two, a file without one.
static void MakeProject(void)
{
    if (Folder) {
        [NSFileManager.defaultManager setAttributes:@{NSFilePosixPermissions: @0755} ofItemAtPath:PathOf(@"TeXShop Backups") error:NULL];
        [NSFileManager.defaultManager removeItemAtPath:Folder error:NULL];
    }
    Folder = [[NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString] stringByResolvingSymlinksInPath];
    Documents = [NSMutableDictionary dictionary];
    NSString *head = @"% !TEX root = ../thesis.tex\n";
    Write(@"thesis.tex", @"\\documentclass{book}\n% eq:main\n\\input{chapters/one}\n");
    Write(@"chapters/one.tex", [head stringByAppendingString:@"\\label{eq:main}\nsee \\eqref{eq:main}\n"]);
    Write(@"chapters/two.tex", [head stringByAppendingString:@"By \\eqref{eq:main} and eq:main again,\n"]);
    Write(@"chapters/three.tex", [head stringByAppendingString:@"nothing here\n"]);
    Write(@"auxiliary/conventions.tex", [head stringByAppendingString:@"see \\eqref{eq:main}.\n"]);
    Open(@"chapters/two.tex");
}

static TSAdvancedFindController *MakeController(void)
{
    TSAdvancedFindSettings *settings = [[TSAdvancedFindSettings alloc] initWithDefaults:[TSMemoryDefaults new] findPasteboard:[NSPasteboard pasteboardWithUniqueName]];
    return [[TSAdvancedFindController alloc] initWithSettings:settings];
}

#pragma mark The window

/// The sheets shown, and how the next ones are answered (by default: Replace in the confirmation, OK otherwise).
static NSMutableArray<NSAlert *> *Alerts;
static NSModalResponse (^Answer)(NSAlert *alert);
static NSMutableArray<NSString *> *OpenedTexts;

static TSTeXRootSearchWindowController *OpenWindow(BOOL backups)
{
    TSAdvancedFindController *controller = MakeController();
    controller.settings.findString = @"eq:main";
    controller.settings.replaceString = @"eq:central";
    controller.settings.options = 0;
    NSURL *libraryDirectory = [NSURL fileURLWithPath:PathOf(@".sets") isDirectory:YES];
    TSTeXRootSearchWindowController *window = [[TSTeXRootSearchWindowController alloc] initWithFindController:controller
                                                                                                       library:[[TSMultipleReplaceLibrary alloc] initWithDirectory:libraryDirectory]];
    window.replaceAllHandler = ^(TSTeXRootSearchWindowController *c) { [c beginReplaceAll]; };
    window.textViewForFile = ^NSTextView *(TSTeXRootReplaceFile *file) { return Documents[file.file.relativePath].view; };
    window.openTextHandler = ^(NSString *text) { [OpenedTexts addObject:text]; };
    // As a sheet: answered in a later turn of the run loop.
    window.alertPresenter = ^(NSAlert *alert, void (^answer)(NSModalResponse)) {
        [Alerts addObject:alert];
        NSModalResponse response = Answer ? Answer(alert) : (alert.buttons.count > 1 && alert.buttons[1].hasDestructiveAction ? NSAlertSecondButtonReturn : NSAlertFirstButtonReturn);
        dispatch_async(dispatch_get_main_queue(), ^{ answer(response); });
    };
    [window openForRootURL:[NSURL fileURLWithPath:PathOf(@"thesis.tex")] environment:Environment() mode:TSTeXRootSearchModeReplace setName:nil];
    window.backupBox.state = backups ? NSControlStateValueOn : NSControlStateValueOff;
    TSTeXRootSearchModel *model = window.model;
    Spin(^BOOL { return model.activity == TSTeXRootSearchActivityIdle && model.project && model.resultGeneration == model.generation && model.canReplaceAll; }, 30);
    return window;
}

static BOOL Idle(TSTeXRootSearchWindowController *window)
{
    TSTeXRootSearchModel *model = window.model;
    return !window.replacing && model.activity == TSTeXRootSearchActivityIdle && model.resultGeneration == model.generation;
}

static TSTeXRootSearchFileResult *ResultOf(TSTeXRootSearchModel *model, NSString *relative)
{
    for (TSTeXRootSearchFileResult *file in model.results)
        if ([file.source.file.relativePath isEqualToString:relative])
            return file;
    return nil;
}

static NSString *Replaced(NSString *text) { return [text stringByReplacingOccurrencesOfString:@"eq:main" withString:@"eq:central"]; }

#pragma mark Replace All

static void TestReplaceAll(void)
{
    MakeProject();
    Alerts = [NSMutableArray array];
    TSTeXRootSearchWindowController *window = OpenWindow(YES);
    TSTeXRootSearchModel *model = window.model;
    Check(model.numberOfItems == 6 && window.replaceAllButton.enabled, [NSString stringWithFormat:@"listed: %lu matches", (unsigned long)model.numberOfItems]);
    // One match off: "eq:main again" in the open document.
    TSTeXRootSearchFileResult *two = ResultOf(model, @"chapters/two.tex");
    [model setItems:@[two.items[1]] inFile:two included:NO];
    Spin(^BOOL { return model.canReplaceAll; }, 5);
    NSString *one = Read(@"chapters/one.tex"), *thesis = Read(@"thesis.tex"), *conventions = Read(@"auxiliary/conventions.tex");
    NSString *twoText = [Documents[@"chapters/two.tex"].view.string copy];

    // Cancel: nothing.
    Answer = ^NSModalResponse(NSAlert *alert) { return NSAlertFirstButtonReturn; };
    [window replaceAll:nil];
    Spin(^BOOL { return Alerts.count == 1 && Idle(window); }, 30);
    NSAlert *confirm = Alerts.firstObject;
    Check([confirm.messageText isEqualToString:@"Replace 5 matches in 4 files?"]
          && [confirm.informativeText isEqualToString:@"3 files that are not open will be changed on the disk. You can’t undo this action."],
          [NSString stringWithFormat:@"the confirmation: %@ / %@", confirm.messageText, confirm.informativeText]);
    Check([confirm.buttons[0].keyEquivalent isEqualToString:@"\r"] && confirm.buttons[1].keyEquivalent.length == 0 && confirm.buttons[1].hasDestructiveAction
          && [confirm.buttons[0].title isEqualToString:@"Cancel"] && [confirm.buttons[1].title isEqualToString:@"Replace"],
          @"Cancel is the default button, Replace is destructive and has no key");
    Check([Read(@"chapters/one.tex") isEqualToString:one] && [Documents[@"chapters/two.tex"].view.string isEqualToString:twoText] && !window.replacing
          && ![NSFileManager.defaultManager fileExistsAtPath:PathOf(@"TeXShop Backups")], @"Cancel replaces nothing and saves no backup");

    // Replace.
    Answer = nil;
    [Alerts removeAllObjects];
    __block BOOL lockedMeanwhile = NO, guardedMeanwhile = NO, controlsOff = NO, closeRefused = NO;
    window.runMade = ^(TSTeXRootReplaceRun *run) {
        run.applierMade = ^(TSTeXRootDocumentApplier *applier) {
            applier.maximumReplacements = 1; // a part for each replacement
            applier.betweenParts = ^(TSTeXRootDocumentApplier *a) {
                NSTextView *view = Documents[@"chapters/two.tex"].view;
                lockedMeanwhile = !view.isEditable;
                guardedMeanwhile = [TSTeXRootReplaceGuard isApplyingToTextStorage:view.textStorage] && [TSTeXRootReplaceGuard locksTextStorage:view.textStorage]
                    && TSTeXRootReplaceGuard.isRunning;
                controlsOff = !window.findField.isEditable && !window.refreshButton.enabled && !window.replaceAllButton.enabled && !window.stopButton.hidden
                    && !window.fileTree.outlineView.enabled && !window.resultsList.tableView.enabled && !window.backupBox.enabled && !window.modeControl.enabled;
                closeRefused = ![(id<NSWindowDelegate>)window windowShouldClose:(NSWindow *)window.window];
            };
        };
    };
    [window replaceAll:nil];
    Spin(^BOOL { return Idle(window) && model.numberOfCollections >= 2; }, 60);
    window.runMade = nil;
    Check(Alerts.count == 1, [NSString stringWithFormat:@"only the confirmation is shown when every file was replaced in (%lu sheets)", (unsigned long)Alerts.count]);
    Check([Read(@"chapters/one.tex") isEqualToString:Replaced(one)] && [Read(@"thesis.tex") isEqualToString:Replaced(thesis)]
          && [Read(@"auxiliary/conventions.tex") isEqualToString:Replaced(conventions)], @"the files on the disk are replaced in");
    NSString *expected = [twoText stringByReplacingOccurrencesOfString:@"\\eqref{eq:main}" withString:@"\\eqref{eq:central}"];
    TestDocument *document = Documents[@"chapters/two.tex"];
    Check([document.view.string isEqualToString:expected], [@"the open document is replaced in, the match off left: " stringByAppendingString:document.view.string]);
    Check(lockedMeanwhile && guardedMeanwhile && controlsOff && closeRefused, [NSString stringWithFormat:@"meanwhile: read-only %d, guard %d, controls %d, close refused %d",
                                                                            lockedMeanwhile, guardedMeanwhile, controlsOff, closeRefused]);
    Check(document.view.isEditable && !TSTeXRootReplaceGuard.isRunning && ![TSTeXRootReplaceGuard locksTextStorage:document.view.textStorage]
          && window.findField.isEditable && window.refreshButton.enabled, @"afterwards the document is editable again and the window can be used");
    Check([model.eventMessage isEqualToString:@"Replaced 5 matches in 4 files"] && [window.statusField.stringValue isEqualToString:@"Replaced 5 matches in 4 files"],
          [NSString stringWithFormat:@"the status says what was done: %@", window.statusField.stringValue]);
    TSTeXRootSearchFileResult *twoAfter = ResultOf(model, @"chapters/two.tex");
    Check(model.numberOfItems == 1 && twoAfter.items.count == 1 && ![model isItemIncluded:twoAfter.items[0] inFile:twoAfter] && !model.canReplaceAll,
          @"searched again: the match that was off is the only one, and stays off");
    // The backup: every file as approved, the open document's text too.
    NSArray *folders = [NSFileManager.defaultManager contentsOfDirectoryAtPath:PathOf(@"TeXShop Backups") error:NULL];
    NSString *backup = [@"TeXShop Backups" stringByAppendingPathComponent:folders.firstObject ?: @""];
    Check(folders.count == 1 && [Read([backup stringByAppendingPathComponent:@"chapters/one.tex"]) isEqualToString:one]
          && [Read([backup stringByAppendingPathComponent:@"chapters/two.tex"]) isEqualToString:twoText]
          && [Read([backup stringByAppendingPathComponent:@"thesis.tex"]) isEqualToString:thesis], @"the backup has the files and the open text as approved");
    // One Undo takes the document's replacements back; Redo puts them in again.
    Check(document.undo.canUndo && [document.undo.undoActionName isEqualToString:@"Replace All"], @"one Undo, named Replace All");
    [document.undo undo];
    Check([document.view.string isEqualToString:twoText] && document.undo.canRedo, @"Undo takes the replacements back");
    [document.undo redo];
    Check([document.view.string isEqualToString:expected], @"Redo puts them in again");
}

#pragma mark Checks 1 and 2

static void TestChecks(void)
{
    // Check 1: a file changed after the list was made.
    MakeProject();
    Alerts = [NSMutableArray array];
    Answer = nil;
    TSTeXRootSearchWindowController *window = OpenWindow(NO);
    TSTeXRootSearchModel *model = window.model;
    NSUInteger collections = model.numberOfCollections;
    Write(@"chapters/three.tex", @"% !TEX root = ../thesis.tex\nnow eq:main here\n");
    NSString *one = Read(@"chapters/one.tex");
    [window replaceAll:nil];
    Spin(^BOOL { return Alerts.count >= 1 && Idle(window) && model.numberOfCollections > collections; }, 30);
    Check(Alerts.count == 1 && [Alerts[0].messageText isEqualToString:@"Nothing was replaced"]
          && [Alerts[0].informativeText isEqualToString:@"chapters/three.tex changed. The list was made again."] && [Read(@"chapters/one.tex") isEqualToString:one],
          [NSString stringWithFormat:@"check 1: a file without a match changed: %@ / %@", Alerts.firstObject.messageText, Alerts.firstObject.informativeText]);
    Spin(^BOOL { return Idle(window) && model.canReplaceAll; }, 30);
    Check(model.numberOfItems == 7, @"check 1: the list is made again, with the new match");

    // Check 1: a file added, and an open document edited.
    [Alerts removeAllObjects];
    Write(@"chapters/four.tex", @"% !TEX root = ../thesis.tex\nfour\n");
    NSTextStorage *storage = Documents[@"chapters/two.tex"].view.textStorage;
    [storage replaceCharactersInRange:NSMakeRange(storage.length, 0) withString:@"typed"];
    [window replaceAll:nil];
    Spin(^BOOL { return Alerts.count >= 1 && Idle(window); }, 30);
    Check(Alerts.count == 1 && [Alerts[0].informativeText isEqualToString:@"chapters/two.tex and chapters/four.tex changed. The list was made again."],
          [@"check 1: a file added and an open document edited: " stringByAppendingString:Alerts.firstObject.informativeText ?: @""]);

    // Check 2: a file changed while the confirmation is shown.
    Spin(^BOOL { return Idle(window) && model.canReplaceAll; }, 30);
    [Alerts removeAllObjects];
    one = Read(@"chapters/one.tex");
    NSString *thesis = Read(@"thesis.tex");
    Answer = ^NSModalResponse(NSAlert *alert) {
        if (alert.buttons.count > 1) {
            Write(@"auxiliary/conventions.tex", @"% !TEX root = ../thesis.tex\nchanged meanwhile\n");
            return NSAlertSecondButtonReturn;
        }
        return NSAlertFirstButtonReturn;
    };
    [window replaceAll:nil];
    Spin(^BOOL { return Alerts.count >= 2 && Idle(window); }, 30);
    Answer = nil;
    Check(Alerts.count == 2 && [Alerts[1].informativeText isEqualToString:@"auxiliary/conventions.tex changed. The list was made again."]
          && [Read(@"chapters/one.tex") isEqualToString:one] && [Read(@"thesis.tex") isEqualToString:thesis],
          [@"check 2: a change while the confirmation is shown: nothing is replaced: " stringByAppendingString:Alerts.lastObject.informativeText ?: @""]);

    // Stopped during check 1: nothing is shown.
    Spin(^BOOL { return Idle(window) && model.canReplaceAll; }, 30);
    [Alerts removeAllObjects];
    [window replaceAll:nil];
    Check(window.replacing && !window.stopButton.hidden, @"■ is shown while Replace All checks the files");
    [window cancelOperation:nil];
    Spin(^BOOL { return NO; }, 0.5);
    Check(!window.replacing && Alerts.count == 0 && [Read(@"chapters/one.tex") isEqualToString:one], @"Escape during check 1: no sheet, nothing replaced");
}

#pragma mark Failures and stops

static void TestFailures(void)
{
    // A file that cannot be written: nothing after it; the report.
    MakeProject();
    Alerts = [NSMutableArray array];
    Answer = nil;
    TSTeXRootSearchWindowController *window = OpenWindow(NO);
    TSTeXRootSearchModel *model = window.model;
    NSString *twoText = [Documents[@"chapters/two.tex"].view.string copy];
    window.runMade = ^(TSTeXRootReplaceRun *run) { run.writer.failsCopyingAttributes = YES; };
    [window replaceAll:nil];
    Spin(^BOOL { return Alerts.count >= 2 && Idle(window); }, 60);
    window.runMade = nil;
    NSAlert *report = Alerts.lastObject;
    Check(Alerts.count == 2 && [report.messageText isEqualToString:@"Nothing was replaced"]
          && [report.informativeText isEqualToString:@"Not replaced: thesis.tex (its permissions or other attributes could not be kept), auxiliary/conventions.tex (not reached), "
                                                    @"chapters/one.tex (not reached), and chapters/two.tex (not reached)"]
          && [Documents[@"chapters/two.tex"].view.string isEqualToString:twoText],
          [NSString stringWithFormat:@"a file that cannot be written: %@ / %@", report.messageText, report.informativeText]);

    // A backup that cannot be saved: nothing is replaced.
    Spin(^BOOL { return Idle(window) && model.canReplaceAll; }, 30);
    [Alerts removeAllObjects];
    window.backupBox.state = NSControlStateValueOn;
    [NSFileManager.defaultManager createDirectoryAtPath:PathOf(@"TeXShop Backups") withIntermediateDirectories:YES attributes:nil error:NULL];
    chmod(PathOf(@"TeXShop Backups").fileSystemRepresentation, 0555);
    NSString *one = Read(@"chapters/one.tex");
    [window replaceAll:nil];
    Spin(^BOOL { return Alerts.count >= 2 && Idle(window); }, 60);
    chmod(PathOf(@"TeXShop Backups").fileSystemRepresentation, 0755);
    Check(Alerts.count == 2 && [Alerts[1].messageText isEqualToString:@"The backup could not be saved"] && [Alerts[1].informativeText hasSuffix:@"Nothing was replaced."]
          && [Read(@"chapters/one.tex") isEqualToString:one], [@"a backup that cannot be saved: " stringByAppendingString:Alerts.lastObject.informativeText ?: @""]);

    // Stopped in the open document: what is in is taken back; the files on the disk stay replaced.
    window.backupBox.state = NSControlStateValueOff;
    Spin(^BOOL { return Idle(window) && model.canReplaceAll; }, 30);
    [Alerts removeAllObjects];
    window.runMade = ^(TSTeXRootReplaceRun *run) {
        run.applierMade = ^(TSTeXRootDocumentApplier *applier) {
            applier.maximumReplacements = 1;
            applier.betweenParts = ^(TSTeXRootDocumentApplier *a) { [window stop:nil]; };
        };
    };
    [window replaceAll:nil];
    Spin(^BOOL { return Alerts.count >= 2 && Idle(window); }, 60);
    window.runMade = nil;
    report = Alerts.lastObject;
    TestDocument *document = Documents[@"chapters/two.tex"];
    Check([document.view.string isEqualToString:twoText] && [Read(@"chapters/one.tex") isEqualToString:Replaced(one)]
          && [report.messageText isEqualToString:@"Some files could not be replaced in"] && [report.informativeText containsString:@"Not replaced: chapters/two.tex (stopped)"]
          && [report.informativeText hasPrefix:@"Replaced: "], [NSString stringWithFormat:@"stopped in the open document: %@ / %@", report.messageText, report.informativeText]);
    Check(!document.undo.canUndo && document.view.isEditable, @"stopped: no Undo left behind, the document editable again");

    // Something else changes the open document meanwhile: partly replaced, the original text can be opened.
    MakeProject();
    Alerts = [NSMutableArray array];
    OpenedTexts = [NSMutableArray array];
    window = OpenWindow(NO);
    model = window.model;
    document = Documents[@"chapters/two.tex"];
    twoText = [document.view.string copy];
    window.runMade = ^(TSTeXRootReplaceRun *run) {
        run.applierMade = ^(TSTeXRootDocumentApplier *applier) {
            applier.maximumReplacements = 1;
            applier.betweenParts = ^(TSTeXRootDocumentApplier *a) {
                [document.view.textStorage replaceCharactersInRange:NSMakeRange(0, 0) withString:@"Z"];
            };
        };
    };
    [window replaceAll:nil];
    Spin(^BOOL { return Alerts.count >= 2 && Idle(window); }, 60);
    window.runMade = nil;
    report = Alerts.lastObject;
    Check([report.informativeText containsString:@"Partly replaced: chapters/two.tex (its text was changed meanwhile)"] && report.buttons.count == 2
          && [report.buttons[1].title isEqualToString:@"Open the Original Text in a New Document"] && [document.view.string hasPrefix:@"Z"] && !document.undo.canUndo,
          [NSString stringWithFormat:@"changed meanwhile: %@", report.informativeText]);
    // The report's second button opens the text as approved.
    [Alerts removeAllObjects];
    Answer = ^NSModalResponse(NSAlert *alert) { return NSAlertSecondButtonReturn; }; // Replace, then the report's second button
    Spin(^BOOL { return Idle(window) && model.canReplaceAll; }, 30);
    window.runMade = ^(TSTeXRootReplaceRun *run) {
        run.applierMade = ^(TSTeXRootDocumentApplier *applier) {
            applier.maximumReplacements = 1;
            applier.betweenParts = ^(TSTeXRootDocumentApplier *a) { [document.view.textStorage replaceCharactersInRange:NSMakeRange(0, 0) withString:@"Y"]; };
        };
    };
    NSString *approved = [document.view.string copy];
    [window replaceAll:nil];
    Spin(^BOOL { return Alerts.count >= 2 && Idle(window); }, 60);
    window.runMade = nil;
    Answer = nil;
    Check(OpenedTexts.count == 1 && [OpenedTexts.firstObject isEqualToString:approved], @"\"Open the Original Text in a New Document\" opens the text as approved");
}

#pragma mark Codex 4b round 1

static void TestRoundOne(void)
{
    // F7: a document made read-only while the confirmation is shown is not replaced in, nor made editable.
    MakeProject();
    Alerts = [NSMutableArray array];
    TSTeXRootSearchWindowController *window = OpenWindow(NO);
    TSTeXRootSearchModel *model = window.model;
    TestDocument *two = Documents[@"chapters/two.tex"];
    NSString *twoText = [two.view.string copy];
    Answer = ^NSModalResponse(NSAlert *alert) {
        if (alert.buttons.count > 1 && alert.buttons[1].hasDestructiveAction) {
            two.view.editable = NO;
            return NSAlertSecondButtonReturn;
        }
        return NSAlertFirstButtonReturn;
    };
    [window replaceAll:nil];
    Spin(^BOOL { return Alerts.count >= 2 && Idle(window); }, 60);
    Answer = nil;
    Check([two.view.string isEqualToString:twoText] && !two.view.isEditable && [Alerts.lastObject.messageText isEqualToString:@"Some files could not be replaced in"]
          && [Alerts.lastObject.informativeText containsString:@"Not replaced: chapters/two.tex (the document could not be edited)"],
          [NSString stringWithFormat:@"made read-only meanwhile: not replaced in, still read-only (%@)", Alerts.lastObject.informativeText]);
    two.view.editable = YES;

    // F8: the document opened again while the confirmation is shown (another text storage with the same text, read-only
    // or editable), or during check 2 after the run locked the documents: the new one is not replaced in.
    for (NSUInteger variant = 0; variant < 3; variant++) {
        MakeProject();
        Alerts = [NSMutableArray array];
        window = OpenWindow(NO);
        NSString *approvedText = [Documents[@"chapters/two.tex"].view.string copy];
        __block TestDocument *reopened = nil, *closed = Documents[@"chapters/two.tex"];
        void (^reopen)(void) = ^{
            reopened = Open(@"chapters/two.tex");
            reopened.view.editable = variant == 1;
        };
        Answer = ^NSModalResponse(NSAlert *alert) {
            if (alert.buttons.count > 1 && alert.buttons[1].hasDestructiveAction) {
                if (variant < 2)
                    reopen();
                else
                    OnCollect = ^{ if (!reopened) { reopen(); reopened.view.editable = YES; } };
                return NSAlertSecondButtonReturn;
            }
            return NSAlertFirstButtonReturn;
        };
        [window replaceAll:nil];
        Spin(^BOOL { return Alerts.count >= 2 && Idle(window); }, 60);
        Answer = nil;
        OnCollect = nil;
        NSArray *names = @[@"opened again read-only", @"opened again editable", @"opened again during check 2"];
        BOOL editableAsBefore = reopened.view.isEditable == (variant != 0);
        Check(reopened && [reopened.view.string isEqualToString:approvedText] && editableAsBefore && [closed.view.string isEqualToString:approvedText]
              && [Alerts.lastObject.informativeText containsString:@"Not replaced: chapters/two.tex (the document was closed or edited)"]
              && [Read(@"chapters/one.tex") containsString:@"eq:central"],
              [NSString stringWithFormat:@"%@: the new text storage is not replaced in (%@)", names[variant], Alerts.lastObject.informativeText]);
    }

    // F3: every file replaced in, a backup in UTF-8: said in a sheet headed with what was done. F6: the bytes are
    // made off the main thread.
    MakeProject();
    Alerts = [NSMutableArray array];
    window = OpenWindow(YES);
    model = window.model;
    __block BOOL encodedOnMain = NO;
    window.backupEncoderForOpenDocument = ^NSData *(^(TSTeXRootReplaceFile *file))(BOOL *) {
        NSString *text = file.originalText;
        return ^NSData *(BOOL *usedUTF8) {
            encodedOnMain |= NSThread.isMainThread;
            *usedUTF8 = YES;
            return [text dataUsingEncoding:NSUTF8StringEncoding];
        };
    };
    [window replaceAll:nil];
    Spin(^BOOL { return Alerts.count >= 2 && Idle(window); }, 60);
    NSAlert *done = Alerts.lastObject;
    Check(Alerts.count == 2 && [done.messageText isEqualToString:@"Replaced 6 matches in 4 files"] && [done.informativeText containsString:@"Backed up in UTF-8: chapters/two.tex"]
          && ![done.informativeText containsString:@"Replaced:"] && done.buttons.count == 2 && [done.buttons[1].title isEqualToString:@"Show in Finder"],
          [NSString stringWithFormat:@"a backup in UTF-8 is told: %@ / %@", done.messageText, done.informativeText]);
    Check(!encodedOnMain, @"the open document's backup is made into bytes off the main thread");

    // F2: stopped while check 2 waits for a slow file system: it ends at once, the collection is cancelled.
    MakeProject();
    Alerts = [NSMutableArray array];
    Collectors = [NSMutableArray array];
    window = OpenWindow(NO);
    model = window.model;
    NSString *one = Read(@"chapters/one.tex");
    Answer = ^NSModalResponse(NSAlert *alert) {
        PrepareDelay = 2000000;
        return alert.buttons.count > 1 ? NSAlertSecondButtonReturn : NSAlertFirstButtonReturn;
    };
    [window replaceAll:nil];
    Spin(^BOOL { return window.run != nil; }, 30);
    Spin(^BOOL { return NO; }, 0.1);
    NSUInteger shown = Alerts.count;
    TSTeXRootProjectCollector *checking = Collectors.lastObject;
    [window stop:nil];
    CFAbsoluteTime stopped = CFAbsoluteTimeGetCurrent();
    Spin(^BOOL { return !window.replacing; }, 1);
    double waited = CFAbsoluteTimeGetCurrent() - stopped;
    Check(!window.replacing && !TSTeXRootReplaceGuard.isRunning && waited < 0.3 && checking.isCancelled && [Read(@"chapters/one.tex") isEqualToString:one]
          && Documents[@"chapters/two.tex"].view.isEditable, [NSString stringWithFormat:@"stopped during check 2: ended in %.0f ms, collection cancelled %d", waited * 1000, checking.isCancelled]);
    Answer = nil;
    PrepareDelay = 0;
    Spin(^BOOL { return NO; }, 2.5); // the slow preparation ends; its result is dropped
    Check([Read(@"chapters/one.tex") isEqualToString:one] && Alerts.count <= shown + 1, @"the late result of check 2 replaces nothing");
    // Check 1 the same.
    Spin(^BOOL { return Idle(window) && model.canReplaceAll; }, 30);
    PrepareDelay = 2000000;
    [window replaceAll:nil];
    Spin(^BOOL { return NO; }, 0.1);
    checking = Collectors.lastObject;
    [window stop:nil];
    Check(!window.replacing && checking.isCancelled, @"stopped during check 1: the collection is cancelled");
    PrepareDelay = 0;
    Spin(^BOOL { return NO; }, 2.5);

    // F1, F5: two open documents. What waits for the end (Quit) runs once the whole Replace All is over, never between
    // two documents; meanwhile the files of the root are not typeset, other files are.
    for (NSUInteger stopping = 0; stopping < 2; stopping++) {
        MakeProject();
        Open(@"auxiliary/conventions.tex");
        Alerts = [NSMutableArray array];
        window = OpenWindow(NO);
        __block NSUInteger waits = 0, firedBusy = 0, fired = 0;
        __block BOOL projectGuarded = NO, otherFree = NO;
        window.runMade = ^(TSTeXRootReplaceRun *run) {
            run.applierMade = ^(TSTeXRootDocumentApplier *applier) {
                applier.maximumReplacements = 1;
                applier.betweenParts = ^(TSTeXRootDocumentApplier *a) {
                    projectGuarded = [TSTeXRootReplaceGuard isApplyingInProjectOfURL:[NSURL fileURLWithPath:PathOf(@"thesis.tex")]];
                    otherFree = ![TSTeXRootReplaceGuard isApplyingInProjectOfURL:[NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:@"other.tex"]]];
                    if (waits++ == 0)
                        [TSTeXRootReplaceGuard performWhenNotApplying:^{
                            fired++;
                            if (TSTeXRootReplaceGuard.isApplying || TSTeXRootReplaceGuard.isRunning)
                                firedBusy++;
                        }];
                    if (stopping && waits == 3)
                        [window stop:nil];
                };
            };
        };
        [window replaceAll:nil];
        Spin(^BOOL { return Idle(window) && fired > 0; }, 60);
        window.runMade = nil;
        Check(fired == 1 && firedBusy == 0 && projectGuarded && otherFree && ![TSTeXRootReplaceGuard isApplyingInProjectOfURL:[NSURL fileURLWithPath:PathOf(@"thesis.tex")]],
              [NSString stringWithFormat:@"%@: the wait ends with the Replace All (fired %lu, while busy %lu), typesetting is refused for the root's files only",
               stopping ? @"stopped" : @"two documents", (unsigned long)fired, (unsigned long)firedBusy]);
    }
}

#pragma mark The main thread

static void TestMainThread(void)
{
    // A 10 MB open document with 100,000 matches, and a file on the disk with a 2 MB insertion (spec §2.9).
    MakeProject();
    NSMutableString *big = [NSMutableString stringWithString:@"% !TEX root = ../thesis.tex\n"];
    while (big.length < 10000000)
        [big appendString:@"Lorem ipsum eq:main dolor sit amet, consectetur adipiscing elit, sed do eiusmod tempor incididunt ut labore et dolore magna.\n"];
    Write(@"chapters/big.tex", big);
    Open(@"chapters/big.tex");
    Alerts = [NSMutableArray array];
    Answer = nil;
    TSTeXRootSearchWindowController *window = OpenWindow(YES);
    TSTeXRootSearchModel *model = window.model;
    model.maximumItems = 500000;
    model.maximumItemsPerFile = 200000;
    [model searchNow];
    Spin(^BOOL { return Idle(window) && model.canReplaceAll; }, 120);
    NSUInteger items = model.numberOfItems;
    NSTimeInterval replacing = LongestPause(^{ [window replaceAll:nil]; }, ^BOOL { return Idle(window) && model.numberOfCollections >= 2; });
    TestDocument *document = Documents[@"chapters/big.tex"];
    printf("main thread: Replace All of %lu matches, 10 MB open: longest pause %.0f ms\n", (unsigned long)items, replacing * 1000);
    Check(items > 70000 && replacing < 0.1 && ![document.view.string containsString:@"eq:main"], @"Replace All in a 10 MB open document keeps the main thread free");
    // Stopped half way: the parts are taken back, a part at a time too.
    [document.undo undo];
    [model collect];
    Spin(^BOOL { return Idle(window) && model.canReplaceAll; }, 120);
    NSUInteger shown = Alerts.count;
    NSString *before = [document.view.string copy];
    window.runMade = ^(TSTeXRootReplaceRun *run) {
        run.applierMade = ^(TSTeXRootDocumentApplier *applier) {
            applier.betweenParts = ^(TSTeXRootDocumentApplier *a) { if (a.numberOfParts == 20) [window stop:nil]; };
        };
    };
    NSTimeInterval stopping = LongestPause(^{ [window replaceAll:nil]; }, ^BOOL { return Idle(window) && Alerts.count >= shown + 2; });
    window.runMade = nil;
    printf("main thread: stopped and taken back: longest pause %.0f ms\n", stopping * 1000);
    Check(stopping < 0.1 && [document.view.string isEqualToString:before], @"stopping in a 10 MB document takes it back without holding the main thread");

    // A 2 MB insertion, in lines.
    MakeProject();
    Alerts = [NSMutableArray array];
    TestDocument *small = Documents[@"chapters/two.tex"];
    window = OpenWindow(NO);
    model = window.model;
    NSMutableString *insertion = [NSMutableString string];
    while (insertion.length < 2000000)
        [insertion appendString:@"a line of the inserted text, of about eighty characters, ending with a break\n"];
    model.replaceString = insertion;
    Spin(^BOOL { return Idle(window) && model.canReplaceAll; }, 120);
    __block NSUInteger parts = 0;
    window.runMade = ^(TSTeXRootReplaceRun *run) {
        run.applierMade = ^(TSTeXRootDocumentApplier *applier) {
            applier.betweenParts = ^(TSTeXRootDocumentApplier *a) { parts = a.numberOfParts; };
        };
    };
    NSTimeInterval inserting = LongestPause(^{ [window replaceAll:nil]; }, ^BOOL { return Idle(window) && model.numberOfCollections >= 2; });
    window.runMade = nil;
    printf("main thread: 2 MB inserted twice in an open document: longest pause %.0f ms, %lu parts\n", inserting * 1000, (unsigned long)parts);
    // Each 2 MB string goes in by pieces of at most 50,000 characters (spec §2.9).
    Check(inserting < 0.1 && small.view.string.length > 4000000 && parts >= 80, @"a 2 MB insertion goes in by pieces and keeps the main thread free");
}

#pragma mark Languages

static void TestLanguage(void)
{
    NSArray<NSString *> *keys = @[@"TeXRootSearch.Confirm.Title", @"TeXRootSearch.Confirm.Disk", @"TeXRootSearch.Changed.Title", @"TeXRootSearch.Changed.Text",
        @"TeXRootSearch.BackupFailed.Title", @"TeXRootSearch.BackupFailed.Text", @"TeXRootSearch.Report.SomeTitle", @"TeXRootSearch.Report.Replaced",
        @"TeXRootSearch.Report.NotReplaced", @"TeXRootSearch.Report.Partly", @"TeXRootSearch.Report.Backup", @"TeXRootSearch.Report.BackupUTF8",
        @"TeXRootSearch.Report.FileReason", @"TeXRootSearch.Outcome.Stopped", @"TeXRootSearch.Outcome.NotReached", @"TeXRootSearch.Outcome.DocumentChanged",
        @"TeXRootSearch.Outcome.Refused", @"TeXRootSearch.Outcome.UnexpectedChange", @"TeXRootSearch.Outcome.FileChanged", @"TeXRootSearch.Outcome.Attributes",
        @"TeXRootSearch.Outcome.Verification", @"TeXRootSearch.Outcome.Write", @"TeXRootSearch.Outcome.Unencodable", @"TeXRootSearch.ShowInFinder",
        @"TeXRootSearch.OpenOriginal", @"TeXRootSearch.Confirm.Replace", @"TeXRootSearch.Outcome.NotEditable", @"TeXRootSearch.Status.Replacing", @"TeXRootSearch.Status.Replaced", @"TeXRootSearch.ScriptRefused"];
    for (NSString *key in keys)
        Check(![TSAdvancedFindLocalized(key, @"\u2400") isEqualToString:@"\u2400"], [@"missing: " stringByAppendingString:key]);
    // Every count: the numbers are in, with no format left.
    for (NSNumber *n in @[@1, @2, @5, @21, @100]) {
        unsigned long count = n.unsignedLongValue;
        NSString *title = [NSString localizedStringWithFormat:TSAdvancedFindLocalized(@"TeXRootSearch.Confirm.Title", @""), count, count];
        NSString *disk = [NSString localizedStringWithFormat:TSAdvancedFindLocalized(@"TeXRootSearch.Confirm.Disk", @""), count];
        NSString *done = [NSString localizedStringWithFormat:TSAdvancedFindLocalized(@"TeXRootSearch.Status.Replaced", @""), count, count];
        for (NSString *text in @[title, disk, done])
            Check(![text containsString:@"%"] && [text containsString:n.stringValue] && text.length > 4, [NSString stringWithFormat:@"%@ with %lu", text, count]);
    }
    // The confirmation's button as the sheet shows it: in Japanese 「置換」 (decision 29), not the panel's 「置き換え」.
    MakeProject();
    Alerts = [NSMutableArray array];
    Answer = ^NSModalResponse(NSAlert *alert) { return NSAlertFirstButtonReturn; };
    TSTeXRootSearchWindowController *window = OpenWindow(NO);
    [window replaceAll:nil];
    Spin(^BOOL { return Alerts.count >= 1 && Idle(window); }, 30);
    Answer = nil;
    NSString *language = NSBundle.mainBundle.preferredLocalizations.firstObject;
    Check(Alerts.firstObject.buttons.count == 2 && [Alerts.firstObject.buttons[1].title isEqualToString:TSAdvancedFindLocalized(@"TeXRootSearch.Confirm.Replace", @"")]
          && (![language isEqualToString:@"ja"] || [Alerts.firstObject.buttons[1].title isEqualToString:@"置換"]), [@"the confirmation's button: " stringByAppendingString:Alerts.firstObject.buttons.lastObject.title ?: @""]);
    if ([language isEqualToString:@"en"]) {
        Check([[NSString localizedStringWithFormat:TSAdvancedFindLocalized(@"TeXRootSearch.Confirm.Title", @""), 1UL, 1UL] isEqualToString:@"Replace 1 match in 1 file?"]
              && [[NSString localizedStringWithFormat:TSAdvancedFindLocalized(@"TeXRootSearch.Confirm.Disk", @""), 1UL] hasPrefix:@"1 file that is not open will be changed"]
              && [[NSString localizedStringWithFormat:TSAdvancedFindLocalized(@"TeXRootSearch.Status.Replaced", @""), 2UL, 1UL] isEqualToString:@"Replaced 2 matches in 1 file"],
              @"English singular and plural");
    }
}

int main(int argc, const char *argv[])
{
    @autoreleasepool {
        TSInstallAppKitIsolation();
        [NSApplication sharedApplication];
        Collectors = [NSMutableArray array];
        NSString *mode = argc > 1 ? @(argv[1]) : @"behavior";
        if ([mode isEqualToString:@"behavior"]) {
            TestReplaceAll();
            TestChecks();
            TestFailures();
            TestRoundOne();
        } else if ([mode isEqualToString:@"main-thread"]) {
            TestMainThread();
        } else if ([mode isEqualToString:@"language"]) {
            TestLanguage();
        }
        if (Folder) {
            [NSFileManager.defaultManager setAttributes:@{NSFilePosixPermissions: @0755} ofItemAtPath:PathOf(@"TeXShop Backups") error:NULL];
            [NSFileManager.defaultManager removeItemAtPath:Folder error:NULL];
        }
        if (failures)
            return 1;
        printf("PASS %s (%s)\n", mode.UTF8String, (NSBundle.mainBundle.preferredLocalizations.firstObject ?: @"en").UTF8String);
    }
    return 0;
}
