// SPDX-License-Identifier: GPL-2.0-or-later
#import <Foundation/Foundation.h>
#import "TSTeXRootProject.h"

NS_ASSUME_NONNULL_BEGIN

/// What the main window's document is to the entry points (spec §2.7.1).
typedef NS_ENUM(NSInteger, TSTeXRootEntryState) {
    /// No TeX document in the main window: the items are gray.
    TSTeXRootEntryStateNoDocument = 0,
    /// The document has never been saved: gray.
    TSTeXRootEntryStateUntitled,
    /// The document's name does not end in ".tex" (lowercase): gray.
    TSTeXRootEntryStateNotTeX,
    /// The document names a root: "… with the Same TEX root…".
    TSTeXRootEntryStateChild,
    /// It names none, so it is the root: "… with This File as TEX root…".
    TSTeXRootEntryStateRoot,
} NS_SWIFT_NAME(TeXRootEntryState);

/// What the entry points of the window of the TeX sources of a root decide from a document alone: whether they can be
/// used, the root, their titles and the warning when the root cannot be used. Foundation only.
NS_SWIFT_NAME(TeXRootEntryRules)
@interface TSTeXRootEntryRules : NSObject
/// The state for a document at `url` (nil when untitled) whose text is `text`, and its root: the file it names as
/// typesetting finds it, or the document itself.
+ (TSTeXRootEntryState)stateForDocumentURL:(nullable NSURL *)url text:(nullable NSString *)text
                         allowingSourceDoc:(BOOL)allowsSourceDoc jobNameToken:(NSString *)jobNameToken
                                   rootURL:(NSURL *_Nullable *_Nullable)rootURL;
/// The state for the menus: from the text alone, without the file system (no path is resolved), so that validating
/// an item never waits for a disk. A document that names a root is a child; whether that root exists is found when
/// the item is chosen.
+ (TSTeXRootEntryState)menuStateForDocumentURL:(nullable NSURL *)url text:(nullable NSString *)text allowingSourceDoc:(BOOL)allowsSourceDoc;
/// The same for a document whose text is its file's (the external editor mode): `loader` reads it on a background
/// queue; `completion` is called on the main thread.
+ (void)menuStateForDocumentURL:(NSURL *)url textLoader:(NSString *_Nullable (^)(void))loader allowingSourceDoc:(BOOL)allowsSourceDoc
                     completion:(void (^)(TSTeXRootEntryState state))completion;
/// What choosing an item does first, all on a background queue (spec §2.9): `loader` gives the document's text (a
/// copy of the text on screen, or the file read for the external editor mode), the root is resolved (symbolic links,
/// "~", "\jobname") and checked (it exists, is a regular file, ends in ".tex"). `completion` is called on the main
/// thread with the root and its problem.
+ (void)resolveRootForDocumentURL:(NSURL *)url textLoader:(NSString *_Nullable (^)(void))loader allowingSourceDoc:(BOOL)allowsSourceDoc
                     jobNameToken:(NSString *)jobNameToken
                       completion:(void (^)(TSTeXRootEntryState state, NSURL *_Nullable rootURL, TSTeXRootProblem problem))completion;
/// The item's title in a state; `applying` for the Multiple Replace window's item.
+ (NSString *)titleForState:(TSTeXRootEntryState)state applying:(BOOL)applying;
/// The message of the warning when the root cannot be used (its path is the explanation).
+ (NSString *)messageForProblem:(TSTeXRootProblem)problem;
- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;
@end

NS_ASSUME_NONNULL_END
