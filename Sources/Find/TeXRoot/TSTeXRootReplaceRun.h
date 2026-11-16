// SPDX-License-Identifier: GPL-2.0-or-later
#import <Cocoa/Cocoa.h>
#import "TSTeXRootReplace.h"
#import "TSTeXRootDocumentApplier.h"

NS_ASSUME_NONNULL_BEGIN

/// What became of one file or open document of a Replace All (spec §2.5.5).
typedef NS_ENUM(NSInteger, TSTeXRootReplaceStatus) {
    TSTeXRootReplaceStatusApplied,
    TSTeXRootReplaceStatusNotApplied,
    TSTeXRootReplaceStatusFailed,
    /// An open document with part of the replacements in its text.
    TSTeXRootReplaceStatusPartial,
} NS_SWIFT_NAME(TeXRootReplaceStatus);

typedef NS_ENUM(NSInteger, TSTeXRootReplaceReason) {
    TSTeXRootReplaceReasonNone,
    /// Stopped (■, Escape, ⌘.) before it was replaced in.
    TSTeXRootReplaceReasonStopped,
    /// Not reached: a file before it failed.
    TSTeXRootReplaceReasonAfterFailure,
    /// The open document was closed, or its text is no longer the one approved.
    TSTeXRootReplaceReasonChanged,
    /// The document did not accept the change.
    TSTeXRootReplaceReasonRefused,
    /// The document could no longer be edited when the run began.
    TSTeXRootReplaceReasonNotEditable,
    /// Its text was changed meanwhile by something else.
    TSTeXRootReplaceReasonUnexpectedChange,
    /// Writing the file failed: `error` (TSTeXRootReplaceErrorDomain) says how.
    TSTeXRootReplaceReasonError,
} NS_SWIFT_NAME(TeXRootReplaceReason);

NS_SWIFT_NAME(TeXRootReplaceRecord)
@interface TSTeXRootReplaceRecord : NSObject
@property (nonatomic, readonly) TSTeXRootReplaceFile *file;
@property (nonatomic, readonly) TSTeXRootReplaceStatus status;
@property (nonatomic, readonly) TSTeXRootReplaceReason reason;
@property (nonatomic, readonly, nullable) NSError *error;
- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;
@end

NS_SWIFT_NAME(TeXRootReplaceReport)
@interface TSTeXRootReplaceReport : NSObject
/// One record for each file of the plan, in its order. Empty when nothing was done (changed files, a failed backup).
@property (nonatomic, readonly, copy) NSArray<TSTeXRootReplaceRecord *> *records;
/// The files whose version was no longer the one approved (check 2): nothing was replaced. Paths below the root's
/// folder.
@property (nonatomic, readonly, copy) NSArray<NSString *> *changedFiles;
/// The backup could not be made (not TSTeXRootReplaceErrorChanged, which gives `changedFiles`): nothing was replaced.
@property (nonatomic, readonly, nullable) NSError *backupError;
@property (nonatomic, readonly, copy, nullable) NSURL *backupFolder;
/// Open documents backed up in UTF-8, as their encoding could not hold their text.
@property (nonatomic, readonly, copy) NSArray<NSString *> *backupNotes;
@property (nonatomic, readonly) BOOL stopped;
/// Every file of the plan was replaced in.
@property (nonatomic, readonly) BOOL allApplied;
@property (nonatomic, readonly) NSUInteger numberOfAppliedItems;
@property (nonatomic, readonly) NSUInteger numberOfAppliedFiles;
- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;
@end

/// The files whose version is not the one listed (spec §2.5.1, checks 1 and 2): `listed` is the project the list was
/// made from, `now` one collected just now; only files `isIncluded` (on in the tree) of `listed` count, with every file
/// of `now` that `listed` does not have (a file added counts too, as it may have matches the list does not show). A
/// file on the disk counts by its identity, size, modification date and content; an open document by its text.
/// Returns paths below the root's folder.
FOUNDATION_EXPORT NSArray<NSString *> *TSTeXRootChangedFiles(TSTeXRootProject *listed, TSTeXRootProject *now,
                                                             BOOL (NS_NOESCAPE ^isIncluded)(TSTeXRootProjectFile *file));

/// Everything after the confirmation sheet of a Replace All (spec §2.5.5): check 2, the backup, the files on the disk
/// one by one, then the open documents, and the report. The disk is used on a background queue; the open documents
/// are changed on the main thread, a part at a time. Called and calling back on the main thread.
NS_SWIFT_NAME(TeXRootReplaceRun)
@interface TSTeXRootReplaceRun : NSObject

- (instancetype)initWithPlan:(TSTeXRootReplacePlan *)plan listedProject:(TSTeXRootProject *)listed
                       codec:(TSTeXRootSourceCodec *)codec NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;

@property (nonatomic, readonly) TSTeXRootReplacePlan *plan;
/// The backup goes next to the root (nil: none).
@property (nonatomic, copy, nullable) NSURL *backupFolder;
/// The collector of check 2, made on the main thread (it takes the open documents' texts); Stop cancels it.
@property (nonatomic, copy) TSTeXRootProjectCollector *_Nullable (^makeCollector)(void);
/// Called on a background queue before the collector collects (the open documents' files identified).
@property (nonatomic, copy, nullable) void (^prepareCollector)(TSTeXRootProjectCollector *collector);
/// The files of the listed project that are on in the tree (main thread, when check 2 starts).
@property (nonatomic, copy) BOOL (^isIncluded)(TSTeXRootProjectFile *file);
/// The text view of an open document of the plan, nil when it is closed (main thread).
@property (nonatomic, copy) NSTextView *_Nullable (^textViewForFile)(TSTeXRootReplaceFile *file);
/// The text storage of each open document of the plan when Replace All was approved (the confirmation sheet). Only
/// that text storage is replaced in: a document opened again since (another text storage, even with the same text) is
/// not (spec §2.5.1a). When nil, those of the start of the run stand.
@property (nonatomic, strong, nullable) NSMapTable<TSTeXRootReplaceFile *, NSTextStorage *> *approvedTextStorages;
/// For the backup of an open document: called on the main thread (where the document's encoding is read), it returns
/// what turns the text approved into bytes on a background queue (in UTF-8, `usedUTF8`, when the encoding cannot
/// hold it).
@property (nonatomic, copy) NSData *_Nullable (^_Nonnull (^backupEncoderForOpenDocument)(TSTeXRootReplaceFile *file))(BOOL *usedUTF8);
/// The Undo name of the replacements in an open document.
@property (nonatomic, copy) NSString *actionName;
/// The date of the backup folder (now unless set, for the tests).
@property (nonatomic, copy, nullable) NSDate *date;
@property (nonatomic, readonly, getter=isRunning) BOOL running;
/// For the tests: the writer of the files on the disk, and the applier made for each open document.
@property (nonatomic, readonly) TSTeXRootDiskWriter *writer;
@property (nonatomic, copy, nullable) void (^applierMade)(TSTeXRootDocumentApplier *applier);
/// For the tests: called on the background queue after each file written.
@property (nonatomic, copy, nullable) void (^fileWritten)(TSTeXRootReplaceFile *file);

/// The text views of the open documents are read-only, and Undo and Redo refused for them, until the report.
- (void)runWithCompletion:(void (^)(TSTeXRootReplaceReport *report))completion;
/// Stops: before the first file is written, nothing is; then, after the file being written, the rest is not; in an
/// open document, what is in is taken back (spec §2.9).
- (void)stop;

@end

NS_ASSUME_NONNULL_END
