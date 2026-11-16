// SPDX-License-Identifier: GPL-2.0-or-later
#import <Foundation/Foundation.h>
#import "TSTeXRootSearch.h"

@class TSTeXRootSearchModel;

NS_ASSUME_NONNULL_BEGIN

/// Why an open document cannot be replaced in (spec §2.5.3), added to those of TSTeXRootSearch: it cannot be edited
/// (read only, or locked by another task), or the same file is open as two documents under different names.
static const TSTeXRootSearchOnlyReason TSTeXRootSearchOnlyReasonNotEditable = (TSTeXRootSearchOnlyReason)101;
static const TSTeXRootSearchOnlyReason TSTeXRootSearchOnlyReasonOpenTwice = (TSTeXRootSearchOnlyReason)102;

/// At most this many lines of an item are shown in the list; a longer item shows them and a last line "⋯".
static const NSUInteger TSTeXRootSearchMaximumShownLines = 20;
/// The lines `text` is shown in: its lines, at most TSTeXRootSearchMaximumShownLines + 1 (the "⋯").
FOUNDATION_EXPORT NSUInteger TSTeXRootSearchShownLines(NSString *_Nullable text);

/// What the window is doing. While anything but Idle, Replace All cannot be pressed.
typedef NS_ENUM(NSInteger, TSTeXRootSearchActivity) {
    TSTeXRootSearchActivityIdle = 0,
    /// Collecting the files (spec §2.2): the progress is in `collectedFolders`, `collectedFiles` and `currentFolder`.
    TSTeXRootSearchActivityCollecting,
    /// A condition changed; the search starts after the pause (spec §2.7.3: 0.3 s).
    TSTeXRootSearchActivityWaiting,
    /// Searching and working out the replacements on the background queue.
    TSTeXRootSearchActivityComputing,
} NS_SWIFT_NAME(TeXRootSearchActivity);

/// What the model needs from TeXShop, given as blocks so that the tests can give their own. Every block is called on
/// the main thread.
NS_SWIFT_NAME(TeXRootSearchEnvironment)
@interface TSTeXRootSearchEnvironment : NSObject
/// A collector for the root, with the codec set. Called on the main thread: it only takes what must be taken there (the
/// texts of the open documents as they are now), never waiting for the file system.
@property (nonatomic, copy) TSTeXRootProjectCollector *_Nonnull (^collectorForRoot)(NSURL *rootURL);
/// Called on the background queue right before the collector collects: what needs the file system to prepare it (the
/// identities of the open documents' files, for its `openDocumentTexts`) is done here (spec §2.9).
@property (nonatomic, copy, nullable) void (^prepareCollector)(TSTeXRootProjectCollector *collector);
/// The texts to search: an open document's text as it is now (with its line ending and whether it can be edited),
/// the text read when collecting for a file that is not open.
@property (nonatomic, copy) NSArray<TSTeXRootSearchSource *> *_Nonnull (^sourcesForFiles)(NSArray<TSTeXRootProjectFile *> *files);
/// Checks that replaced text can be written in each file's encoding.
@property (nonatomic, strong, nullable) TSTeXRootSourceCodec *codec;
/// Runs a block after a delay on the main thread; the tests run it when they choose.
@property (nonatomic, copy) void (^performAfterDelay)(NSTimeInterval delay, dispatch_block_t block);
/// What tells the open documents apart: which documents are open, and on which files. When it differs from what it
/// was when the files were collected, the texts of the open documents taken then no longer stand (a document closed
/// may have had unsaved text): the files are collected again before anything is listed (spec §2.5.1, §2.5.3).
@property (nonatomic, copy, nullable) id<NSObject> _Nonnull (^documentsSignature)(void);
@end

NS_SWIFT_NAME(TeXRootSearchModelDelegate)
@protocol TSTeXRootSearchModelDelegate <NSObject>
/// Anything shown changed: the activity, the progress, the files, the results, the checks or the status.
- (void)texRootSearchModelDidChange:(TSTeXRootSearchModel *)model;
@end

/// The state of the window of the TeX sources of a root (spec §2.7): the files collected and which of them are on,
/// the conditions of the search, the results and which items are on, and the generation that tells whether the
/// list on screen is the one of the current conditions (spec §2.5.1). Main thread only; the work is done on a
/// background queue, and a result is dropped when the generation has moved on since it was started.
NS_SWIFT_NAME(TeXRootSearchModel)
@interface TSTeXRootSearchModel : NSObject

- (instancetype)initWithRootURL:(NSURL *)rootURL environment:(TSTeXRootSearchEnvironment *)environment NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;

@property (nonatomic, readonly, copy) NSURL *rootURL;
@property (nonatomic, weak, nullable) id<TSTeXRootSearchModelDelegate> delegate;
/// 0.3 s (spec §2.7.3).
@property (nonatomic) NSTimeInterval pause;
/// The limits of TSTeXRootSearch, smaller in the tests.
@property (nonatomic) NSUInteger maximumItemsPerFile;
@property (nonatomic) NSUInteger maximumItems;

