// SPDX-License-Identifier: GPL-2.0-or-later
#import "TSTeXRootSearchModel.h"
#import "TSRegexMultipleReplace.h"
#import <stdatomic.h>

NSUInteger TSTeXRootSearchShownLines(NSString *_Nullable text)
{
    static NSCharacterSet *breaks;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        const unichar characters[] = {'\n', '\r', 0x0085, 0x2028, 0x2029};
        breaks = [NSCharacterSet characterSetWithCharactersInString:[NSString stringWithCharacters:characters length:5]];
    });
    NSUInteger length = text.length, lines = 1, location = 0;
    while (lines <= TSTeXRootSearchMaximumShownLines) {
        NSRange found = [(NSString *_Nonnull)text rangeOfCharacterFromSet:breaks options:NSLiteralSearch range:NSMakeRange(location, length - location)];
        if (found.location == NSNotFound)
            break;
        location = NSMaxRange(found);
        if ([text characterAtIndex:found.location] == '\r' && location < length && [text characterAtIndex:location] == '\n')
            location++;
        if (location >= length)
            break;
        lines++;
    }
    return lines;
}

@implementation TSTeXRootSearchEnvironment

- (instancetype)init
{
    if (!(self = [super init]))
        return nil;
    _collectorForRoot = ^TSTeXRootProjectCollector *(NSURL *rootURL) {
        [NSException raise:NSInternalInconsistencyException format:@"No collector for %@", rootURL];
        return (TSTeXRootProjectCollector *_Nonnull)nil;
    };
    _sourcesForFiles = ^NSArray<TSTeXRootSearchSource *> *(NSArray<TSTeXRootProjectFile *> *files) {
        NSMutableArray<TSTeXRootSearchSource *> *sources = [NSMutableArray array];
        for (TSTeXRootProjectFile *file in files)
            [sources addObject:[[TSTeXRootSearchSource alloc] initWithFile:file]];
        return sources;
    };
    _performAfterDelay = ^(NSTimeInterval delay, dispatch_block_t block) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)), dispatch_get_main_queue(), block);
    };
    return self;
}

@end

/// Tells the background work that it is no longer wanted. Safe from any thread.
@interface TSTeXRootSearchToken : NSObject
@property (atomic, getter=isCancelled) BOOL cancelled;
@end

@implementation TSTeXRootSearchToken
@end

@interface TSTeXRootSearchModel ()
@property (nonatomic, readonly) TSTeXRootSearchEnvironment *environment;
@property (nonatomic, readonly) dispatch_queue_t queue;
@property (nonatomic, readwrite, nullable) TSTeXRootProject *project;
@property (nonatomic, readwrite) TSTeXRootSearchActivity activity;
@property (nonatomic, readwrite) NSUInteger generation;
@property (nonatomic, readwrite) NSUInteger resultGeneration;
@property (nonatomic, readwrite) BOOL reachedLimit;
@property (nonatomic, readwrite, nullable) NSError *queryError;
@property (nonatomic, readwrite, getter=isStopped) BOOL stopped;
@property (nonatomic, readwrite) NSUInteger collectedFolders;
@property (nonatomic, readwrite) NSUInteger collectedFiles;
@property (nonatomic, readwrite, copy, nullable) NSString *currentFolder;
@property (nonatomic, readwrite) TSTeXRootCollectionFailure collectionFailure;
/// The results of the files on, by identifier; a file without items has none.
@property (nonatomic, strong) NSMutableDictionary<id, TSTeXRootSearchFileResult *> *fileResults;
/// The files turned off, by identifier.
@property (nonatomic, strong) NSMutableSet *excludedFiles;
/// The items turned off, by the identifier of their file, as their keys (TSItemKey): the line, the column and the
/// text, so that an item stays off when the file is searched again after an edit elsewhere, or after the document was
/// opened with its line endings changed.
@property (nonatomic, strong) NSMutableDictionary<id, NSMutableSet<NSString *> *> *excludedItems;
@property (nonatomic, strong, nullable) TSTeXRootSearchToken *token;
@property (nonatomic, strong, nullable) TSTeXRootProjectCollector *collector;
/// Moves on with each request for a search after the pause, so that only the last one runs.
@property (nonatomic) NSUInteger requestNumber;
/// What the search after the pause covers: every file on, or only the open documents edited meanwhile.
@property (nonatomic) BOOL fullSearchPending;
/// The reasons of the texts last searched, by identifier (an open document that cannot be edited, …).
@property (nonatomic, strong) NSMutableDictionary<id, NSNumber *> *sourceReasons;
@property (nonatomic, strong) NSMutableSet *pendingFileIdentifiers;
/// The lines each item takes in the list, by file (one byte per item), worked out on the background queue.
@property (nonatomic, strong) NSMapTable<TSTeXRootSearchFileResult *, NSData *> *shownLines;
/// The documents' signature when the files being collected, or listed, were collected.
@property (nonatomic, strong, nullable) id collectingSignature;
@property (nonatomic, strong, nullable) id collectedSignature;
@property (nonatomic, readwrite) NSUInteger numberOfCollections;
/// The items on in each file with items off, until the next change (the status asks several times per change).
@property (nonatomic, strong) NSMapTable<TSTeXRootSearchFileResult *, NSNumber *> *includedCounts;
@end

