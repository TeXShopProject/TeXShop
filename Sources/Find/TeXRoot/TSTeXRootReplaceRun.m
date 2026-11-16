// SPDX-License-Identifier: GPL-2.0-or-later
#import "TSTeXRootReplaceRun.h"
#include <stdatomic.h>

NSArray<NSString *> *TSTeXRootChangedFiles(TSTeXRootProject *listed, TSTeXRootProject *now,
                                           BOOL (NS_NOESCAPE ^isIncluded)(TSTeXRootProjectFile *file))
{
    NSMutableDictionary<id, TSTeXRootProjectFile *> *nowByIdentifier = [NSMutableDictionary dictionary];
    for (TSTeXRootProjectFile *file in now.files)
        nowByIdentifier[file.identifier] = file;
    NSMutableOrderedSet<NSString *> *changed = [NSMutableOrderedSet orderedSet];
    NSMutableSet<NSString *> *listedPaths = [NSMutableSet set];
    NSMutableSet *listedIdentifiers = [NSMutableSet set];
    for (TSTeXRootProjectFile *then in listed.files) {
        [listedPaths addObject:then.relativePath];
        [listedIdentifiers addObject:then.identifier];
        if (!isIncluded(then))
            continue;
        TSTeXRootProjectFile *file = nowByIdentifier[then.identifier];
        BOOL same = NO;
        if (file && then.isOpen)
            same = file.isOpen && [file.text isEqualToString:then.text];
        else if (file)
            same = !file.isOpen && file.sha256 && then.sha256 && [file.sha256 isEqualToData:(NSData *_Nonnull)then.sha256] && file.size == then.size
                && (file.modificationDate == then.modificationDate || [file.modificationDate isEqualToDate:(NSDate *_Nonnull)then.modificationDate]);
        if (!same)
            [changed addObject:then.relativePath];
    }
    // Added: a file the list has never seen (another file at a listed path counts above, by its identity).
    for (TSTeXRootProjectFile *file in now.files)
        if (![listedIdentifiers containsObject:file.identifier] && ![listedPaths containsObject:file.relativePath])
            [changed addObject:file.relativePath];
    return changed.array;
}

#pragma mark Records

@interface TSTeXRootReplaceRecord ()
@property (nonatomic, readwrite) TSTeXRootReplaceFile *file;
@property (nonatomic, readwrite) TSTeXRootReplaceStatus status;
@property (nonatomic, readwrite) TSTeXRootReplaceReason reason;
@property (nonatomic, readwrite, nullable) NSError *error;
@end

@implementation TSTeXRootReplaceRecord
- (instancetype)initWithFile:(TSTeXRootReplaceFile *)file status:(TSTeXRootReplaceStatus)status reason:(TSTeXRootReplaceReason)reason error:(nullable NSError *)error
{
    if (!(self = [super init]))
        return nil;
    _file = file;
    _status = status;
    _reason = reason;
    _error = error;
    return self;
}
@end

@interface TSTeXRootReplaceReport ()
@property (nonatomic, readwrite, copy) NSArray<TSTeXRootReplaceRecord *> *records;
@property (nonatomic, readwrite, copy) NSArray<NSString *> *changedFiles;
@property (nonatomic, readwrite, nullable) NSError *backupError;
@property (nonatomic, readwrite, copy, nullable) NSURL *backupFolder;
@property (nonatomic, readwrite, copy) NSArray<NSString *> *backupNotes;
@property (nonatomic, readwrite) BOOL stopped;
@end

@implementation TSTeXRootReplaceReport

- (instancetype)initPrivate
{
    if (!(self = [super init]))
        return nil;
    _records = @[];
    _changedFiles = @[];
    _backupNotes = @[];
    return self;
}

- (BOOL)allApplied
{
    if (self.records.count == 0)
        return NO;
    for (TSTeXRootReplaceRecord *record in self.records)
        if (record.status != TSTeXRootReplaceStatusApplied)
            return NO;
    return YES;
}