#pragma mark Conditions
/// Each setter moves the generation on at once and searches again after the pause, with every item on again.
@property (nonatomic) TSTeXRootSearchMode mode;
@property (nonatomic, copy) NSString *findString;
@property (nonatomic, copy) NSString *replaceString;
@property (nonatomic) TSRegexFindOptions options;
@property (nonatomic) TSRegexReplacementSyntax replacementSyntax;
@property (nonatomic, strong, nullable) TSRegexMultipleReplace *multipleReplace;
/// Sets every condition at once (opening the window), with one change of generation.
- (void)setMode:(TSTeXRootSearchMode)mode findString:(NSString *)findString replaceString:(NSString *)replaceString
        options:(TSRegexFindOptions)options syntax:(TSRegexReplacementSyntax)syntax multipleReplace:(nullable TSRegexMultipleReplace *)set;
/// Searches now, without waiting for the pause (Return in a field).
- (void)searchNow;

#pragma mark Files
/// Collects the files, then searches them (opening the window, ↻). Files that were off stay off when they are found
/// again (by their identifier); files new to the list are on.
- (void)collect;
@property (nonatomic, readonly, nullable) TSTeXRootProject *project;
/// Folders and files looked at, and the folder being read, while collecting.
@property (nonatomic, readonly) NSUInteger collectedFolders;
@property (nonatomic, readonly) NSUInteger collectedFiles;
@property (nonatomic, readonly, copy, nullable) NSString *currentFolder;
/// Why the last collection gave nothing (the root went away, …); TSTeXRootCollectionFailureNone otherwise.
@property (nonatomic, readonly) TSTeXRootCollectionFailure collectionFailure;
- (BOOL)isFileIncluded:(TSTeXRootProjectFile *)file;
/// Why the file cannot be replaced in: that of its results, else that of its text as last searched, else the
/// collector's.
- (TSTeXRootSearchOnlyReason)searchOnlyReasonOfFile:(TSTeXRootProjectFile *)file;
/// The items of the file in the list (0 when it is off or has none).
- (NSUInteger)numberOfItemsInFile:(TSTeXRootProjectFile *)file;
/// Turning files off takes their items out of the list at once; turning them on searches only them.
- (void)setFiles:(NSArray<TSTeXRootProjectFile *> *)files included:(BOOL)included;
/// An open document's text changed: only that file is searched again.
- (void)textDidChangeForFileWithIdentifier:(id<NSObject, NSCopying>)identifier;
/// A document became read-only or editable again: every file is searched again, from new sources.
- (void)documentsDidChange;
/// A document was opened, closed or renamed: the files are collected again, also while they are being collected.
- (void)openDocumentsDidChange;
/// How many times the files were collected (for the tests).
@property (nonatomic, readonly) NSUInteger numberOfCollections;

#pragma mark Results
@property (nonatomic, readonly) TSTeXRootSearchActivity activity;
/// Moves on with every change of what Replace All would do.
@property (nonatomic, readonly) NSUInteger generation;
/// The generation of the list shown.
@property (nonatomic, readonly) NSUInteger resultGeneration;
/// The files on, with items, in the order of the project.
@property (nonatomic, readonly, copy) NSArray<TSTeXRootSearchFileResult *> *results;
@property (nonatomic, readonly) BOOL reachedLimit;
/// The find string or a rule cannot be used: the list is empty.
@property (nonatomic, readonly, nullable) NSError *queryError;
- (BOOL)isItemIncluded:(TSTeXRootSearchItem *)item inFile:(TSTeXRootSearchFileResult *)file;
/// The lines the item at `index` of `file` takes in the list (before or after, whichever is longer, in the mode of
/// the search): worked out with the search, so that the list never measures the texts on the main thread.
- (NSUInteger)shownLinesOfItemAtIndex:(NSUInteger)index inFile:(TSTeXRootSearchFileResult *)file;
/// Only in the replacing modes, and only in files that can be replaced in.
- (void)setItems:(NSArray<TSTeXRootSearchItem *> *)items inFile:(TSTeXRootSearchFileResult *)file included:(BOOL)included;
/// Items that will be replaced, and the files they are in.
@property (nonatomic, readonly) NSUInteger numberOfIncludedItems;
@property (nonatomic, readonly) NSUInteger numberOfFilesWithIncludedItems;
@property (nonatomic, readonly) NSUInteger numberOfItems;
@property (nonatomic, readonly) NSUInteger numberOfIncludedFiles;
/// Replace All can be pressed: a replacing mode, the list of the current generation, nothing running, no limit
/// reached, and at least one item on (spec §2.5.1).
@property (nonatomic, readonly) BOOL canReplaceAll;

#pragma mark Status
/// Stopped while collecting or computing: the list is empty and the status says so.
@property (nonatomic, readonly, getter=isStopped) BOOL stopped;
/// What just happened ("Replaced 5 items in 4 files"): kept over the search that follows it, cleared by the next
/// change the user makes (spec §2.7.4).
@property (nonatomic, copy, nullable) NSString *eventMessage;
/// Stops collecting or computing (■, Escape, ⌘.).
- (void)stop;

/// After Replace All (spec §2.5.5, §2.6): collects the files again and searches them with the same conditions, keeping
/// `message` in the status line. An item of the new list that overlaps a range of `rangesOff` (by the file's path below
/// the root's folder, as a file written gets another identity: the items that were off, moved to where they are in the
/// replaced text) is off; items off in files not replaced in stay off as they were. The ranges of a file are kept until
/// its items are listed again, through a stop or another collection; new conditions drop them all (every item is on),
/// an edit of the file drops its own.
- (void)searchAgainAfterReplacingWithRangesOff:(NSDictionary<NSString *, NSArray<NSValue *> *> *)rangesOff message:(NSString *)message;

@end

NS_ASSUME_NONNULL_END