@implementation TSTeXRootSearchModel

- (instancetype)initWithRootURL:(NSURL *)rootURL environment:(TSTeXRootSearchEnvironment *)environment
{
    if (!(self = [super init]))
        return nil;
    _rootURL = [rootURL copy];
    _environment = environment;
    _queue = dispatch_queue_create("org.texshop.TeXRootSearch", DISPATCH_QUEUE_SERIAL);
    _pause = 0.3;
    _maximumItemsPerFile = TSTeXRootSearch.defaultMaximumItemsPerFile;
    _maximumItems = TSTeXRootSearch.defaultMaximumItems;
    _findString = @"";
    _replaceString = @"";
    _fileResults = [NSMutableDictionary dictionary];
    _excludedFiles = [NSMutableSet set];
    _excludedItems = [NSMutableDictionary dictionary];
    _pendingFileIdentifiers = [NSMutableSet set];
    _sourceReasons = [NSMutableDictionary dictionary];
    _includedCounts = [NSMapTable strongToStrongObjectsMapTable];
    _shownLines = [NSMapTable weakToStrongObjectsMapTable];
    return self;
}

- (void)dealloc
{
    _token.cancelled = YES;
    [_collector cancel];
}

- (void)changed
{
    [self.includedCounts removeAllObjects];
    [self.delegate texRootSearchModelDidChange:self];
}

#pragma mark Conditions

/// A change the user made: the event line goes, as does the note that the search was stopped.
- (void)userChanged
{
    self.eventMessage = nil;
    self.stopped = NO;
}

/// A condition of the search changed: every item is on again, and the search runs after the pause.
- (void)conditionsChanged
{
    [self userChanged];
    self.generation++;
    [self.excludedItems removeAllObjects];
    [self searchAfterPause];
    [self changed];
}

- (void)setMode:(TSTeXRootSearchMode)mode
{
    if (_mode == mode)
        return;
    _mode = mode;
    [self conditionsChanged];
}

- (void)setFindString:(NSString *)findString
{
    if ([_findString isEqualToString:findString])
        return;
    _findString = [findString copy];
    [self conditionsChanged];
}

- (void)setReplaceString:(NSString *)replaceString
{
    if ([_replaceString isEqualToString:replaceString])
        return;
    _replaceString = [replaceString copy];
    if (self.mode == TSTeXRootSearchModeReplace)
        [self conditionsChanged];
}

- (void)setOptions:(TSRegexFindOptions)options
{
    if (_options == options)
        return;
    _options = options;
    if (self.mode != TSTeXRootSearchModeMultipleReplace)
        [self conditionsChanged];
}

- (void)setReplacementSyntax:(TSRegexReplacementSyntax)replacementSyntax
{
    if (_replacementSyntax == replacementSyntax)
        return;
    _replacementSyntax = replacementSyntax;
    if (self.mode == TSTeXRootSearchModeReplace)
        [self conditionsChanged];
}

- (void)setMultipleReplace:(TSRegexMultipleReplace *)multipleReplace
{
    if (_multipleReplace == multipleReplace || [_multipleReplace isEqual:multipleReplace])
        return;
    _multipleReplace = [multipleReplace copy];
    if (self.mode == TSTeXRootSearchModeMultipleReplace)
        [self conditionsChanged];
}