- (NSUInteger)numberOfAppliedItems
{
    NSUInteger count = 0;
    for (TSTeXRootReplaceRecord *record in self.records)
        if (record.status == TSTeXRootReplaceStatusApplied)
            count += record.file.numberOfItems;
    return count;
}

- (NSUInteger)numberOfAppliedFiles
{
    NSUInteger count = 0;
    for (TSTeXRootReplaceRecord *record in self.records)
        if (record.status == TSTeXRootReplaceStatusApplied)
            count++;
    return count;
}

@end

#pragma mark Run

@interface TSTeXRootReplaceRun () {
    atomic_bool _stopRequested;
}
@property (nonatomic, readwrite) TSTeXRootReplacePlan *plan;
@property (nonatomic, strong) TSTeXRootProject *listed;
@property (nonatomic, strong) TSTeXRootSourceCodec *codec;
@property (nonatomic, readwrite) TSTeXRootDiskWriter *writer;
@property (nonatomic, readwrite, getter=isRunning) BOOL running;
@property (nonatomic, strong) dispatch_queue_t queue;
@property (nonatomic, copy, nullable) void (^completion)(TSTeXRootReplaceReport *report);
@property (nonatomic, strong) TSTeXRootReplaceReport *report;
@property (nonatomic, strong) NSMutableArray<TSTeXRootReplaceRecord *> *records;
/// The text views made read-only, to make editable again at the end.
@property (nonatomic, strong) NSMutableArray<NSTextView *> *lockedViews;
@property (nonatomic, strong, nullable) TSTeXRootDocumentApplier *applier;
/// The collector of check 2 while it runs.
@property (nonatomic, strong, nullable) TSTeXRootProjectCollector *checkCollector;
/// The text storages whose view could not be edited when the run began: not replaced in (spec §2.5.1a).
@property (nonatomic, strong) NSHashTable<NSTextStorage *> *notEditable;
@end

@implementation TSTeXRootReplaceRun

- (instancetype)initWithPlan:(TSTeXRootReplacePlan *)plan listedProject:(TSTeXRootProject *)listed codec:(TSTeXRootSourceCodec *)codec
{
    if (!(self = [super init]))
        return nil;
    _plan = plan;
    _listed = listed;
    _codec = codec;
    _writer = [[TSTeXRootDiskWriter alloc] initWithCodec:codec];
    _queue = dispatch_queue_create("org.texshop.texroot-replace", DISPATCH_QUEUE_SERIAL);
    _records = [NSMutableArray array];
    _lockedViews = [NSMutableArray array];
    _actionName = @"Replace All";
    _makeCollector = ^TSTeXRootProjectCollector *_Nullable { return nil; };
    _notEditable = [NSHashTable weakObjectsHashTable];
    _isIncluded = ^BOOL(TSTeXRootProjectFile *file) { return YES; };
    _textViewForFile = ^NSTextView *_Nullable(TSTeXRootReplaceFile *file) { return nil; };
    _backupEncoderForOpenDocument = ^NSData *_Nullable (^(TSTeXRootReplaceFile *file))(BOOL *) {
        NSString *text = file.originalText;
        return ^NSData *_Nullable(BOOL *usedUTF8) { return [text dataUsingEncoding:NSUTF8StringEncoding]; };
    };
    atomic_init(&_stopRequested, false);
    return self;
}

- (BOOL)stopRequested
{
    return atomic_load(&_stopRequested);
}

- (void)stop
{
    atomic_store(&_stopRequested, true);
    [self.applier stop];
    // During check 2 it ends at once: the collection is cancelled (a download it waits for, too), and its result,
    // when it comes, is dropped (Codex 4b F2).
    TSTeXRootProjectCollector *collector = self.checkCollector;
    if (collector) {
        self.checkCollector = nil;
        [collector cancel];
        [self markRestFrom:0 reason:TSTeXRootReplaceReasonStopped];
        [self finish];
    }
}

