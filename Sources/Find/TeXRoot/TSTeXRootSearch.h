// SPDX-License-Identifier: GPL-2.0-or-later
#import <Foundation/Foundation.h>
#import "TSRegexFindOptions.h"
#import "TSRegexReplacementTemplate.h"
#import "TSTeXRootProject.h"

@class TSRegexMultipleReplace;

NS_ASSUME_NONNULL_BEGIN

/// What the window of the TeX sources of a root does: search, replace with one find and replace pair, or apply a
/// multiple replacement set.
typedef NS_ENUM(NSInteger, TSTeXRootSearchMode) {
    TSTeXRootSearchModeFind = 0,
    TSTeXRootSearchModeReplace,
    TSTeXRootSearchModeMultipleReplace,
} NS_SWIFT_NAME(TeXRootSearchMode);

/// Why a file that could be replaced in on its own cannot be with this replacement (added to the collector's reasons):
/// the replaced text cannot be written in the file's encoding.
static const TSTeXRootSearchOnlyReason TSTeXRootSearchOnlyReasonUnencodable = (TSTeXRootSearchOnlyReason)100;

/// The text of one file to search, taken when the search starts.
NS_SWIFT_NAME(TeXRootSearchSource)
@interface TSTeXRootSearchSource : NSObject
@property (nonatomic, readonly) TSTeXRootProjectFile *file;
@property (nonatomic, readonly, copy) NSString *text;
/// The text is an open document's (copied on the main thread), not the file on the disk.
@property (nonatomic, readonly, getter=isOpenDocument) BOOL openDocument;
/// An open document's line ending, as the Advanced Find panel gives it (nil keeps the replacement's line breaks).
@property (nonatomic, readonly, copy, nullable) NSString *lineEnding;
/// The file's own reason (the collector's), or the caller's for an open document (one that cannot be edited).
@property (nonatomic, readonly) TSTeXRootSearchOnlyReason searchOnlyReason;
/// An open document.
- (instancetype)initWithFile:(TSTeXRootProjectFile *)file openDocumentText:(NSString *)text lineEnding:(nullable NSString *)lineEnding
            searchOnlyReason:(TSTeXRootSearchOnlyReason)reason NS_DESIGNATED_INITIALIZER;
/// The file as it was read from the disk by the collector.
- (instancetype)initWithFile:(TSTeXRootProjectFile *)file;
- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;
@end

/// What to search for and what to put in its place. Immutable.
NS_SWIFT_NAME(TeXRootSearchQuery)
@interface TSTeXRootSearchQuery : NSObject
@property (nonatomic, readonly) TSTeXRootSearchMode mode;
@property (nonatomic, readonly, copy, nullable) NSString *findString;
@property (nonatomic, readonly) TSRegexFindOptions options;
@property (nonatomic, readonly, copy, nullable) NSString *replaceString;
@property (nonatomic, readonly) TSRegexReplacementSyntax replacementSyntax;
@property (nonatomic, readonly, nullable) TSRegexMultipleReplace *multipleReplace;
/// Multiple replacement: why enabled rules will be skipped (an empty or invalid find string), by the rule's index.
@property (nonatomic, readonly, copy) NSDictionary<NSNumber *, NSError *> *ruleErrors;
/// Fails as the panel does (an empty find string, an invalid pattern), with the TSRegexFind error.
+ (nullable instancetype)findQueryWithString:(NSString *)findString options:(TSRegexFindOptions)options error:(NSError **)error;
+ (nullable instancetype)replaceQueryWithString:(NSString *)findString replacement:(NSString *)replaceString
                                        options:(TSRegexFindOptions)options syntax:(TSRegexReplacementSyntax)syntax
                                          error:(NSError **)error;
+ (instancetype)multipleReplaceQueryWithSet:(TSRegexMultipleReplace *)set;
- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;
@end

/// One line of the list: a match (find and replace), or a hunk of changed lines (multiple replacement).
NS_SWIFT_NAME(TeXRootSearchItem)
@interface TSTeXRootSearchItem : NSObject
/// In the file's text: the match, or the lines a hunk changes (with their line breaks).
@property (nonatomic, readonly) NSRange range;
/// What takes the place of `range` when the item is replaced; nil in find mode.
@property (nonatomic, readonly, copy, nullable) NSString *replacement;
/// The line the item starts on, from 1: line breaks are CR, LF, CRLF, NEL, U+2028 and U+2029, as in the editor.
@property (nonatomic, readonly) NSUInteger lineNumber;
/// The lines the item touches. The last line break is left out unless the item changes it.
@property (nonatomic, readonly, copy) NSString *beforeText;
/// In `beforeText`: what is matched, or what a hunk changes (empty for an empty match: a mark at its place).
@property (nonatomic, readonly) NSRange beforeHighlight;
/// The same lines with only this item replaced; nil in find mode.
@property (nonatomic, readonly, copy, nullable) NSString *afterText;
/// In `afterText`: what was put in.
@property (nonatomic, readonly) NSRange afterHighlight;
- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;
@end