- (void)setMode:(TSTeXRootSearchMode)mode findString:(NSString *)findString replaceString:(NSString *)replaceString
        options:(TSRegexFindOptions)options syntax:(TSRegexReplacementSyntax)syntax multipleReplace:(nullable TSRegexMultipleReplace *)set
{
    _mode = mode;
    _findString = [findString copy];
    _replaceString = [replaceString copy];
    _options = options;
    _replacementSyntax = syntax;
    _multipleReplace = [set copy];
    [self conditionsChanged];
}

- (void)searchNow
{
    if (self.activity == TSTeXRootSearchActivityCollecting)
        return;
    self.requestNumber++;
    self.fullSearchPending = NO;
    [self.pendingFileIdentifiers removeAllObjects];
    [self computeFiles:nil];
}

- (void)searchAfterPause
{
    self.fullSearchPending = YES;
    [self scheduleSearch];
}

/// Waits for the pause, then searches every file on, or only the edited documents when nothing else changed.
- (void)scheduleSearch
{
    if (self.activity == TSTeXRootSearchActivityCollecting || !self.project)
        return;
    // A search under way is for conditions that are gone; a full one is left unfinished, so all is searched again.
    if (self.activity == TSTeXRootSearchActivityComputing)
        self.fullSearchPending = YES;
    self.token.cancelled = YES;
    self.activity = TSTeXRootSearchActivityWaiting;
    NSUInteger number = ++self.requestNumber;
    __weak typeof(self) weakSelf = self;
    self.environment.performAfterDelay(self.pause, ^{
        typeof(self) model = weakSelf;
        if (!model || model.requestNumber != number || model.activity != TSTeXRootSearchActivityWaiting)
            return;
        NSMutableArray<TSTeXRootProjectFile *> *files = [NSMutableArray array];
        for (TSTeXRootProjectFile *file in model.project.files)
            if ([model.pendingFileIdentifiers containsObject:file.identifier] && [model isFileIncluded:file])
                [files addObject:file];
        BOOL full = model.fullSearchPending || model.reachedLimit;
        model.fullSearchPending = NO;
        [model.pendingFileIdentifiers removeAllObjects];
        [model computeFiles:full ? nil : files];
    });
}

/// The query of the current conditions; nil with no error when there is nothing to search for.
- (nullable TSTeXRootSearchQuery *)makeQuery:(NSError **)error
{
    switch (self.mode) {
        case TSTeXRootSearchModeFind:
            return self.findString.length ? [TSTeXRootSearchQuery findQueryWithString:self.findString options:self.options error:error] : nil;
        case TSTeXRootSearchModeReplace:
            return self.findString.length ? [TSTeXRootSearchQuery replaceQueryWithString:self.findString replacement:self.replaceString
                                                                                 options:self.options syntax:self.replacementSyntax error:error] : nil;
        case TSTeXRootSearchModeMultipleReplace: {
            if (!self.multipleReplace)
                return nil;
            TSTeXRootSearchQuery *query = [TSTeXRootSearchQuery multipleReplaceQueryWithSet:(TSRegexMultipleReplace *_Nonnull)self.multipleReplace];
            if (error && query.ruleErrors.count > 0)
                *error = query.ruleErrors[(NSNumber *_Nonnull)[query.ruleErrors.allKeys sortedArrayUsingSelector:@selector(compare:)].firstObject];
            return query;
        }
    }
    return nil;
}

#pragma mark Computing

- (nullable id)currentDocumentsSignature
{
    return self.environment.documentsSignature ? self.environment.documentsSignature() : nil;
}

/// The texts taken when collecting still stand: no document was opened, closed or renamed since.
- (BOOL)collectedDocumentsStand
{
    id now = [self currentDocumentsSignature];
    return now == self.collectedSignature || [now isEqual:self.collectedSignature];
}

/// The lines of each item in the list, one byte each (spec §2.9: nothing is measured on the main thread).
static NSData *TSShownLinesOfFile(TSTeXRootSearchFileResult *file, TSTeXRootSearchMode mode)
{
    NSMutableData *data = [NSMutableData dataWithLength:file.items.count];
    uint8_t *bytes = data.mutableBytes;
    NSUInteger index = 0;
    for (TSTeXRootSearchItem *item in file.items) {
        NSUInteger lines = TSTeXRootSearchShownLines(item.beforeText);
        if (mode != TSTeXRootSearchModeFind)
            lines = MAX(lines, TSTeXRootSearchShownLines(item.afterText));
        bytes[index++] = (uint8_t)MIN(lines, (NSUInteger)255);
    }
    return data;
}