- (void)runWithCompletion:(void (^)(TSTeXRootReplaceReport *report))completion
{
    self.completion = completion;
    self.running = YES;
    self.report = [[TSTeXRootReplaceReport alloc] initPrivate];
    [TSTeXRootReplaceGuard setRunning:YES];
    [self lockOpenDocuments];
    // Check 2 (spec §2.5.1): the files collected again, compared with the list approved.
    NSMutableSet *included = [NSMutableSet set];
    for (TSTeXRootProjectFile *file in self.listed.files)
        if (self.isIncluded(file))
            [included addObject:file.identifier];
    TSTeXRootProjectCollector *collector = self.makeCollector();
    void (^prepare)(TSTeXRootProjectCollector *) = self.prepareCollector;
    self.checkCollector = collector;
    TSTeXRootProject *listed = self.listed;
    NSMutableArray<NSURL *> *projectFiles = [NSMutableArray array];
    for (TSTeXRootProjectFile *file in listed.files)
        [projectFiles addObject:file.url];
    [TSTeXRootReplaceGuard setProjectFiles:projectFiles];
    dispatch_async(self.queue, ^{
        if (prepare && collector)
            prepare((TSTeXRootProjectCollector *_Nonnull)collector);
        TSTeXRootProject *now = [collector collect];
        NSArray<NSString *> *changed = now ? TSTeXRootChangedFiles(listed, (TSTeXRootProject *_Nonnull)now, ^BOOL(TSTeXRootProjectFile *file) {
            return [included containsObject:file.identifier];
        }) : @[listed.rootFile.relativePath ?: @""];
        dispatch_async(dispatch_get_main_queue(), ^{
            if (self.checkCollector != collector || !self.running)
                return; // stopped meanwhile: already reported
            self.checkCollector = nil;
            if (changed.count) {
                self.report.changedFiles = changed;
                [self finish];
                return;
            }
            if (self.stopRequested) {
                [self markRestFrom:0 reason:TSTeXRootReplaceReasonStopped];
                [self finish];
                return;
            }
            [self backUp];
        });
    });
}

/// The text views of the open documents of the plan: read-only until the report (spec §2.5.1a).
- (void)lockOpenDocuments
{
    NSMutableArray<NSTextStorage *> *storages = [NSMutableArray array];
    for (TSTeXRootReplaceFile *file in self.plan.files) {
        if (!file.openDocument)
            continue;
        NSTextView *main = self.textViewForFile(file);
        NSTextStorage *storage = main.textStorage;
        if (!storage)
            continue;
        [storages addObject:storage];
        // Made read-only meanwhile (the list was made while it could be edited): it is not replaced in, and is never
        // made editable here (Codex 4b F7).
        if (!main.isEditable)
            [self.notEditable addObject:(NSTextStorage *_Nonnull)storage];
        for (NSLayoutManager *layout in storage.layoutManagers)
            for (NSTextContainer *container in layout.textContainers) {
                NSTextView *view = container.textView;
                if (view.isEditable) {
                    view.editable = NO;
                    [self.lockedViews addObject:view];
                }
            }
    }
    [TSTeXRootReplaceGuard setLockedTextStorages:storages];
}

- (void)unlockOpenDocuments
{
    for (NSTextView *view in self.lockedViews)
        view.editable = YES;
    [self.lockedViews removeAllObjects];
    [TSTeXRootReplaceGuard setLockedTextStorages:nil];
}

#pragma mark Backup