NS_SWIFT_NAME(TeXRootSearchFileResult)
@interface TSTeXRootSearchFileResult : NSObject
@property (nonatomic, readonly) TSTeXRootSearchSource *source;
/// In the order of the text; they never overlap.
@property (nonatomic, readonly, copy) NSArray<TSTeXRootSearchItem *> *items;
/// The source's reason, or TSTeXRootSearchOnlyReasonUnencodable when the text with every item replaced cannot be
/// written in the file's encoding (files on the disk, in the replacing modes).
@property (nonatomic, readonly) TSTeXRootSearchOnlyReason searchOnlyReason;
/// More items than the limit per file, or the limit in all was reached in this file: the rest were not listed.
@property (nonatomic, readonly, getter=isTruncated) BOOL truncated;
/// The text with the items at `indexes` replaced and the others left as they are (the replacing modes).
- (NSString *)textReplacingItemsAtIndexes:(NSIndexSet *)indexes;
- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;
@end

NS_SWIFT_NAME(TeXRootSearchResult)
@interface TSTeXRootSearchResult : NSObject
@property (nonatomic, readonly) TSTeXRootSearchMode mode;
/// The generation the search was started for; the window drops a result of an older generation.
@property (nonatomic, readonly) NSUInteger generation;
/// Only the files with items, in the order of the sources.
@property (nonatomic, readonly, copy) NSArray<TSTeXRootSearchFileResult *> *files;
@property (nonatomic, readonly) NSUInteger numberOfItems;
/// A limit was reached (per file or in all): not every item is listed, and nothing may be replaced.
@property (nonatomic, readonly) BOOL reachedLimit;
- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;
@end

/// Searches the files of a project, and computes the replacements and their before and after lines as Replace All
/// and Multiple Replace of the Advanced Find panel compute them. Pure computation; meant for a background queue.
///
/// Line endings. In an open document the find strings and the replaced text take the document's line ending, as in
/// the panel. A file on the disk keeps its line endings, which may be mixed (spec §2.5.4): a line break in the find
/// strings is the file's first line ending (LF when it has none), and a line break put in by a replacement takes the
/// line ending of the line where the match starts (the file's first line ending when that line has none, LF when the
/// file has none).
///
/// Multiple replacement. The rules are applied one after another to the whole text, as in the panel. The original
/// and the result are then compared line by line (a line keeps its line break; a last line without one is a line):
/// the parts that the replacements touched are widened to whole lines, and each such part is compared with Myers's
/// algorithm, so that unchanged lines inside it split it. A part needing more than `maximumLineEdits` line edits is
/// one hunk. Hunks with no unchanged line between them are one hunk.
NS_SWIFT_NAME(TeXRootSearch)
@interface TSTeXRootSearch : NSObject
/// 5,000 items per file, 500,000 in all, as CotEditor's folder search.
@property (class, nonatomic, readonly) NSUInteger defaultMaximumItemsPerFile;
@property (class, nonatomic, readonly) NSUInteger defaultMaximumItems;
/// 1,024 line edits for one part of a multiple replacement (see above).
@property (class, nonatomic, readonly) NSUInteger maximumLineEdits;

/// Nil once `isCancelled` has returned YES. `codec` checks that the replaced text of a file on the disk can be written
/// in its encoding; without it nothing is checked. `progress` is told how many sources are done.
+ (nullable TSTeXRootSearchResult *)searchSources:(NSArray<TSTeXRootSearchSource *> *)sources
                                            query:(TSTeXRootSearchQuery *)query
                                       generation:(NSUInteger)generation
                                            codec:(nullable TSTeXRootSourceCodec *)codec
                              maximumItemsPerFile:(NSUInteger)maximumItemsPerFile
                                     maximumItems:(NSUInteger)maximumItems
                                     cancellation:(nullable BOOL (^)(void))isCancelled
                                         progress:(nullable void (^)(NSUInteger done, NSUInteger total))progress;

/// The line break that ends the line containing `index` in `text`; for a last line without one, the first line break
/// of the text; LF when the text has none.
+ (NSString *)lineEndingAtIndex:(NSUInteger)index inText:(NSString *)text;
/// The first line break of `text`, LF when it has none.
+ (NSString *)firstLineEndingInText:(NSString *)text;
- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;
@end

NS_ASSUME_NONNULL_END