- (NSArray<TSTeXRootProjectFile *> *)includedFiles
{
    NSMutableArray<TSTeXRootProjectFile *> *files = [NSMutableArray array];
    for (TSTeXRootProjectFile *file in self.project.files)
        if (![self.excludedFiles containsObject:file.identifier])
            [files addObject:file];
    return files;
}

/// Searches `only` (nil: every file on) for the current generation. Results reach the list only while that
/// generation is current. A first list is filled file by file; otherwise the list stays as it was until the new one
/// is complete (spec §2.7.3).
- (void)computeFiles:(nullable NSArray<TSTeXRootProjectFile *> *)only
{
    if (self.project && ![self collectedDocumentsStand]) {
        // A document was opened or closed since the files were collected: its text taken then may be gone.
        [self collect];
        return;
    }
    self.token.cancelled = YES;
    TSTeXRootSearchToken *token = [TSTeXRootSearchToken new];
    self.token = token;
    NSUInteger generation = self.generation;
    NSError *error = nil;
    TSTeXRootSearchQuery *query = [self makeQuery:&error];
    self.queryError = query.mode == TSTeXRootSearchModeMultipleReplace ? nil : error;
    if (!query || !self.project) {
        [self.fileResults removeAllObjects];
        self.reachedLimit = NO;
        self.resultGeneration = generation;
        self.activity = TSTeXRootSearchActivityIdle;
        [self changed];
        return;
    }
    if (query.mode == TSTeXRootSearchModeMultipleReplace)
        self.queryError = error; // a rule that cannot be used is shown, and the others still apply
    NSArray<TSTeXRootProjectFile *> *files = only ?: [self includedFiles];
    NSArray<TSTeXRootSearchSource *> *sources = self.environment.sourcesForFiles(files);
    for (TSTeXRootSearchSource *source in sources)
        self.sourceReasons[source.file.identifier] = @(source.searchOnlyReason);
    NSMutableSet *recomputed = [NSMutableSet set];
    for (TSTeXRootProjectFile *file in files)
        [recomputed addObject:file.identifier];
    NSUInteger base = 0;
    if (only)
        for (id identifier in self.fileResults)
            if (![recomputed containsObject:identifier])
                base += self.fileResults[identifier].items.count;
    BOOL streams = !only && self.fileResults.count == 0;
    self.activity = TSTeXRootSearchActivityComputing;
    [self changed];
    TSTeXRootSourceCodec *codec = self.environment.codec;
    NSUInteger perFile = self.maximumItemsPerFile, maximum = self.maximumItems;
    __weak typeof(self) weakSelf = self;
    // A search is for the conditions it started with: any change of them cancels its token, and its results are then
    // dropped, even when they arrive later (spec §2.5.1). Turning items on or off moves the generation without
    // touching the results: the list that comes is still that of the conditions.
    BOOL (^isCurrent)(void) = ^BOOL {
        typeof(self) model = weakSelf;
        return model && model.token == token && !token.cancelled;
    };
    dispatch_async(self.queue, ^{
        NSUInteger total = base;
        BOOL limit = NO;
        NSMutableDictionary<id, TSTeXRootSearchFileResult *> *found = [NSMutableDictionary dictionary];
        NSMapTable<TSTeXRootSearchFileResult *, NSData *> *foundLines = [NSMapTable strongToStrongObjectsMapTable];
        for (TSTeXRootSearchSource *source in sources) {
            if (token.cancelled)
                return;
            TSTeXRootSearchResult *result = [TSTeXRootSearch searchSources:@[source] query:query generation:generation codec:codec
                                                         maximumItemsPerFile:perFile maximumItems:maximum > total ? maximum - total : 0
                                                                cancellation:^BOOL { return token.cancelled; } progress:nil];
            if (!result)
                return;
            TSTeXRootSearchFileResult *file = result.files.firstObject;
            total += file.items.count;
            NSData *lines = file ? TSShownLinesOfFile(file, query.mode) : nil;
            if (file) {
                found[source.file.identifier] = file;
                [foundLines setObject:(NSData *_Nonnull)lines forKey:file];
            }
            if (streams && file)
                dispatch_async(dispatch_get_main_queue(), ^{
                    if (!isCurrent())
                        return;
                    weakSelf.fileResults[source.file.identifier] = file;
                    [weakSelf.shownLines setObject:lines forKey:file];
                    [weakSelf changed];
                });
            if (result.reachedLimit) {
                limit = YES;
                if (total >= maximum)
                    break;
            }
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            typeof(self) model = weakSelf;
            if (!isCurrent())
                return;
            if (only) {
                for (id identifier in recomputed)
                    [model.fileResults removeObjectForKey:identifier];
                [model.fileResults addEntriesFromDictionary:found];
            } else {
                model.fileResults = found;
            }
            for (TSTeXRootSearchFileResult *file in foundLines)
                [model.shownLines setObject:[foundLines objectForKey:file] forKey:file];
            model.reachedLimit = limit;
            model.resultGeneration = model.generation;
            model.activity = TSTeXRootSearchActivityIdle;
            [model changed];
        });
    });
}

