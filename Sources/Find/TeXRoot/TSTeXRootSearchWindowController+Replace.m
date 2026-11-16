// SPDX-License-Identifier: GPL-2.0-or-later
// Replace All of the window "Find in TeX Sources" (spec §2.5): check 1 and the confirmation sheet, the run, and the
// report.
#import "TSTeXRootSearchWindowController+Private.h"

#define TSLocalized TSAdvancedFindLocalized

/// What Replace All was approved with, kept until its report.
@interface TSTeXRootApproval : NSObject
@property (nonatomic, strong) TSTeXRootSearchModel *model;
@property (nonatomic, strong) TSTeXRootProject *listed;
@property (nonatomic, copy) NSArray<TSTeXRootSearchFileResult *> *results;
@property (nonatomic, copy) BOOL (^isItemIncluded)(TSTeXRootSearchItem *item, TSTeXRootSearchFileResult *file);
/// The identities of the files on in the tree.
@property (nonatomic, copy) NSSet *filesOn;
@property (nonatomic, strong, nullable) TSTeXRootReplacePlan *plan;
@property (nonatomic) NSUInteger request;
@end

@implementation TSTeXRootApproval
@end

/// Moves on when Replace All is pressed or stopped: a check that comes back for an older press is dropped.
static NSUInteger TSReplaceRequest;

@implementation TSTeXRootSearchWindowController (ReplaceAll)

#pragma mark Sheets

- (void)presentAlert:(NSAlert *)alert answer:(nullable void (^)(NSModalResponse response))answer
{
    void (^handler)(NSModalResponse) = answer ?: ^(NSModalResponse response) {};
    if (self.alertPresenter) {
        self.alertPresenter(alert, handler);
        return;
    }
    [alert beginSheetModalForWindow:(NSWindow *_Nonnull)self.window completionHandler:handler];
}

/// The names of files, as a list in the user's language ("a.tex, b.tex and c.tex").
- (NSString *)listOfPaths:(NSArray<NSString *> *)paths
{
    return [NSListFormatter localizedStringByJoiningStrings:paths] ?: @"";
}

/// A long text goes in a scroll view under the message, so that the sheet keeps a size that fits the window.
- (void)setText:(NSString *)text ofAlert:(NSAlert *)alert
{
    NSUInteger lines = [text componentsSeparatedByString:@"\n"].count;
    if (text.length < 600 && lines <= 8) {
        alert.informativeText = text;
        return;
    }
    NSScrollView *scroll = [[NSScrollView alloc] initWithFrame:NSMakeRect(0, 0, 360, 180)];
    scroll.hasVerticalScroller = YES;
    scroll.borderType = NSBezelBorder;
    NSTextView *view = [[NSTextView alloc] initWithFrame:scroll.bounds];
    view.editable = NO;
    view.string = text;
    view.font = [NSFont systemFontOfSize:NSFont.smallSystemFontSize];
    view.textContainerInset = NSMakeSize(4, 4);
    view.autoresizingMask = NSViewWidthSizable;
    scroll.documentView = view;
    alert.accessoryView = scroll;
}

#pragma mark Replace All

