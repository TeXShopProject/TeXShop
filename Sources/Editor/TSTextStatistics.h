// SPDX-License-Identifier: GPL-2.0-or-later
/*
 * TSTextStatistics.h
 *
 * One count of Text Statistics: the characters, words and lines of the source as the
 * status bar counts them, and of the text that detex leaves when it removes the TeX
 * commands, with the files read by \input and \include. The text (the selection, when
 * there is one) is written to a temporary file that detex reads from the document's
 * folder, so the document need not be saved; the file is removed afterwards. detex's
 * output is counted here, as the status bar counts, not with wc.
 *
 * The characters can also be counted with options, as CotEditor's Advanced Character Count
 * counts them: line endings and whitespace left out, a run of whitespace taken as one, a
 * Unicode normalization first, and a unit other than the character (Unicode scalars, UTF-16
 * code units, or the bytes of an encoding). The options are kept for the whole application,
 * except the encoding, which is the document's each time the popover opens.
 */

#import <Foundation/Foundation.h>
#import "TSStatusBarCounting.h"

NS_ASSUME_NONNULL_BEGIN

/// What the characters are counted in.
typedef NS_ENUM(NSInteger, TSCharacterUnit) {
    TSCharacterUnitGraphemeCluster,   // as the status bar counts
    TSCharacterUnitUnicodeScalar,
    TSCharacterUnitUTF16,
    TSCharacterUnitByte,              // in the options' encoding
};

/// The Unicode normalization applied before the characters are counted.
typedef NS_ENUM(NSInteger, TSUnicodeNormalization) {
    TSUnicodeNormalizationNone,
    TSUnicodeNormalizationNFC,
    TSUnicodeNormalizationNFD,
    TSUnicodeNormalizationNFKC,
    TSUnicodeNormalizationNFKD,
    TSUnicodeNormalizationNFKCCaseFold,
    TSUnicodeNormalizationModifiedNFC,  // NFC except U+2000–U+2FFF, U+F900–U+FAFF and U+2F800–U+2FAFF, as HFS+ leaves them
    TSUnicodeNormalizationModifiedNFD,  // NFD except the same ranges
};

/// How Text Statistics counts the characters.
@interface TSCharacterCountOptions : NSObject <NSCopying>
/// LF, CR, CR LF, NEL, LINE SEPARATOR and PARAGRAPH SEPARATOR are not counted.
@property (nonatomic) BOOL ignoresLineEndings;
/// Tabs, the space separators (U+0020, U+00A0, U+3000 and the like), VT and FF are not counted.
@property (nonatomic) BOOL ignoresWhitespace;
/// A run of whitespace and line endings that are counted counts as its first one.
@property (nonatomic) BOOL treatsConsecutiveWhitespaceAsOne;
@property (nonatomic) TSUnicodeNormalization normalization;
@property (nonatomic) TSCharacterUnit unit;
/// The encoding of TSCharacterUnitByte. Not saved.
@property (nonatomic) NSStringEncoding encoding;
/// The text as the encoding writes it (TeXShop writes a backslash as a yen sign in some Japanese encodings), or nil.
@property (nonatomic, copy, nullable) NSString *_Nonnull (^textForEncoding)(NSString *text, NSStringEncoding encoding);
/// The options kept in the settings, with UTF-8 as the encoding.
+ (instancetype)savedOptions;
/// Keeps the options in the settings, all but the encoding.
- (void)save;
/// YES when the characters are counted as the status bar counts them.
@property (nonatomic, readonly, getter=isDefault) BOOL isDefault;
@end

/// The count when a character cannot be written in the encoding of TSCharacterUnitByte.
extern const NSUInteger TSCharacterCountUnencodable;
/// The number of characters of `string` counted with `options`; NSNotFound when `cancel` stopped it.
NSUInteger TSCharacterCountWithOptions(NSString *string, TSCharacterCountOptions *options, TSStatusBarCancel _Nullable cancel);

typedef NS_ENUM(NSInteger, TSTextStatisticsState) {
    TSTextStatisticsCounting,
    TSTextStatisticsDone,
    TSTextStatisticsDetexMissing,
    TSTextStatisticsDetexFailed,
};

@interface TSTextStatisticsResult : NSObject
@property (nonatomic, readonly) TSTextStatisticsState state;
/// YES when the selection was counted, NO for the whole document.
@property (nonatomic, readonly) BOOL selection;
/// The source as the status bar counts it (lines, characters, words).
@property (nonatomic, readonly) TSStatusBarCounts source;
/// The text that detex leaves; NSNotFound while counting or when detex did not run.
@property (nonatomic, readonly) TSStatusBarCounts text;
/// When the count started.
@property (nonatomic, readonly) NSDate *date;
/// The characters of the source and of the text counted with `options`: NSNotFound while counting or when detex did
/// not run, TSCharacterCountUnencodable when the encoding cannot write them.
@property (nonatomic, readonly) NSUInteger sourceCharacters, textCharacters;
@property (nonatomic, readonly, copy) TSCharacterCountOptions *options;
/// What was counted: the source (the selection, when there is one) and what detex left of it (nil when detex did not run).
@property (nonatomic, readonly, copy) NSString *sourceString;
@property (nonatomic, readonly, copy, nullable) NSString *textString;
@end

@interface TSTextStatistics : NSObject

/// The detex that the TeX bin folder (the TetexBinPath setting) holds, or nil.
+ (nullable NSURL *)detexInFolder:(nullable NSString *)binFolder;

/// Starts a count of `ranges` of `string` (the whole text when no range holds characters). `folder` is where detex
/// looks for the files of \input and \include (nil: the temporary folder); `encoding` is the document's, for the file
/// detex reads and for what it writes. A count already running is stopped first. `completion` runs on the main
/// queue, once, unless the count is stopped.
- (void)countString:(NSString *)string ranges:(NSArray<NSValue *> *)ranges folder:(nullable NSURL *)folder
              detex:(nullable NSURL *)detex encoding:(NSStringEncoding)encoding options:(TSCharacterCountOptions *)options
         completion:(void (^)(TSTextStatisticsResult *result))completion;
/// Counts the characters of what `result` counted again with other options, without running detex. A count already
/// running is stopped first. `completion` runs on the main queue with the new result, once, unless the count is stopped.
- (void)recountCharactersOfResult:(TSTextStatisticsResult *)result options:(TSCharacterCountOptions *)options
                       completion:(void (^)(TSTextStatisticsResult *result))completion;
/// Stops the running count, if any: detex is terminated and the temporary file removed.
- (void)stop;
/// YES while detex runs or its output is counted.
@property (nonatomic, readonly, getter=isRunning) BOOL running;
/// The temporary file of the running count, for the tests.
@property (nonatomic, readonly, nullable) NSURL *temporaryFile;

/// The text that `ranges` select in `string`, the ranges joined by a line end, or the whole string when none holds characters.
+ (NSString *)countedTextOfString:(NSString *)string ranges:(NSArray<NSValue *> *)ranges selection:(BOOL *_Nullable)selection;

@end

NS_ASSUME_NONNULL_END