#pragma mark Files

- (void)collect
{
    [self userChanged];
    self.token.cancelled = YES;
    [self.collector cancel];
    self.requestNumber++;
    self.generation++;
    self.collectedFolders = 0;
    self.collectedFiles = 0;
    self.currentFolder = nil;
    self.collectionFailure = TSTeXRootCollectionFailureNone;
    self.activity = TSTeXRootSearchActivityCollecting;
    // The documents as they are when their texts are taken, which collectorForRoot does.
    self.collectingSignature = [self currentDocumentsSignature];
    TSTeXRootProjectCollector *collector = self.environment.collectorForRoot(self.rootURL);
    self.collector = collector;
    self.numberOfCollections++;
    __weak typeof(self) weakSelf = self;
    collector.progressHandler = ^(NSUInteger folders, NSUInteger files, NSString *folder) {
        dispatch_async(dispatch_get_main_queue(), ^{
            typeof(self) model = weakSelf;
            if (!model || model.collector != collector)
                return;
            model.collectedFolders = folders;
            model.collectedFiles = files;
            model.currentFolder = folder;
            [model changed];
        });
    };
    [self changed];
    void (^prepare)(TSTeXRootProjectCollector *) = self.environment.prepareCollector;
    dispatch_async(self.queue, ^{
        if (prepare)
            prepare(collector);
        TSTeXRootProject *project = [collector collect];
        dispatch_async(dispatch_get_main_queue(), ^{
            typeof(self) model = weakSelf;
            if (!model || model.collector != collector)
                return;
            model.collector = nil;
            [model finishCollecting:project failure:collector.failure];
        });
    });
}

- (void)finishCollecting:(nullable TSTeXRootProject *)project failure:(TSTeXRootCollectionFailure)failure
{
    id now = [self currentDocumentsSignature];
    if (!(now == self.collectingSignature || [now isEqual:self.collectingSignature])) {
        // A document was opened, closed or renamed while collecting: what was taken from it no longer stands.
        [self collect];
        return;
    }
    self.collectedSignature = self.collectingSignature;
    self.collectionFailure = failure;
    if (!project) {
        self.project = nil;
        [self.fileResults removeAllObjects];
        self.reachedLimit = NO;
        self.resultGeneration = ++self.generation;
        self.activity = TSTeXRootSearchActivityIdle;
        [self changed];
        return;
    }
    // Files off stay off when they are found again; those that went away are forgotten (spec §2.3).
    NSMutableSet *present = [NSMutableSet set];
    for (TSTeXRootProjectFile *file in project.files)
        [present addObject:file.identifier];
    [self.excludedFiles intersectSet:present];
    for (id identifier in self.excludedItems.allKeys)
        if (![present containsObject:identifier])
            [self.excludedItems removeObjectForKey:identifier];
    // The texts changed with the collection: what was listed no longer stands.
    for (id identifier in self.fileResults.allKeys)
        if (![present containsObject:identifier])
            [self.fileResults removeObjectForKey:identifier];
    self.project = project;
    self.generation++;
    self.activity = TSTeXRootSearchActivityIdle;
    [self computeFiles:nil];
}

- (BOOL)isFileIncluded:(TSTeXRootProjectFile *)file
{
    return ![self.excludedFiles containsObject:file.identifier];
}