- (void)beginReplaceAll
{
    TSTeXRootSearchModel *model = self.model;
    TSTeXRootSourceCodec *codec = model.environment.codec;
    if (!model || !model.canReplaceAll || self.replacing || TSTeXRootReplaceGuard.isRunning || !model.project || !codec) {
        NSBeep();
        return;
    }
    TSTeXRootApproval *approval = [TSTeXRootApproval new];
    approval.model = model;
    approval.listed = (TSTeXRootProject *_Nonnull)model.project;
    approval.results = model.results;
    approval.isItemIncluded = [model inclusionSnapshot];
    NSMutableSet *filesOn = [NSMutableSet set];
    for (TSTeXRootProjectFile *file in approval.listed.files)
        if ([model isFileIncluded:file])
            [filesOn addObject:file.identifier];
    approval.filesOn = filesOn;
    approval.request = ++TSReplaceRequest;
    self.replacing = YES;
    [self updateFromModel];

    // Check 1 (spec §2.5.1): the files collected again and compared with the list, and the plan made from the list,
    // on a background queue.
    TSTeXRootSearchEnvironment *environment = model.environment;
    TSTeXRootProjectCollector *collector = environment.collectorForRoot(model.rootURL);
    void (^prepare)(TSTeXRootProjectCollector *) = environment.prepareCollector;
    self.checkCollector = collector;
    __weak typeof(self) weakSelf = self;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        if (prepare)
            prepare(collector);
        TSTeXRootProject *now = [collector collect];
        NSError *error = nil;
        TSTeXRootReplacePlan *plan = [TSTeXRootReplacePlan planWithResults:approval.results isIncluded:approval.isItemIncluded codec:codec error:&error];
        NSArray<NSString *> *changed = now ? TSTeXRootChangedFiles(approval.listed, (TSTeXRootProject *_Nonnull)now, ^BOOL(TSTeXRootProjectFile *file) {
            return [filesOn containsObject:file.identifier];
        }) : @[approval.listed.rootURL.lastPathComponent ?: @""];
        dispatch_async(dispatch_get_main_queue(), ^{
            typeof(self) controller = weakSelf;
            if (!controller || approval.request != TSReplaceRequest || controller.model != model)
                return; // stopped meanwhile (and already ended), or the window was tied to another root
            controller.checkCollector = nil;
            approval.plan = plan;
            if (changed.count) {
                [controller showChangedFiles:changed];
                return;
            }
            if (!plan) {
                [controller endReplacingWithFailure:error];
                return;
            }
            [controller confirmApproval:approval codec:(TSTeXRootSourceCodec *_Nonnull)codec];
        });
    });
}

/// Nothing was replaced: the files changed since the list was made, which is made again (spec §2.7.4, decision 34).
- (void)showChangedFiles:(NSArray<NSString *> *)paths
{
    self.replacing = NO;
    [self.model collect];
    [self updateFromModel];
    NSAlert *alert = [NSAlert new];
    alert.alertStyle = NSAlertStyleWarning;
    alert.messageText = TSLocalized(@"TeXRootSearch.Changed.Title", @"Nothing was replaced");
    [self setText:[NSString stringWithFormat:TSLocalized(@"TeXRootSearch.Changed.Text", @"%@ changed. The list was made again."), [self listOfPaths:paths]] ofAlert:alert];
    [alert addButtonWithTitle:NSLocalizedString(@"OK", @"OK")];
    [self presentAlert:alert answer:nil];
}

- (void)endReplacingWithFailure:(nullable NSError *)error
{
    self.replacing = NO;
    [self updateFromModel];
    NSAlert *alert = [NSAlert new];
    alert.alertStyle = NSAlertStyleWarning;
    alert.messageText = TSLocalized(@"TeXRootSearch.Changed.Title", @"Nothing was replaced");
    NSURL *url = error.userInfo[NSURLErrorKey];
    NSString *reason = [self reasonOfError:error];
    alert.informativeText = url ? [NSString stringWithFormat:TSLocalized(@"TeXRootSearch.Report.FileReason", @"%1$@ (%2$@)"), [self pathOfURL:url], reason] : reason;
    [alert addButtonWithTitle:NSLocalizedString(@"OK", @"OK")];
    [self presentAlert:alert answer:nil];
}