- (void)backUp
{
    NSURL *folder = self.backupFolder;
    if (!folder) {
        [self writeFilesOnDisk];
        return;
    }
    // The open documents' encodings are read here on the main thread; their texts as approved become bytes on the
    // background queue (spec §2.9).
    NSMapTable<TSTeXRootReplaceFile *, NSData *_Nullable (^)(BOOL *)> *encoders = [NSMapTable strongToStrongObjectsMapTable];
    for (TSTeXRootReplaceFile *file in self.plan.files)
        if (file.openDocument)
            [encoders setObject:self.backupEncoderForOpenDocument(file) forKey:file];
    TSTeXRootReplacePlan *plan = self.plan;
    NSDate *date = self.date ?: [NSDate date];
    __weak typeof(self) weakSelf = self;
    dispatch_async(self.queue, ^{
        NSError *error = nil;
        NSArray<NSString *> *notes = nil;
        NSURL *made = [TSTeXRootBackup backUpPlan:plan inFolder:(NSURL *_Nonnull)folder date:date
                                 openDocumentData:^NSData *(TSTeXRootReplaceFile *file, BOOL *usedUTF8) {
            NSData *_Nullable (^encode)(BOOL *) = [encoders objectForKey:file];
            return encode ? encode(usedUTF8) : nil;
        } notes:&notes cancellation:^BOOL { return weakSelf.stopRequested; } error:&error];
        dispatch_async(dispatch_get_main_queue(), ^{
            if (!made) {
                if (error.code == TSTeXRootReplaceErrorChanged) {
                    NSURL *url = error.userInfo[NSURLErrorKey];
                    NSString *path = nil;
                    for (TSTeXRootReplaceFile *file in plan.files)
                        if ([file.file.url isEqual:url])
                            path = file.file.relativePath;
                    self.report.changedFiles = @[path ?: url.lastPathComponent ?: @""];
                } else if (error.code == TSTeXRootReplaceErrorStopped) {
                    [self markRestFrom:0 reason:TSTeXRootReplaceReasonStopped];
                } else {
                    self.report.backupError = error;
                }
                [self finish];
                return;
            }
            self.report.backupFolder = made;
            self.report.backupNotes = notes ?: @[];
            [self writeFilesOnDisk];
        });
    });
}

#pragma mark Files on the disk

- (void)writeFilesOnDisk
{
    NSArray<TSTeXRootReplaceFile *> *files = self.plan.files;
    TSTeXRootDiskWriter *writer = self.writer;
    void (^written)(TSTeXRootReplaceFile *) = self.fileWritten;
    __weak typeof(self) weakSelf = self;
    dispatch_async(self.queue, ^{
        NSMutableArray<TSTeXRootReplaceRecord *> *records = [NSMutableArray array];
        BOOL failed = NO, stopped = NO;
        for (TSTeXRootReplaceFile *file in files) {
            if (file.openDocument)
                break; // the files on the disk come first
            if (weakSelf.stopRequested) {
                stopped = YES;
                break;
            }
            NSError *error = nil;
            if ([writer writeFile:file error:&error]) {
                [records addObject:[[TSTeXRootReplaceRecord alloc] initWithFile:file status:TSTeXRootReplaceStatusApplied reason:TSTeXRootReplaceReasonNone error:nil]];
            } else {
                [records addObject:[[TSTeXRootReplaceRecord alloc] initWithFile:file status:TSTeXRootReplaceStatusFailed reason:TSTeXRootReplaceReasonError error:error]];
                failed = YES;
                break;
            }
            if (written)
                written(file);
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            [self.records addObjectsFromArray:records];
            if (failed || stopped) {
                [self markRestFrom:self.records.count reason:failed ? TSTeXRootReplaceReasonAfterFailure : TSTeXRootReplaceReasonStopped];
                [self finish];
                return;
            }
            [self applyToOpenDocumentAtIndex:self.records.count];
        });
    });
}

- (void)markRestFrom:(NSUInteger)index reason:(TSTeXRootReplaceReason)reason
{
    NSArray<TSTeXRootReplaceFile *> *files = self.plan.files;
    for (NSUInteger i = index; i < files.count; i++)
        [self.records addObject:[[TSTeXRootReplaceRecord alloc] initWithFile:files[i] status:TSTeXRootReplaceStatusNotApplied reason:reason error:nil]];
    if (reason == TSTeXRootReplaceReasonStopped)
        self.report.stopped = YES;
}