- (TSTeXRootSearchOnlyReason)searchOnlyReasonOfFile:(TSTeXRootProjectFile *)file
{
    TSTeXRootSearchFileResult *result = self.fileResults[file.identifier];
    if (result)
        return result.searchOnlyReason;
    NSNumber *reason = self.sourceReasons[file.identifier];
    return reason ? (TSTeXRootSearchOnlyReason)reason.integerValue : file.searchOnlyReason;
}

- (NSUInteger)numberOfItemsInFile:(TSTeXRootProjectFile *)file
{
    return [self isFileIncluded:file] ? self.fileResults[file.identifier].items.count : 0;
}

- (void)setFiles:(NSArray<TSTeXRootProjectFile *> *)files included:(BOOL)included
{
    NSMutableArray<TSTeXRootProjectFile *> *changedFiles = [NSMutableArray array];
    for (TSTeXRootProjectFile *file in files)
        if ([self isFileIncluded:file] != included)
            [changedFiles addObject:file];
    if (changedFiles.count == 0)
        return;
    [self userChanged];
    self.generation++;
    for (TSTeXRootProjectFile *file in changedFiles) {
        if (included)
            [self.excludedFiles removeObject:file.identifier];
        else
            [self.excludedFiles addObject:file.identifier];
    }
    if (self.activity != TSTeXRootSearchActivityIdle || self.reachedLimit) {
        // A search is under way, or the limit made the list partial: search every file on again.
        if (self.activity != TSTeXRootSearchActivityCollecting)
            [self computeFiles:nil];
        [self changed];
        return;
    }
    if (included) {
        [self computeFiles:changedFiles];
        return;
    }
    // Off: out of the list at once; the rest of the list is still that of the current conditions.
    for (TSTeXRootProjectFile *file in changedFiles)
        [self.fileResults removeObjectForKey:file.identifier];
    self.resultGeneration = self.generation;
    [self changed];
}

- (void)textDidChangeForFileWithIdentifier:(id<NSObject, NSCopying>)identifier
{
    TSTeXRootProjectFile *changedFile = nil;
    for (TSTeXRootProjectFile *file in self.project.files)
        if ([file.identifier isEqual:identifier])
            changedFile = file;
    if (!changedFile)
        return;
    [self userChanged];
    self.generation++;
    if (![self isFileIncluded:changedFile] || self.activity == TSTeXRootSearchActivityCollecting) {
        [self changed];
        return;
    }
    [self.pendingFileIdentifiers addObject:identifier];
    [self scheduleSearch];
    [self changed];
}

- (void)openDocumentsDidChange
{
    // Collecting starts again even while it runs: the texts it took may be gone.
    [self collect];
}

- (void)documentsDidChange
{
    self.generation++;
    if (self.activity == TSTeXRootSearchActivityCollecting || !self.project) {
        [self changed];
        return;
    }
    [self computeFiles:nil];
}

#pragma mark Items

/// What identifies an item over searches of the same conditions: its line, its column and its text (and what it is
/// replaced with), not its range, which other edits and other line endings move.
static NSString *TSItemKey(TSTeXRootSearchItem *item)
{
    NSString *before = NSMaxRange(item.beforeHighlight) <= item.beforeText.length ? [item.beforeText substringWithRange:item.beforeHighlight] : item.beforeText;
    NSMutableString *key = [NSMutableString stringWithCapacity:before.length + item.replacement.length + 24];
    [key appendString:@(item.lineNumber).stringValue];
    [key appendString:@":"];
    [key appendString:@(item.beforeHighlight.location).stringValue];
    [key appendString:@":"];
    [key appendString:@(before.length).stringValue];
    [key appendString:@":"];
    [key appendString:before];
    [key appendString:@"\u2192"];
    [key appendString:item.replacement ?: @""];
    return key;
}

- (NSArray<TSTeXRootSearchFileResult *> *)results
{
    NSMutableArray<TSTeXRootSearchFileResult *> *results = [NSMutableArray array];
    for (TSTeXRootProjectFile *file in self.project.files) {
        TSTeXRootSearchFileResult *result = self.fileResults[file.identifier];
        if (result && result.items.count > 0 && [self isFileIncluded:file])
            [results addObject:result];
    }
    return results;
}