/// The confirmation sheet (decision 29): Cancel is the default button; Replace is marked as destructive.
- (void)confirmApproval:(TSTeXRootApproval *)approval codec:(TSTeXRootSourceCodec *)codec
{
    TSTeXRootReplacePlan *plan = (TSTeXRootReplacePlan *_Nonnull)approval.plan;
    NSAlert *alert = [NSAlert new];
    alert.alertStyle = NSAlertStyleWarning;
    alert.messageText = [NSString localizedStringWithFormat:TSLocalized(@"TeXRootSearch.Confirm.Title", @"Replace %1$lu matches in %2$lu files?"),
                         (unsigned long)plan.numberOfItems, (unsigned long)plan.files.count];
    NSMutableArray<NSString *> *lines = [NSMutableArray array];
    // Only when files are written on the disk: replacements in open documents can be undone.
    if (plan.numberOfFilesOnDisk > 0)
        [lines addObject:[NSString localizedStringWithFormat:TSLocalized(@"TeXRootSearch.Confirm.Disk",
            @"%lu files that are not open will be changed on the disk. You can’t undo this action."), (unsigned long)plan.numberOfFilesOnDisk]];
    NSUInteger unreadable = approval.listed.unreadableItems.count;
    if (unreadable > 0)
        [lines addObject:[NSString stringWithFormat:TSLocalized(@"TeXRootSearch.UnreadableButton", @"Files not read: %lu"), (unsigned long)unreadable]];
    alert.informativeText = [lines componentsJoinedByString:@"\n"];
    NSButton *cancel = [alert addButtonWithTitle:TSLocalized(@"AdvancedFind.Cancel", @"Cancel")];
    cancel.keyEquivalent = @"\r";
    NSButton *replace = [alert addButtonWithTitle:TSLocalized(@"TeXRootSearch.Confirm.Replace", @"Replace")];
    replace.keyEquivalent = @"";
    replace.hasDestructiveAction = YES;
    __weak typeof(self) weakSelf = self;
    [self presentAlert:alert answer:^(NSModalResponse response) {
        typeof(self) controller = weakSelf;
        if (!controller)
            return;
        if (response != NSAlertSecondButtonReturn || approval.request != TSReplaceRequest || controller.model != approval.model) {
            controller.replacing = NO;
            [controller updateFromModel];
            return;
        }
        [controller runApproval:approval codec:codec];
    }];
}

#pragma mark The run

- (void)runApproval:(TSTeXRootApproval *)approval codec:(TSTeXRootSourceCodec *)codec
{
    TSTeXRootSearchModel *model = approval.model;
    TSTeXRootReplaceRun *run = [[TSTeXRootReplaceRun alloc] initWithPlan:(TSTeXRootReplacePlan *_Nonnull)approval.plan listedProject:approval.listed codec:codec];
    if (self.backupBox.state == NSControlStateValueOn)
        run.backupFolder = approval.listed.folderURL;
    TSTeXRootSearchEnvironment *environment = model.environment;
    NSURL *rootURL = model.rootURL;
    run.makeCollector = ^TSTeXRootProjectCollector *_Nullable { return environment.collectorForRoot(rootURL); };
    run.prepareCollector = environment.prepareCollector;
    NSSet *filesOn = approval.filesOn;
    run.isIncluded = ^BOOL(TSTeXRootProjectFile *file) { return [filesOn containsObject:file.identifier]; };
    if (self.textViewForFile)
        run.textViewForFile = (NSTextView *_Nullable (^_Nonnull)(TSTeXRootReplaceFile *))self.textViewForFile;
    if (self.backupEncoderForOpenDocument)
        run.backupEncoderForOpenDocument = (NSData *_Nullable (^_Nonnull (^_Nonnull)(TSTeXRootReplaceFile *))(BOOL *))self.backupEncoderForOpenDocument;
    run.actionName = TSLocalized(@"AdvancedFind.ReplaceAllAction", @"Replace All");
    self.run = run;
    if (self.runMade)
        self.runMade(run);
    [self updateFromModel];
    __weak typeof(self) weakSelf = self;
    [run runWithCompletion:^(TSTeXRootReplaceReport *report) {
        [weakSelf finishApproval:approval report:report];
    }];
}