#pragma mark Open documents

- (void)applyToOpenDocumentAtIndex:(NSUInteger)index
{
    NSArray<TSTeXRootReplaceFile *> *files = self.plan.files;
    if (index >= files.count) {
        [self finish];
        return;
    }
    if (self.stopRequested) {
        [self markRestFrom:index reason:TSTeXRootReplaceReasonStopped];
        [self finish];
        return;
    }
    TSTeXRootReplaceFile *file = files[index];
    NSTextView *view = self.textViewForFile(file);
    if (view && [self.notEditable containsObject:(NSTextStorage *_Nonnull)view.textStorage]) {
        [self.records addObject:[[TSTeXRootReplaceRecord alloc] initWithFile:file status:TSTeXRootReplaceStatusNotApplied reason:TSTeXRootReplaceReasonNotEditable error:nil]];
        [self applyToOpenDocumentAtIndex:index + 1];
        return;
    }
    if (!view) {
        [self.records addObject:[[TSTeXRootReplaceRecord alloc] initWithFile:file status:TSTeXRootReplaceStatusNotApplied reason:TSTeXRootReplaceReasonChanged error:nil]];
        [self applyToOpenDocumentAtIndex:index + 1];
        return;
    }
    TSTeXRootDocumentApplier *applier = [[TSTeXRootDocumentApplier alloc] initWithTextView:view replacements:file.replacements
                                                                              originalText:file.originalText actionName:self.actionName];
    self.applier = applier;
    if (self.applierMade)
        self.applierMade(applier);
    [applier startWithCompletion:^(TSTeXRootDocumentApplier *done) {
        self.applier = nil;
        TSTeXRootReplaceStatus status = done.outcome == TSTeXRootApplyOutcomeApplied ? TSTeXRootReplaceStatusApplied
            : done.outcome == TSTeXRootApplyOutcomePartial ? TSTeXRootReplaceStatusPartial : TSTeXRootReplaceStatusNotApplied;
        TSTeXRootReplaceReason reason = TSTeXRootReplaceReasonNone;
        switch (done.reason) {
            case TSTeXRootApplyReasonNone: reason = TSTeXRootReplaceReasonNone; break;
            case TSTeXRootApplyReasonChanged: reason = TSTeXRootReplaceReasonChanged; break;
            case TSTeXRootApplyReasonRefused: reason = TSTeXRootReplaceReasonRefused; break;
            case TSTeXRootApplyReasonStopped: reason = TSTeXRootReplaceReasonStopped; break;
            case TSTeXRootApplyReasonUnexpectedChange: reason = TSTeXRootReplaceReasonUnexpectedChange; break;
        }
        [self.records addObject:[[TSTeXRootReplaceRecord alloc] initWithFile:file status:status reason:reason error:nil]];
        if (reason == TSTeXRootReplaceReasonStopped)
            self.report.stopped = YES;
        // A document that changed, refused or was stopped: the documents after it are not replaced in (spec §2.5.5:
        // what failed stops it; an open document that was closed or edited is only skipped).
        if (status == TSTeXRootReplaceStatusPartial || reason == TSTeXRootReplaceReasonRefused || reason == TSTeXRootReplaceReasonStopped) {
            [self markRestFrom:index + 1 reason:reason == TSTeXRootReplaceReasonStopped ? TSTeXRootReplaceReasonStopped : TSTeXRootReplaceReasonAfterFailure];
            [self finish];
            return;
        }
        [self applyToOpenDocumentAtIndex:index + 1];
    }];
}

#pragma mark End

- (void)finish
{
    if (!self.running)
        return; // once
    [self unlockOpenDocuments];
    self.report.records = self.records;
    self.running = NO;
    [TSTeXRootReplaceGuard setRunning:NO];
    void (^completion)(TSTeXRootReplaceReport *) = self.completion;
    self.completion = nil;
    if (completion)
        completion(self.report);
}

@end