- (BOOL)isItemIncluded:(TSTeXRootSearchItem *)item inFile:(TSTeXRootSearchFileResult *)file
{
    if (self.mode == TSTeXRootSearchModeFind || file.searchOnlyReason != TSTeXRootSearchOnlyReasonNone)
        return NO;
    return ![self.excludedItems[file.source.file.identifier] containsObject:TSItemKey(item)];
}

- (void)setItems:(NSArray<TSTeXRootSearchItem *> *)items inFile:(TSTeXRootSearchFileResult *)file included:(BOOL)included
{
    if (self.mode == TSTeXRootSearchModeFind || file.searchOnlyReason != TSTeXRootSearchOnlyReasonNone)
        return;
    id identifier = file.source.file.identifier;
    NSMutableSet<NSString *> *excluded = self.excludedItems[identifier] ?: [NSMutableSet set];
    self.excludedItems[identifier] = excluded;
    BOOL changes = NO;
    for (TSTeXRootSearchItem *item in items) {
        NSString *key = TSItemKey(item);
        if ([excluded containsObject:key] == included) {
            changes = YES;
            if (included)
                [excluded removeObject:key];
            else
                [excluded addObject:key];
        }
    }
    if (!changes)
        return;
    [self userChanged];
    // What Replace All would do changed, but the list is still that of the current conditions.
    self.generation++;
    if (self.activity == TSTeXRootSearchActivityIdle && self.resultGeneration + 1 == self.generation)
        self.resultGeneration = self.generation;
    [self changed];
}

- (NSUInteger)shownLinesOfItemAtIndex:(NSUInteger)index inFile:(TSTeXRootSearchFileResult *)file
{
    NSData *lines = [self.shownLines objectForKey:file];
    if (lines && index < lines.length)
        return ((const uint8_t *)lines.bytes)[index];
    return 1;
}

- (NSUInteger)numberOfItems
{
    NSUInteger count = 0;
    for (TSTeXRootSearchFileResult *file in self.results)
        count += file.items.count;
    return count;
}

/// The items of a file that are on: all of them unless some were turned off, which only then are looked at one by one.
- (NSUInteger)numberOfIncludedItemsInFile:(TSTeXRootSearchFileResult *)file
{
    if (self.mode == TSTeXRootSearchModeFind || file.searchOnlyReason != TSTeXRootSearchOnlyReasonNone)
        return 0;
    NSSet<NSString *> *excluded = self.excludedItems[file.source.file.identifier];
    if (excluded.count == 0)
        return file.items.count;
    NSNumber *cached = [self.includedCounts objectForKey:file];
    if (cached)
        return cached.unsignedIntegerValue;
    NSUInteger count = 0;
    for (TSTeXRootSearchItem *item in file.items)
        if (![excluded containsObject:TSItemKey(item)])
            count++;
    [self.includedCounts setObject:@(count) forKey:file];
    return count;
}

- (NSUInteger)numberOfIncludedItems
{
    NSUInteger count = 0;
    for (TSTeXRootSearchFileResult *file in self.results)
        count += [self numberOfIncludedItemsInFile:file];
    return count;
}

- (NSUInteger)numberOfFilesWithIncludedItems
{
    NSUInteger count = 0;
    for (TSTeXRootSearchFileResult *file in self.results)
        if ([self numberOfIncludedItemsInFile:file] > 0)
            count++;
    return count;
}

- (NSUInteger)numberOfIncludedFiles
{
    return [self includedFiles].count;
}

- (BOOL)canReplaceAll
{
    return self.mode != TSTeXRootSearchModeFind && self.activity == TSTeXRootSearchActivityIdle && self.resultGeneration == self.generation
        && !self.reachedLimit && !self.stopped && self.project && self.numberOfIncludedItems > 0;
}

#pragma mark Stopping

- (void)stop
{
    if (self.activity == TSTeXRootSearchActivityIdle)
        return;
    self.token.cancelled = YES;
    self.token = nil;
    [self.collector cancel];
    self.collector = nil;
    self.requestNumber++;
    [self.fileResults removeAllObjects];
    self.reachedLimit = NO;
    self.stopped = YES;
    self.eventMessage = nil;
    self.resultGeneration = ++self.generation;
    self.activity = TSTeXRootSearchActivityIdle;
    [self changed];
}

@end