- (void)finishApproval:(TSTeXRootApproval *)approval report:(TSTeXRootReplaceReport *)report
{
    self.run = nil;
    if (report.changedFiles.count) {
        [self showChangedFiles:report.changedFiles];
        return;
    }
    if (report.backupError) {
        self.replacing = NO;
        [self updateFromModel];
        NSAlert *alert = [NSAlert new];
        alert.alertStyle = NSAlertStyleWarning;
        alert.messageText = TSLocalized(@"TeXRootSearch.BackupFailed.Title", @"The backup could not be saved");
        NSError *error = (NSError *_Nonnull)report.backupError;
        NSURL *url = error.userInfo[NSURLErrorKey];
        NSString *reason = [self reasonOfError:error];
        NSString *what = url ? [NSString stringWithFormat:TSLocalized(@"TeXRootSearch.Report.FileReason", @"%1$@ (%2$@)"), [self pathOfURL:url], reason] : reason;
        alert.informativeText = [NSString stringWithFormat:TSLocalized(@"TeXRootSearch.BackupFailed.Text", @"%@. Nothing was replaced."), what];
        [alert addButtonWithTitle:NSLocalizedString(@"OK", @"OK")];
        [self presentAlert:alert answer:nil];
        return;
    }
    // Where the items that were off are in the files replaced in (spec §2.6), worked out on a background queue.
    NSMutableDictionary<NSString *, TSTeXRootSearchFileResult *> *resultByPath = [NSMutableDictionary dictionary];
    for (TSTeXRootSearchFileResult *result in approval.results)
        resultByPath[result.source.file.relativePath] = result;
    NSArray<TSTeXRootReplaceRecord *> *records = report.records;
    BOOL (^included)(TSTeXRootSearchItem *, TSTeXRootSearchFileResult *) = approval.isItemIncluded;
    __weak typeof(self) weakSelf = self;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSMutableDictionary<NSString *, NSArray<NSValue *> *> *rangesOff = [NSMutableDictionary dictionary];
        for (TSTeXRootReplaceRecord *record in records) {
            if (record.status != TSTeXRootReplaceStatusApplied)
                continue;
            NSString *path = record.file.file.relativePath;
            TSTeXRootSearchFileResult *result = resultByPath[path];
            NSMutableArray<NSValue *> *off = [NSMutableArray array];
            for (TSTeXRootSearchItem *item in result.items)
                if (!included(item, result))
                    [off addObject:[NSValue valueWithRange:item.range]];
            rangesOff[path] = [TSTeXRootReplaceMapping ranges:off afterReplacements:record.file.replacements];
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            typeof(self) controller = weakSelf;
            if (!controller)
                return;
            controller.replacing = NO;
            NSString *message = nil;
            if (report.numberOfAppliedFiles > 0)
                message = [NSString localizedStringWithFormat:TSLocalized(@"TeXRootSearch.Status.Replaced", @"Replaced %1$lu matches in %2$lu files"),
                           (unsigned long)report.numberOfAppliedItems, (unsigned long)report.numberOfAppliedFiles];
            else if (report.stopped)
                message = TSLocalized(@"TeXRootSearch.Status.Stopped", @"Stopped");
            if (controller.model == approval.model)
                [approval.model searchAgainAfterReplacingWithRangesOff:rangesOff message:message];
            [controller updateFromModel];
            // Every file replaced in: a sheet only when a backup had to be saved in UTF-8 (spec §2.5.5), headed with
            // what was done.
            if (!report.allApplied || report.backupNotes.count)
                [controller showReport:report title:report.allApplied ? message : nil];
        });
    });
}

#pragma mark The report

- (NSString *)pathOfURL:(NSURL *)url
{
    NSString *folder = self.model.project.folderURL.path;
    NSString *path = url.path ?: @"";
    if (folder.length && [path hasPrefix:[folder stringByAppendingString:@"/"]])
        return [path substringFromIndex:folder.length + 1];
    return url.lastPathComponent ?: path;
}

