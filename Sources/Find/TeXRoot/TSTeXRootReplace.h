// SPDX-License-Identifier: GPL-2.0-or-later
#import <Foundation/Foundation.h>
#import "TSTeXRootSearch.h"
#import "TSRegexFindReplacement.h"

NS_ASSUME_NONNULL_BEGIN

/// Errors of Replace All in the TeX sources of a root.
FOUNDATION_EXPORT NSErrorDomain const TSTeXRootReplaceErrorDomain;
typedef NS_ERROR_ENUM(TSTeXRootReplaceErrorDomain, TSTeXRootReplaceError) {
    /// The file is not as it was when the list was made (its content, size, date or identity), or it is gone.
    TSTeXRootReplaceErrorChanged = 1,
    /// The replaced text cannot be written in the file's encoding (never, as the list marks such files).
    TSTeXRootReplaceErrorUnencodable,
    /// The backup folder or a backup could not be made.
    TSTeXRootReplaceErrorBackup,
    /// The permissions, extended attributes or creation date could not be given to the new file: nothing was written.
    TSTeXRootReplaceErrorAttributes,
    /// Writing or putting the new file in place failed.
    TSTeXRootReplaceErrorWrite,
    /// The file written does not read back as the text meant.
    TSTeXRootReplaceErrorVerification,
    /// Stopped before the file was written.
    TSTeXRootReplaceErrorStopped,
} NS_SWIFT_NAME(TeXRootReplaceError);

/// One file's part of an approved Replace All, fixed when it is approved (spec §2.5.1a): nothing in it is computed
/// again afterwards.
NS_SWIFT_NAME(TeXRootReplaceFile)
@interface TSTeXRootReplaceFile : NSObject
@property (nonatomic, readonly) TSTeXRootProjectFile *file;
/// Replaced on screen (an open document) rather than written to the disk.
@property (nonatomic, readonly, getter=isOpenDocument) BOOL openDocument;
@property (nonatomic, readonly) NSUInteger numberOfItems;
/// The replacements, ascending and not overlapping, in `originalText`.
@property (nonatomic, readonly, copy) NSArray<TSRegexFindReplacement *> *replacements;
/// The text searched and approved, and the text with the replacements made.
@property (nonatomic, readonly, copy) NSString *originalText;
@property (nonatomic, readonly, copy) NSString *replacedText;
/// A file on the disk: the bytes to write (its encoding and byte order mark kept), and the SHA-256 of the bytes it was
/// read from.
@property (nonatomic, readonly, copy, nullable) NSData *replacedData;
@property (nonatomic, readonly, copy, nullable) NSData *originalSHA256;
- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;
@end

/// What Replace All will do, fixed when it is approved: the items on in the files that can be replaced in.
NS_SWIFT_NAME(TeXRootReplacePlan)
@interface TSTeXRootReplacePlan : NSObject
/// Nil with no item on; fails only when a text cannot be written in its file's encoding.
+ (nullable instancetype)planWithResults:(NSArray<TSTeXRootSearchFileResult *> *)results
                              isIncluded:(BOOL (NS_NOESCAPE ^)(TSTeXRootSearchItem *item, TSTeXRootSearchFileResult *file))isIncluded
                                   codec:(TSTeXRootSourceCodec *)codec error:(NSError **)error;
/// Files on the disk first (in the order of the list), then open documents (spec §2.5.5: those Undo can take back last).
@property (nonatomic, readonly, copy) NSArray<TSTeXRootReplaceFile *> *files;
@property (nonatomic, readonly) NSUInteger numberOfItems;
@property (nonatomic, readonly) NSUInteger numberOfFilesOnDisk;
/// The files on the disk whose version is no longer the one approved, in a project collected again just now: gone,
/// or with another identity, size, modification date or content (spec §2.5.1, checks 1 and 2). Open documents are
/// compared by the caller (their edits).
- (NSArray<TSTeXRootReplaceFile *> *)filesOnDiskChangedInProject:(TSTeXRootProject *)project;
- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;
@end

/// The backup of a Replace All (spec §2.5.5): a folder `TeXShop Backups/<date time>` next to the root, never one that
/// exists already ("<date time> 2", … then), with every file of the plan under its relative path and name, as it was
/// approved, with its attributes. All or nothing: on any failure the folder made is removed.
NS_SWIFT_NAME(TeXRootBackup)
@interface TSTeXRootBackup : NSObject
/// `folder` is the root's folder. A file on the disk is copied from the bytes read now, which must be those approved
/// (its SHA-256); an open document from `openDocumentData` (its text as approved, in its encoding, or in UTF-8 when it
/// cannot be: `usedUTF8` then, and the file's name goes into `notes`). Returns the folder made.
+ (nullable NSURL *)backUpPlan:(TSTeXRootReplacePlan *)plan inFolder:(NSURL *)folder date:(NSDate *)date
              openDocumentData:(NSData *_Nullable (^)(TSTeXRootReplaceFile *file, BOOL *usedUTF8))openDocumentData
                         notes:(NSArray<NSString *> *_Nullable *_Nullable)notes
                  cancellation:(nullable BOOL (^)(void))isCancelled error:(NSError **)error;
/// The name of the folder for `date`, as "2026-11-16 22.11.33", in the Gregorian calendar and the user's time zone.
+ (NSString *)folderNameForDate:(NSDate *)date;
- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;
@end

/// Writes one file on the disk (spec §2.5.4): the new bytes to a hidden temporary file in the same folder, the
/// original's permissions, extended attributes and creation date copied to it (nothing is written when they cannot
/// be), then, coordinated with NSFileCoordinator, the original read again and compared with the SHA-256 approved
/// (check 3 of §2.5.1) and replaced at once; last, the file read back strictly and compared with the text meant.
NS_SWIFT_NAME(TeXRootDiskWriter)
@interface TSTeXRootDiskWriter : NSObject
- (instancetype)initWithCodec:(TSTeXRootSourceCodec *)codec NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;
/// NO with the error (TSTeXRootReplaceErrorDomain); the original is then untouched, except after
/// TSTeXRootReplaceErrorVerification, when the new bytes are in place but do not read back as meant.
- (BOOL)writeFile:(TSTeXRootReplaceFile *)file error:(NSError **)error;
/// For the tests: called right before the original is read again for check 3, inside the coordination.
@property (nonatomic, copy, nullable) void (^beforeCheck)(NSURL *url);
/// For the tests: makes copying the attributes fail.
@property (nonatomic) BOOL failsCopyingAttributes;
@end

/// Where things are in a text after replacements in it (spec §2.6).
NS_SWIFT_NAME(TeXRootReplaceMapping)
@interface TSTeXRootReplaceMapping : NSObject
/// The ranges, none of them replaced, moved by what the replacements before each added or took away.
+ (NSArray<NSValue *> *)ranges:(NSArray<NSValue *> *)ranges afterReplacements:(NSArray<TSRegexFindReplacement *> *)replacements;
/// The two ranges share a character, or an empty one lies within the other (ends included): an item that touches an
/// item left off stays off.
+ (BOOL)range:(NSRange)a overlapsRange:(NSRange)b;
- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;
@end

NS_ASSUME_NONNULL_END