- (NSString *)reasonOfError:(nullable NSError *)error
{
    if ([error.domain isEqualToString:TSTeXRootReplaceErrorDomain]) {
        switch ((TSTeXRootReplaceError)error.code) {
            case TSTeXRootReplaceErrorChanged:
                return TSLocalized(@"TeXRootSearch.Outcome.FileChanged", @"the file had changed");
            case TSTeXRootReplaceErrorUnencodable:
                return TSLocalized(@"TeXRootSearch.Outcome.Unencodable", @"the file’s encoding cannot hold the text replaced");
            case TSTeXRootReplaceErrorAttributes:
                return TSLocalized(@"TeXRootSearch.Outcome.Attributes", @"its permissions or other attributes could not be kept");
            case TSTeXRootReplaceErrorVerification:
                return TSLocalized(@"TeXRootSearch.Outcome.Verification", @"what was written does not read back as meant");
            case TSTeXRootReplaceErrorStopped:
                return TSLocalized(@"TeXRootSearch.Outcome.Stopped", @"stopped");
            case TSTeXRootReplaceErrorBackup:
            case TSTeXRootReplaceErrorWrite:
                break;
        }
        NSError *underlying = error.userInfo[NSUnderlyingErrorKey];
        if (underlying.localizedDescription.length)
            return underlying.localizedDescription;
        return TSLocalized(@"TeXRootSearch.Outcome.Write", @"it could not be written");
    }
    return error.localizedDescription ?: @"";
}

- (NSString *)reasonOfRecord:(TSTeXRootReplaceRecord *)record
{
    switch (record.reason) {
        case TSTeXRootReplaceReasonStopped:
            return TSLocalized(@"TeXRootSearch.Outcome.Stopped", @"stopped");
        case TSTeXRootReplaceReasonAfterFailure:
            return TSLocalized(@"TeXRootSearch.Outcome.NotReached", @"not reached");
        case TSTeXRootReplaceReasonChanged:
            return TSLocalized(@"TeXRootSearch.Outcome.DocumentChanged", @"the document was closed or edited");
        case TSTeXRootReplaceReasonNotEditable:
            return TSLocalized(@"TeXRootSearch.Outcome.NotEditable", @"the document could not be edited");
        case TSTeXRootReplaceReasonRefused:
            return TSLocalized(@"TeXRootSearch.Outcome.Refused", @"the document did not accept the change");
        case TSTeXRootReplaceReasonUnexpectedChange:
            return TSLocalized(@"TeXRootSearch.Outcome.UnexpectedChange", @"its text was changed meanwhile");
        case TSTeXRootReplaceReasonError:
            return [self reasonOfError:record.error];
        case TSTeXRootReplaceReasonNone:
            break;
    }
    return @"";
}

/// What was replaced and what was not (spec §2.5.5), with the backup's folder.
- (void)showReport:(TSTeXRootReplaceReport *)report title:(nullable NSString *)title
{
    NSMutableArray<NSString *> *replaced = [NSMutableArray array], *notReplaced = [NSMutableArray array], *partly = [NSMutableArray array];
    NSMutableArray<TSTeXRootReplaceFile *> *partlyFiles = [NSMutableArray array];
    NSString *withReason = TSLocalized(@"TeXRootSearch.Report.FileReason", @"%1$@ (%2$@)");
    for (TSTeXRootReplaceRecord *record in report.records) {
        NSString *path = record.file.file.relativePath;
        switch (record.status) {
            case TSTeXRootReplaceStatusApplied:
                [replaced addObject:path];
                break;
            case TSTeXRootReplaceStatusPartial:
                [partly addObject:[NSString stringWithFormat:withReason, path, [self reasonOfRecord:record]]];
                [partlyFiles addObject:record.file];
                break;
            case TSTeXRootReplaceStatusNotApplied:
            case TSTeXRootReplaceStatusFailed:
                [notReplaced addObject:[NSString stringWithFormat:withReason, path, [self reasonOfRecord:record]]];
                break;
        }
    }
    NSAlert *alert = [NSAlert new];
    alert.alertStyle = NSAlertStyleWarning;
    alert.messageText = title ?: ((replaced.count || partly.count) ? TSLocalized(@"TeXRootSearch.Report.SomeTitle", @"Some files could not be replaced in")
                                                                 : TSLocalized(@"TeXRootSearch.Changed.Title", @"Nothing was replaced"));
    NSMutableArray<NSString *> *lines = [NSMutableArray array];
    if (replaced.count && !title)
        [lines addObject:[NSString stringWithFormat:TSLocalized(@"TeXRootSearch.Report.Replaced", @"Replaced: %@"), [self listOfPaths:replaced]]];
    if (partly.count)
        [lines addObject:[NSString stringWithFormat:TSLocalized(@"TeXRootSearch.Report.Partly", @"Partly replaced: %@"), [self listOfPaths:partly]]];
    if (notReplaced.count)
        [lines addObject:[NSString stringWithFormat:TSLocalized(@"TeXRootSearch.Report.NotReplaced", @"Not replaced: %@"), [self listOfPaths:notReplaced]]];
    NSURL *backup = report.backupFolder;
    if (backup)
        [lines addObject:[NSString stringWithFormat:TSLocalized(@"TeXRootSearch.Report.Backup", @"Backup: %@"), [self pathOfURL:(NSURL *_Nonnull)backup]]];
    if (report.backupNotes.count)
        [lines addObject:[NSString stringWithFormat:TSLocalized(@"TeXRootSearch.Report.BackupUTF8", @"Backed up in UTF-8: %@"), [self listOfPaths:report.backupNotes]]];
    [self setText:[lines componentsJoinedByString:@"\n"] ofAlert:alert];
    [alert addButtonWithTitle:NSLocalizedString(@"OK", @"OK")];
    NSModalResponse finder = 0, original = 0, next = NSAlertSecondButtonReturn;
    if (backup) {
        [alert addButtonWithTitle:TSLocalized(@"TeXRootSearch.ShowInFinder", @"Show in Finder")];
        finder = next++;
    }
    if (partlyFiles.count && self.openTextHandler) {
        [alert addButtonWithTitle:TSLocalized(@"TeXRootSearch.OpenOriginal", @"Open the Original Text in a New Document")];
        original = next++;
    }
    __weak typeof(self) weakSelf = self;
    [self presentAlert:alert answer:^(NSModalResponse response) {
        if (finder && response == finder) {
            [NSWorkspace.sharedWorkspace activateFileViewerSelectingURLs:@[(NSURL *_Nonnull)backup]];
        } else if (original && response == original) {
            // The texts as approved, kept until now (spec §2.5.3a).
            for (TSTeXRootReplaceFile *file in partlyFiles)
                weakSelf.openTextHandler(file.originalText);
        }
    }];
}

@end

@implementation TSTeXRootSearchWindowController (ReplaceAllPrivate)

#pragma mark While it runs

/// ■, Escape and ⌘. while Replace All runs: before the confirmation, check 1 is dropped; afterwards the run stops.
- (void)stopReplacing
{
    if (self.run) {
        [self.run stop];
        return;
    }
    // Check 1: its collection is cancelled (a download it waits for, too) and its result dropped (Codex 4b F2).
    [self.checkCollector cancel];
    self.checkCollector = nil;
    TSReplaceRequest++;
    self.replacing = NO;
    [self updateFromModel];
}

- (void)updateControlsForReplacing
{
    BOOL free = !self.replacing && self.model != nil;
    self.modeControl.enabled = free;
    self.refreshButton.enabled = free;
    self.findFieldView.editable = free;
    self.replaceFieldView.editable = free;
    self.regexBox.enabled = free;
    self.ignoreCaseBox.enabled = free;
    self.moreOptionsButton.enabled = free;
    self.setPopUp.enabled = free;
    self.editSetButton.enabled = free;
    self.backupBox.enabled = free;
    self.fileTree.outlineView.enabled = free;
    self.resultsList.tableView.enabled = free;
    if (self.replacing)
        self.replaceAllButton.enabled = NO;
}

@end
